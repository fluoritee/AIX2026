#include "additionally.h"    // some definitions from: im2col.h, blas.h, list.h, utils.h, activations.h, tree.h, layer.h, network.h
#include <stdlib.h>
#include <math.h>

#define GEMMCONV

#define MAX_VAL_8       127         // 7-bit (1-bit sign)
#define MAX_VAL_16      32767       // 15-bit (1-bit sign)
#define MAX_VAL_32      2147483647  // 31-bit (1-bit sign)
#define MAX_VAL_UINT_8  255         // 8-bit (Unsigned, for Input Activations)

int const run_single_image_test = 1;

// [추가] 오름차순 정렬을 위한 비교 함수 (99.9% Percentile 탐색용)
int compare_floats(const void* a, const void* b) {
    float fa = *(const float*)a;
    float fb = *(const float*)b;
    return (fa > fb) - (fa < fb);
}

int max_abs(int src, int max_val)
{
    if (abs(src) > abs(max_val)) src = (src > 0) ? max_val : -max_val - 1;
    return src;
}

short int max_abs_short(short int src, short int max_val)
{
    if (abs(src) > abs(max_val)) src = (src > 0) ? max_val : -max_val - 1;
    return src;
}

// [수정] im2col.c - 입력 데이터를 uint8_t로 안전하게 처리하도록 변경
uint8_t im2col_get_pixel_uint8(uint8_t* im, int height, int width, int channels,
    int row, int col, int channel, int pad)
{
    row -= pad;
    col -= pad;

    if (row < 0 || col < 0 ||
        row >= height || col >= width) return 0;
    return im[col + width * (row + height * channel)];
}

// [수정] im2col.c - 부호 없는 UINT8 배열 처리
void im2col_cpu_uint8(uint8_t* data_im,
    int channels, int height, int width,
    int ksize, int stride, int pad, uint8_t* data_col)
{
    int c, h, w;
    int height_col = (height + 2 * pad - ksize) / stride + 1;
    int width_col = (width + 2 * pad - ksize) / stride + 1;

    int channels_col = channels * ksize * ksize;
    for (c = 0; c < channels_col; ++c) {
        int w_offset = c % ksize;
        int h_offset = (c / ksize) % ksize;
        int c_im = c / ksize / ksize;
        for (h = 0; h < height_col; ++h) {
            for (w = 0; w < width_col; ++w) {
                int im_row = h_offset + h * stride;
                int im_col = w_offset + w * stride;
                int col_index = (c * height_col + h) * width_col + w;
                data_col[col_index] = im2col_get_pixel_uint8(data_im, height, width, channels,
                    im_row, im_col, c_im, pad);
            }
        }
    }
}

// [수정] B 행렬(입력 데이터)을 uint8_t로 변경하여 음수 역전 현상 방지
void gemm_nn_int8_int16(int M, int N, int K, int8_t ALPHA,
    int8_t* A, int lda,
    uint8_t* B, int ldb,
    int16_t* C, int ldc)
{
    int32_t* c_tmp = calloc(N, sizeof(int32_t));
    int i, j, k;
    for (i = 0; i < M; ++i) {
        for (k = 0; k < K; ++k) {
            register int16_t A_PART = ALPHA * A[i * lda + k];
            for (j = 0; j < N; ++j) {
                c_tmp[j] += A_PART * B[k * ldb + j]; // B는 부호 없는 값으로 안전하게 확장됨
            }
        }
        for (j = 0; j < N; ++j) {
            C[i * ldc + j] += max_abs(c_tmp[j], MAX_VAL_16);
            c_tmp[j] = 0;
        }
    }
    free(c_tmp);
}

