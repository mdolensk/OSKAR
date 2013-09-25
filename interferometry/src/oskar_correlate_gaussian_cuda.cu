/*
 * Copyright (c) 2012-2013, The University of Oxford
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 3. Neither the name of the University of Oxford nor the names of its
 *    contributors may be used to endorse or promote products derived from this
 *    software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#include <oskar_accumulate_baseline_visibility_for_source.h>
#include <oskar_correlate_gaussian_cuda.h>
#include <oskar_sinc.h>

#include <math.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Kernel wrappers. ======================================================== */

/* Single precision. */
void oskar_correlate_gaussian_cuda_f(int num_sources,
        int num_stations, const float4c* d_jones,
        const float* d_source_I, const float* d_source_Q,
        const float* d_source_U, const float* d_source_V,
        const float* d_source_l, const float* d_source_m,
        const float* d_source_a, const float* d_source_b,
        const float* d_source_c, const float* d_station_u,
        const float* d_station_v, float inv_wavelength,
        float frac_bandwidth, float4c* d_vis)
{
    dim3 num_threads(128, 1);
    dim3 num_blocks(num_stations, num_stations);
    size_t shared_mem = num_threads.x * sizeof(float4c);
    oskar_correlate_gaussian_cudak_f
    OSKAR_CUDAK_CONF(num_blocks, num_threads, shared_mem)
    (num_sources, num_stations, d_jones, d_source_I, d_source_Q, d_source_U,
            d_source_V, d_source_l, d_source_m, d_source_a, d_source_b,
            d_source_c, d_station_u, d_station_v, inv_wavelength,
            frac_bandwidth, d_vis);
}

/* Double precision. */
void oskar_correlate_gaussian_cuda_d(int num_sources,
        int num_stations, const double4c* d_jones,
        const double* d_source_I, const double* d_source_Q,
        const double* d_source_U, const double* d_source_V,
        const double* d_source_l, const double* d_source_m,
        const double* d_source_a, const double* d_source_b,
        const double* d_source_c, const double* d_station_u,
        const double* d_station_v, double inv_wavelength,
        double frac_bandwidth, double4c* d_vis)
{
    dim3 num_threads(128, 1);
    dim3 num_blocks(num_stations, num_stations);
    size_t shared_mem = num_threads.x * sizeof(double4c);
    oskar_correlate_gaussian_cudak_d
    OSKAR_CUDAK_CONF(num_blocks, num_threads, shared_mem)
    (num_sources, num_stations, d_jones, d_source_I, d_source_Q, d_source_U,
            d_source_V, d_source_l, d_source_m, d_source_a, d_source_b,
            d_source_c, d_station_u, d_station_v, inv_wavelength,
            frac_bandwidth, d_vis);
}

#ifdef __cplusplus
}
#endif


/* Kernels. ================================================================ */

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#ifndef M_PIf
#define M_PIf 3.14159265358979323846f
#endif

/* Indices into the visibility/baseline matrix. */
#define AI blockIdx.x /* Column index. */
#define AJ blockIdx.y /* Row index. */

extern __shared__ float4c  smem_f[];
extern __shared__ double4c smem_d[];


/* Single precision. */
__global__
void oskar_correlate_gaussian_cudak_f(const int num_sources,
        const int num_stations, const float4c* __restrict__ jones,
        const float* __restrict__ source_I,
        const float* __restrict__ source_Q,
        const float* __restrict__ source_U,
        const float* __restrict__ source_V,
        const float* __restrict__ source_l,
        const float* __restrict__ source_m,
        const float* __restrict__ source_a,
        const float* __restrict__ source_b,
        const float* __restrict__ source_c,
        const float* __restrict__ station_u,
        const float* __restrict__ station_v, const float inv_wavelength,
        const float frac_bandwidth, float4c* __restrict__ vis)
{
    /* Return immediately if in the wrong half of the visibility matrix. */
    if (AJ >= AI) return;

    /* Common values per thread block. */
    __shared__ float uu, vv, uu2, vv2, uuvv;
    if (threadIdx.x == 0)
    {
        /* Baseline UV-distance, in wavelengths. */
        uu   = (station_u[AI] - station_u[AJ]) * inv_wavelength;
        vv   = (station_v[AI] - station_v[AJ]) * inv_wavelength;

        /* Quantities needed for evaluating source with gaussian term. */
        uu2  = uu * uu;
        vv2  = vv * vv;
        uuvv = 2.0f * uu * vv;

        /* Modify the baseline UV-distance to include the common components
         * of the bandwidth smearing term. */
        uu *= M_PIf * frac_bandwidth;
        vv *= M_PIf * frac_bandwidth;
    }
    __syncthreads();

    /* Get pointers to both source vectors for station i and j. */
    const float4c* __restrict__ station_i = &jones[num_sources * AI];
    const float4c* __restrict__ station_j = &jones[num_sources * AJ];

    /* Each thread loops over a subset of the sources. */
    {
        float4c sum; /* Partial sum per thread. */
        sum.a = make_float2(0.0f, 0.0f);
        sum.b = make_float2(0.0f, 0.0f);
        sum.c = make_float2(0.0f, 0.0f);
        sum.d = make_float2(0.0f, 0.0f);
        for (int t = threadIdx.x; t < num_sources; t += blockDim.x)
        {
            /* Compute bandwidth-smearing term. */
            float rb = oskar_sinc_f(uu * source_l[t] + vv * source_m[t]);

            /* Evaluate gaussian source width term. */
            float f = expf(-(source_a[t] * uu2 +
                    source_b[t] * uuvv + source_c[t] * vv2));

            rb *= f;

            /* Accumulate baseline visibility response for source. */
            oskar_accumulate_baseline_visibility_for_source_f(&sum, t,
                    source_I, source_Q, source_U, source_V,
                    station_i, station_j, rb);
        }
        smem_f[threadIdx.x] = sum;
    }
    __syncthreads();

    /* Accumulate contents of shared memory. */
    if (threadIdx.x == 0)
    {
        /* Sum over all sources for this baseline. */
        float4c sum;
        sum.a = make_float2(0.0f, 0.0f);
        sum.b = make_float2(0.0f, 0.0f);
        sum.c = make_float2(0.0f, 0.0f);
        sum.d = make_float2(0.0f, 0.0f);
        for (int i = 0; i < blockDim.x; ++i)
        {
            sum.a.x += smem_f[i].a.x;
            sum.a.y += smem_f[i].a.y;
            sum.b.x += smem_f[i].b.x;
            sum.b.y += smem_f[i].b.y;
            sum.c.x += smem_f[i].c.x;
            sum.c.y += smem_f[i].c.y;
            sum.d.x += smem_f[i].d.x;
            sum.d.y += smem_f[i].d.y;
        }

        /* Determine 1D index. */
        int idx = AJ*(num_stations-1) - (AJ-1)*AJ/2 + AI - AJ - 1;

        /* Modify existing visibility. */
        vis[idx].a.x += sum.a.x;
        vis[idx].a.y += sum.a.y;
        vis[idx].b.x += sum.b.x;
        vis[idx].b.y += sum.b.y;
        vis[idx].c.x += sum.c.x;
        vis[idx].c.y += sum.c.y;
        vis[idx].d.x += sum.d.x;
        vis[idx].d.y += sum.d.y;
    }
}

