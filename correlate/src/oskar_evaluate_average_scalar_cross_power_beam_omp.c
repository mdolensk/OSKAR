/*
 * Copyright (c) 2014-2015, The University of Oxford
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

#include <oskar_evaluate_average_scalar_cross_power_beam_omp.h>
#include <oskar_correlate_functions_inline.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Single precision. */
void oskar_evaluate_average_scalar_cross_power_beam_omp_f(
        const int num_sources, const int num_stations,
        const float2* restrict jones, float2* restrict beam)
{
    int i = 0;
    float norm;
    norm = 2.0f / (num_stations * (num_stations - 1));

#pragma omp parallel for private(i)
    for (i = 0; i < num_sources; ++i)
    {
        int SP, SQ;
        float2 val1, val2, p, q;

        /* Calculate cross-power beam at the source. */
        val1.x = 0.0f;
        val1.y = 0.0f;
        for (SP = 0; SP < num_stations; ++SP)
        {
            /* Load data for first station into shared memory. */
            p = jones[SP * num_sources + i];
            val2.x = 0.0f;
            val2.y = 0.0f;

            /* Cross-correlate. */
            for (SQ = SP + 1; SQ < num_stations; ++SQ)
            {
                /* Load data for second station into registers. */
                q = jones[SQ * num_sources + i];

                /* Multiply-add: val += p * conj(q). */
                OSKAR_MULTIPLY_ADD_COMPLEX_CONJUGATE(val2, p, q);
            }

            /* Accumulate partial sum (try to preserve numerical precision). */
            val1.x += val2.x;
            val1.y += val2.y;
        }

        /* Calculate average by dividing by number of baselines. */
        val1.x *= norm;
        val1.y *= norm;

        /* Store result. */
        beam[i] = val1;
    }
}

/* Double precision. */
void oskar_evaluate_average_scalar_cross_power_beam_omp_d(
        const int num_sources, const int num_stations,
        const double2* restrict jones, double2* restrict beam)
{
    int i = 0;
    double norm;
    norm = 2.0 / (num_stations * (num_stations - 1));

#pragma omp parallel for private(i)
    for (i = 0; i < num_sources; ++i)
    {
        int SP, SQ;
        double2 val1, val2, p, q;

        /* Calculate cross-power beam at the source. */
        val1.x = 0.0;
        val1.y = 0.0;
        for (SP = 0; SP < num_stations; ++SP)
        {
            /* Load data for first station into shared memory. */
            p = jones[SP * num_sources + i];
            val2.x = 0.0;
            val2.y = 0.0;

            /* Cross-correlate. */
            for (SQ = SP + 1; SQ < num_stations; ++SQ)
            {
                /* Load data for second station into registers. */
                q = jones[SQ * num_sources + i];

                /* Multiply-add: val += p * conj(q). */
                OSKAR_MULTIPLY_ADD_COMPLEX_CONJUGATE(val2, p, q);
            }

            /* Accumulate partial sum (try to preserve numerical precision). */
            val1.x += val2.x;
            val1.y += val2.y;
        }

        /* Calculate average by dividing by number of baselines. */
        val1.x *= norm;
        val1.y *= norm;

        /* Store result. */
        beam[i] = val1;
    }
}

#ifdef __cplusplus
}
#endif