// [수정] B 행렬(입력 데이터)을 uint8_t로 변경
void gemm_nn_int8_int32(int M, int N, int K, int8_t ALPHA,
    int8_t* A, int lda,
    uint8_t* B, int ldb,
    int32_t* C, int ldc)
{
    int32_t* c_tmp = calloc(N, sizeof(int32_t));
    int i, j, k;
    for (i = 0; i < M; ++i) {
        for (k = 0; k < K; ++k) {
            register int16_t A_PART = ALPHA * A[i * lda + k];
            for (j = 0; j < N; ++j) {
                c_tmp[j] += A_PART * B[k * ldb + j];
            }
        }
        for (j = 0; j < N; ++j) {
            C[i * ldc + j] += max_abs(c_tmp[j], MAX_VAL_32);
            c_tmp[j] = 0;
        }
    }
    free(c_tmp);
}

void forward_convolutional_layer_q(network net, layer l, network_state state)
{
    int out_h = (l.h + 2 * l.pad - l.size) / l.stride + 1;
    int out_w = (l.w + 2 * l.pad - l.size) / l.stride + 1;
    int i, j;
    int const out_size = out_h * out_w;

    typedef int32_t conv_t;
    conv_t* output_q = calloc(l.outputs, sizeof(conv_t));

    // [핵심 수정] 입력 데이터를 UINT8 (0~255) 공간으로 가공
    uint8_t* input_u8 = (uint8_t*)calloc(l.inputs, sizeof(uint8_t));
    for (int z = 0; z < l.inputs; ++z) {
        float src_f = state.input[z] * l.input_quant_multiplier;
        int32_t src = (int32_t)roundf(src_f);

        // ReLU의 특성을 반영: 0 미만은 자르고, 255를 한계로 설정
        if (src < 0) src = 0;
        if (src > 255) src = 255;

        input_u8[z] = (uint8_t)src;
    }
    state.input_uint8 = (int8_t*)input_u8; // 구조체 호환을 위한 단순 캐스팅 보존

    if (run_single_image_test) {
        char file_input_femap[100];
        snprintf(file_input_femap, sizeof(file_input_femap), "log_feamap/CONV%02d_input.hex", state.index);
        FILE* fp = fopen(file_input_femap, "w");
        for (int chn = 0; chn < l.c; chn++) {
            for (int idx = 0; idx < l.h * l.w; idx++) {
                int i = chn * l.h * l.w + idx;
                fprintf(fp, "%02x\n", input_u8[i]);
            }
        }
        if (fp) fclose(fp);
    }

    int m = l.n;
    int k = l.size * l.size * l.c;
    int n = out_h * out_w;
    int8_t* a = l.weights_int8;
    uint8_t* b = (uint8_t*)state.workspace;
    conv_t* c = output_q;

    // [수정] uint8_t 전용 함수 호출
    im2col_cpu_uint8(input_u8, l.c, l.h, l.w, l.size, l.stride, l.pad, b);

    int t;
#pragma omp parallel for
    for (t = 0; t < m; ++t) {
        gemm_nn_int8_int32(1, n, k, 1, a + t * k, k, b, n, c + t * n, n);
    }
    free(input_u8);

    for (int fil = 0; fil < l.n; ++fil) {
        for (j = 0; j < out_size; ++j) {
            output_q[fil * out_size + j] = output_q[fil * out_size + j] + l.biases_quant[fil];
        }
    }

    if (l.activation == RELU) {
        for (i = 0; i < l.n * out_size; ++i) {
            output_q[i] = (output_q[i] > 0) ? output_q[i] : 0;
        }
    }

    float ALPHA1 = 1 / (l.input_quant_multiplier * l.weights_quant_multiplier);
    for (i = 0; i < l.outputs; ++i) {
        l.output[i] = output_q[i] * ALPHA1;
    }

    if (run_single_image_test) {
        int z;
        int next_input_quant_multiplier = 1;
        for (z = state.index + 1; z < net.n; ++z) {
            if (net.layers[z].type == CONVOLUTIONAL) {
                next_input_quant_multiplier = net.layers[z].input_quant_multiplier;
                break;
            }
        }
        char file_output_femap[100];
        snprintf(file_output_femap, sizeof(file_output_femap), "log_feamap/CONV%02d_output.hex", state.index);
        FILE* fp = fopen(file_output_femap, "w");
        for (int chn = 0; chn < l.n; chn++) {
            for (int idx = 0; idx < out_size; idx++) {
                int i = chn * out_size + idx;
                float src_f = l.output[i] * next_input_quant_multiplier;
                int32_t src = (int32_t)roundf(src_f);
                if (src < 0) src = 0;
                if (src > 255) src = 255;
                fprintf(fp, "%02x\n", (uint8_t)src);
            }
        }
        if (fp) fclose(fp);
    }
    free(output_q);
}