/* Double precision. */
__global__
void oskar_correlate_gaussian_cudak_d(const int num_sources,
        const int num_stations, const double4c* __restrict__ jones,
        const double* __restrict__ source_I,
        const double* __restrict__ source_Q,
        const double* __restrict__ source_U,
        const double* __restrict__ source_V,
        const double* __restrict__ source_l,
        const double* __restrict__ source_m,
        const double* __restrict__ source_a,
        const double* __restrict__ source_b,
        const double* __restrict__ source_c,
        const double* __restrict__ station_u,
        const double* __restrict__ station_v, const double inv_wavelength,
        const double frac_bandwidth, double4c* __restrict__ vis)
{
    /* Return immediately if in the wrong half of the visibility matrix. */
    if (AJ >= AI) return;

    /* Common values per thread block. */
    __shared__ double uu, vv, uu2, vv2, uuvv;
    if (threadIdx.x == 0)
    {
        /* Baseline UV-distance, in wavelengths. */
        uu   = (station_u[AI] - station_u[AJ]) * inv_wavelength;
        vv   = (station_v[AI] - station_v[AJ]) * inv_wavelength;

        /* Quantities needed for evaluating source with gaussian term. */
        uu2  = uu * uu;
        vv2  = vv * vv;
        uuvv = 2.0 * uu * vv;

        /* Modify the baseline UV-distance to include the common components
         * of the bandwidth smearing term. */
        uu *= M_PI * frac_bandwidth;
        vv *= M_PI * frac_bandwidth;
    }
    __syncthreads();

    /* Get pointers to both source vectors for station i and j. */
    const double4c* __restrict__ station_i = &jones[num_sources * AI];
    const double4c* __restrict__ station_j = &jones[num_sources * AJ];

    /* Each thread loops over a subset of the sources. */
    {
        double4c sum; /* Partial sum per thread. */
        sum.a = make_double2(0.0, 0.0);
        sum.b = make_double2(0.0, 0.0);
        sum.c = make_double2(0.0, 0.0);
        sum.d = make_double2(0.0, 0.0);
        for (int t = threadIdx.x; t < num_sources; t += blockDim.x)
        {
            /* Compute bandwidth-smearing term. */
            double rb = oskar_sinc_d(uu * source_l[t] + vv * source_m[t]);

            /* Evaluate gaussian source width term. */
            double f = exp(-(source_a[t] * uu2 +
                    source_b[t] * uuvv + source_c[t] * vv2));

            rb *= f;

            /* Accumulate baseline visibility response for source. */
            oskar_accumulate_baseline_visibility_for_source_d(&sum, t,
                    source_I, source_Q, source_U, source_V,
                    station_i, station_j, rb);
        }
        smem_d[threadIdx.x] = sum;
    }
    __syncthreads();

    /* Accumulate contents of shared memory. */
    if (threadIdx.x == 0)
    {
        /* Sum over all sources for this baseline. */
        double4c sum;
        sum.a = make_double2(0.0, 0.0);
        sum.b = make_double2(0.0, 0.0);
        sum.c = make_double2(0.0, 0.0);
        sum.d = make_double2(0.0, 0.0);
        for (int i = 0; i < blockDim.x; ++i)
        {
            sum.a.x += smem_d[i].a.x;
            sum.a.y += smem_d[i].a.y;
            sum.b.x += smem_d[i].b.x;
            sum.b.y += smem_d[i].b.y;
            sum.c.x += smem_d[i].c.x;
            sum.c.y += smem_d[i].c.y;
            sum.d.x += smem_d[i].d.x;
            sum.d.y += smem_d[i].d.y;
        }

        /* Determine 1D index. */
        int idx = AJ*(num_stations-1) - (AJ-1)*AJ/2 + AI - AJ - 1;

        /* Modify existing visibility. */
        vis[idx].a.x += sum.a.x;
        vis[idx].a.y += sum.a.y;
        vis[idx].b.x += sum.b.x;
        vis[idx].b.y += sum.b.y;
        vis[idx].c.x += sum.c.x;
        vis[idx].c.y += sum.c.y;
        vis[idx].d.x += sum.d.x;
        vis[idx].d.y += sum.d.y;
    }
}
