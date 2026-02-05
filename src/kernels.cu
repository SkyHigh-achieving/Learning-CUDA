#include <iostream>
#include <vector>
#include <cmath>
#include <cuda_fp16.h>
#include <cuda_runtime.h>

#include "../tester/utils.h"

// =====================================================================
// Trace Kernel Implementation
// =====================================================================

/**
 * @brief CUDA Kernel for computing the trace.
 * 使用 Grid-Stride Loop 模式确保可以处理任意长度的对角线，
 * 并在每个线程内部先进行局部累加，最后通过 atomicAdd 汇总，
 * 减少对全局内存原子操作的竞争。
 */
template <typename T>
__global__ void traceKernel(const T* input, T* result, size_t cols, size_t n) {
    size_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    T local_sum = 0;

    // Grid-stride loop: 每个线程处理多个对角线元素（如果 n 很大）
    for (size_t i = idx; i < n; i += gridDim.x * blockDim.x) {
        // 对角线元素的索引规律：row == col => index = i * cols + i
        local_sum += input[i * cols + i];
    }

    // 原子加法汇总到结果
    // 注意：atomicAdd 在 float 和 int 上均有原生支持
    if (local_sum != 0) {
        atomicAdd(result, local_sum);
    }
}

/**
 * @brief Computes the trace of a matrix.
 * Host 侧封装函数：负责显存管理、数据拷贝与 Kernel 启动。
 */
template <typename T>
T trace(const std::vector<T>& h_input, size_t rows, size_t cols) {
    size_t n = (rows < cols) ? rows : cols;
    if (n == 0) return T(0);

    T *d_input, *d_result;
    T h_result = 0;

    // 1. 分配显存
    cudaMalloc(&d_input, rows * cols * sizeof(T));
    cudaMalloc(&d_result, sizeof(T));

    // 2. 拷贝数据并初始化结果
    cudaMemcpy(d_input, h_input.data(), rows * cols * sizeof(T), cudaMemcpyHostToDevice);
    cudaMemset(d_result, 0, sizeof(T));

    // 3. 配置并行参数
    // 选择 256 为线程块大小是经验值，通常能获得较好的硬件利用率
    int blockSize = 256;
    int gridSize = (n + blockSize - 1) / blockSize;
    
    // 限制 gridSize 避免在超大 N 时启动过多无意义的 block
    if (gridSize > 1024) gridSize = 1024;

    // 4. 启动 Kernel
    traceKernel<T><<<gridSize, blockSize>>>(d_input, d_result, cols, n);

    // 5. 拷贝结果回 Host
    cudaMemcpy(&h_result, d_result, sizeof(T), cudaMemcpyDeviceToHost);

    // 6. 释放显存
    cudaFree(d_input);
    cudaFree(d_result);

    return h_result;
}

/**
 * @brief Computes flash attention for given query, key, and value tensors.
 * 
 * 算法原理：FlashAttention-V2 简化版。
 * 1. 使用 Tiling 减少对 HBM 的访问。
 * 2. 在线 Softmax：维护每个 Row 的 max (m) 和 sum (l)。
 * 3. GQA 支持：多个 Q head 共享一个 KV head。
 * 4. Causal Masking：在计算 S = QK^T 时，若 is_causal 为真且 target_idx < source_idx，则设为 -inf。
 */