void yolov2_forward_network_q(network net, network_state state)
{
    state.workspace = net.workspace;
    int i;
    for (i = 0; i < net.n; ++i) {
        state.index = i;
        layer l = net.layers[i];

        if (l.type == CONVOLUTIONAL) {
            forward_convolutional_layer_q(net, l, state);
        }
        else if (l.type == MAXPOOL) {
            forward_maxpool_layer_cpu(l, state);
        }
        else if (l.type == ROUTE) {
            forward_route_layer_cpu(l, state);
        }
        else if (l.type == REORG) {
            forward_reorg_layer_cpu(l, state);
        }
        else if (l.type == UPSAMPLE) {
            forward_upsample_layer_cpu(l, state);
        }
        else if (l.type == SHORTCUT) {
            forward_shortcut_layer_cpu(l, state);
        }
        else if (l.type == YOLO) {
            forward_yolo_layer_cpu(l, state);
        }
        else if (l.type == REGION) {
            forward_region_layer_cpu(l, state);
        }
        state.input = l.output;
    }
}

float* network_predict_quantized(network net, float* input)
{
    network_state state;
    state.net = net;
    state.index = 0;
    state.input = input;
    state.truth = 0;
    state.train = 0;
    state.delta = 0;

    yolov2_forward_network_q(net, state);
    int i;
    for (i = net.n - 1; i > 0; --i) if (net.layers[i].type != COST) break;
    return net.layers[i].output;
}

/* Quantization-related */