template <typename T>
__global__ void flashAttentionKernel(
    const T* q, const T* k, const T* v, T* o,
    int batch_size, int target_seq_len, int src_seq_len,
    int query_heads, int kv_heads, int head_dim, bool is_causal, double scale) {
    
    int b = blockIdx.x;
    int h = blockIdx.y;
    int i = blockIdx.z; 
    int tid = threadIdx.x;

    if (b >= batch_size || h >= query_heads || i >= target_seq_len) return;

    int gqa_ratio = query_heads / kv_heads;
    int kv_h = h / gqa_ratio;

    const T* q_curr = q + (b * target_seq_len * query_heads + i * query_heads + h) * head_dim;
    const T* k_base = k + (b * src_seq_len * kv_heads + kv_h) * head_dim;
    const T* v_base = v + (b * src_seq_len * kv_heads + kv_h) * head_dim;
    T* o_curr = o + (b * target_seq_len * query_heads + i * query_heads + h) * head_dim;

    extern __shared__ double s_data[];
    double* s_acc = s_data;           
    __shared__ double s_m;            
    __shared__ double s_l;           
    __shared__ double s_c;           

    if (tid == 0) {
        s_m = -1e30;
    }
    __syncthreads();

    // Pass 1: compute max
    for (int j = 0; j < src_seq_len; ++j) {
        if (is_causal && i < j) break;

        double partial_score = 0.0;
        const T* k_curr = k_base + (j * kv_heads) * head_dim;
        for (int d = tid; d < head_dim; d += blockDim.x) {
            partial_score = fma((double)q_curr[d], (double)k_curr[d], partial_score);
        }

        for (int offset = 16; offset > 0; offset /= 2)
            partial_score += __shfl_down_sync(0xFFFFFFFF, partial_score, offset);

        if (tid % 32 == 0) s_acc[tid / 32] = partial_score;
        __syncthreads();

        if (tid < 32) {
            double val = (tid < (blockDim.x / 32)) ? s_acc[tid] : 0.0;
            for (int offset = 16; offset > 0; offset /= 2)
                val += __shfl_down_sync(0xFFFFFFFF, val, offset);
            if (tid == 0) {
                val *= scale;
                if (val > s_m) s_m = val;
            }
        }
        __syncthreads();
    }

    if (tid == 0) {
        s_l = 0.0;
        s_c = 0.0;
    }
    __syncthreads();

    double local_o[8];
    double local_c[8];
    for (int d = 0; d < 8; ++d) { local_o[d] = 0.0; local_c[d] = 0.0; }

    // Pass 2: compute sum and output
    for (int j = 0; j < src_seq_len; ++j) {
        if (is_causal && i < j) break;

        double partial_score = 0.0;
        const T* k_curr = k_base + (j * kv_heads) * head_dim;
        for (int d = tid; d < head_dim; d += blockDim.x) {
            partial_score = fma((double)q_curr[d], (double)k_curr[d], partial_score);
        }

        for (int offset = 16; offset > 0; offset /= 2)
            partial_score += __shfl_down_sync(0xFFFFFFFF, partial_score, offset);

        if (tid % 32 == 0) s_acc[tid / 32] = partial_score;
        __syncthreads();

        if (tid < 32) {
            double val = (tid < (blockDim.x / 32)) ? s_acc[tid] : 0.0;
            for (int offset = 16; offset > 0; offset /= 2)
                val += __shfl_down_sync(0xFFFFFFFF, val, offset);
            if (tid == 0) {
                val *= scale;
                double exp_score = exp(val - s_m);
                s_acc[0] = exp_score;
                double y = exp_score - s_c;
                double t = s_l + y;
                s_c = (t - s_l) - y;
                s_l = t;
            }
        }
        __syncthreads();

        double exp_score = s_acc[0];
        const T* v_curr = v_base + (j * kv_heads) * head_dim;
        int reg_idx = 0;
        for (int d = tid; d < head_dim; d += blockDim.x) {
            double add = (double)v_curr[d] * exp_score;
            double y = add - local_c[reg_idx];
            double t = local_o[reg_idx] + y;
            local_c[reg_idx] = (t - local_o[reg_idx]) - y;
            local_o[reg_idx] = t;
            reg_idx++;
        }
        __syncthreads();
    }

    double final_l = s_l;
    int reg_idx = 0;
    for (int d = tid; d < head_dim; d += blockDim.x) {
        o_curr[d] = (T)(local_o[reg_idx] / final_l);
        reg_idx++;
    }
}

template <typename T>
void flashAttention(const std::vector<T>& h_q, const std::vector<T>& h_k,
                    const std::vector<T>& h_v, std::vector<T>& h_o,
                    int batch_size, int target_seq_len, int src_seq_len, 
                    int query_heads, int kv_heads, int head_dim, bool is_causal) {       
    T *d_q, *d_k, *d_v, *d_o;
    size_t q_size = batch_size * target_seq_len * query_heads * head_dim * sizeof(T);
    size_t kv_size = batch_size * src_seq_len * kv_heads * head_dim * sizeof(T);
    size_t o_size = q_size;

    cudaMalloc(&d_q, q_size);
    cudaMalloc(&d_k, kv_size);
    cudaMalloc(&d_v, kv_size);
    cudaMalloc(&d_o, o_size);

    cudaMemcpy(d_q, h_q.data(), q_size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_k, h_k.data(), kv_size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_v, h_v.data(), kv_size, cudaMemcpyHostToDevice);

    double scale = 1.0 / sqrt((double)head_dim);
    dim3 grid(batch_size, query_heads, target_seq_len);
    int threads = 256; 
    size_t shared_mem = 2 * threads * sizeof(double); 

    flashAttentionKernel<T><<<grid, threads, shared_mem>>>(
        d_q, d_k, d_v, d_o,
        batch_size, target_seq_len, src_seq_len,
        query_heads, kv_heads, head_dim, is_causal, scale
    );

    cudaMemcpy(h_o.data(), d_o, o_size, cudaMemcpyDeviceToHost);

    cudaFree(d_q); cudaFree(d_k); cudaFree(d_v); cudaFree(d_o);
}

// *********************************************************************
// Explicit Template Instantiations (REQUIRED FOR LINKING WITH TESTER.O)
// DO NOT MODIFY THIS SECTION
// *********************************************************************
template int trace<int>(const std::vector<int>&, size_t, size_t);
template float trace<float>(const std::vector<float>&, size_t, size_t);
template void flashAttention<float>(const std::vector<float>&, const std::vector<float>&,
  const std::vector<float>&, std::vector<float>&,
  int, int, int, int, int, int, bool);
template void flashAttention<half>(const std::vector<half>&, const std::vector<half>&,
  const std::vector<half>&, std::vector<half>&,
  int, int, int, int, int, int, bool);