void do_quantization(network net) {
    int counter = 0;
    int j;

#define TOTAL_CALIB_LAYER 11

    // Weight 배열은 초기값이며, 아래의 99.9% Profiling을 통해 자동으로 덮어씌워집니다.
    float weight_quant_multiplier[TOTAL_CALIB_LAYER] = {
      16, 128, 128, 128, 128, 128, 128, 128, 128, 128, 128
    };

    // Input Multiplier는 현재 설정하신 값을 그대로 유지합니다. UINT8 확장에 의해 여유 폭이 생겼습니다.
    float input_quant_multiplier[TOTAL_CALIB_LAYER] = {
     128,   8,  16,  16,  16,  16,  32,  32,  32,  32,   8
    };

    // [핵심 수정] 99.9% Percentile 기반 Weight 분포 자동 보정 로직
    printf("=== Weight Distribution Profiling (99.9%% Percentile) ===\n");
    printf("Layer   wmax_999  optimal_mult\n");
    int cnt = 0;
    for (j = 0; j < net.n; ++j) {
        layer* l = &net.layers[j];
        if (l->type != CONVOLUTIONAL) continue;

        size_t filter_size = l->size * l->size * l->c;
        int total_weights = l->n * (int)filter_size;

        float* abs_weights = (float*)malloc(total_weights * sizeof(float));
        for (int i = 0; i < total_weights; ++i) {
            abs_weights[i] = fabs(l->weights[i]);
        }

        qsort(abs_weights, total_weights, sizeof(float), compare_floats);

        int target_index = (int)(total_weights * 0.999f);
        if (target_index >= total_weights) target_index = total_weights - 1;
        float wmax_999 = abs_weights[target_index];

        if (wmax_999 < 0.0001f) wmax_999 = 0.0001f;

        float raw = 127.0f / wmax_999;
        int log2_w = (int)roundf(log2f(raw));

        if (log2_w < 2) log2_w = 2;
        if (log2_w > 8) log2_w = 8;
        int opt = 1 << log2_w;

        // 도출된 최적의 Multiplier를 배열에 자동 적용
        weight_quant_multiplier[cnt] = (float)opt;

        printf(" CONV%02d: \twmax_999=%.4f \toptimal=%d\n", j, wmax_999, opt);

        free(abs_weights);
        cnt++;
    }
    printf("========================================================\n");

    printf("Multipler    Input    Weight    Bias\n");
    counter = 0;
    for (j = 0; j < net.n; ++j) {
        layer* l = &net.layers[j];

        if (l->type == CONVOLUTIONAL) {
            size_t const filter_size = l->size * l->size * l->c;
            int i, fil;

            l->input_quant_multiplier = (counter < TOTAL_CALIB_LAYER) ? input_quant_multiplier[counter] : 16;
            l->weights_quant_multiplier = (counter < TOTAL_CALIB_LAYER) ? weight_quant_multiplier[counter] : 16;
            ++counter;

            for (fil = 0; fil < l->n; ++fil) {
                for (i = 0; i < filter_size; ++i) {
                    float w = l->weights[fil * filter_size + i] * l->weights_quant_multiplier;
                    l->weights_int8[fil * filter_size + i] = max_abs((int)roundf(w), MAX_VAL_8);
                }
            }

            float biases_multiplier = (l->weights_quant_multiplier * l->input_quant_multiplier);
            for (fil = 0; fil < l->n; ++fil) {
                float b = l->biases[fil] * biases_multiplier;
                l->biases_quant[fil] = max_abs((int)roundf(b), MAX_VAL_16);
            }

            printf(" CONV%02d: \t%g \t%g \t%g \n", j, l->input_quant_multiplier, l->weights_quant_multiplier, biases_multiplier);
        }
    }
}

void save_quantized_model(network net) {
    int j;
    for (j = 0; j < net.n; ++j) {
        layer* l = &net.layers[j];
        if (l->type == CONVOLUTIONAL) {
            size_t filter_size = l->size * l->size * l->c;
            printf(" Saving quantized weights, bias, and scale for CONV%02d \n", j);

            char weightfile[100];
            char biasfile[100];
            char scalefile[100];

            sprintf(weightfile, "log_param/CONV%02d_param_weight.hex", j);
            sprintf(biasfile, "log_param/CONV%02d_param_biases.hex", j);
            sprintf(scalefile, "log_param/CONV%02d_param_scales.hex", j);
            FILE* fp_w = fopen(weightfile, "w");
            FILE* fp_b = fopen(biasfile, "w");
            FILE* fp_s = fopen(scalefile, "w");

            int f;
            for (f = 0; f < l->n; f++) {
                for (int i = 0; i < filter_size; ++i) {
                    int w_index = f * filter_size + i;
                    fprintf(fp_w, "%02x\n", (uint8_t)l->weights_int8[w_index]);
                }
                fprintf(fp_b, "%04x\n", (uint16_t)l->biases_quant[f]);

                int next_input_quant_multiplier = 1;
                for (int z = l->index + 1; z < net.n; ++z) {
                    if (net.layers[z].type == CONVOLUTIONAL) {
                        next_input_quant_multiplier = net.layers[z].input_quant_multiplier;
                        break;
                    }
                }

                int scale = (l->input_quant_multiplier * l->weights_quant_multiplier) / next_input_quant_multiplier;
                fprintf(fp_s, "%04x\n", (uint16_t)scale);
            }

            if (fp_w) fclose(fp_w);
            if (fp_b) fclose(fp_b);
            if (fp_s) fclose(fp_s);
        }
    }
}