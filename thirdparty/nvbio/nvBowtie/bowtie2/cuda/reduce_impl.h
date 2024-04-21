/*
 * nvbio
 * Copyright (c) 2011-2014, NVIDIA CORPORATION. All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *    * Redistributions of source code must retain the above copyright
 *      notice, this list of conditions and the following disclaimer.
 *    * Redistributions in binary form must reproduce the above copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *    * Neither the name of the NVIDIA CORPORATION nor the
 *      names of its contributors may be used to endorse or promote products
 *      derived from this software without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL NVIDIA CORPORATION BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

///
///\file reduce.h
///

#pragma once

#include <nvBowtie/bowtie2/cuda/defs.h>
#include <nvbio/io/alignments.h>
#include <nvBowtie/bowtie2/cuda/seed_hit.h>
#include <nvBowtie/bowtie2/cuda/params.h>
#include <nvbio/io/utils.h>
#include <nvbio/basic/exceptions.h>

namespace nvbio {
namespace bowtie2 {
namespace cuda {

template <typename ScoringScheme> struct BaseScoringPipelineState;
template <typename ScoringScheme> struct BestApproxScoringPipelineState;

///@addtogroup nvBowtie
///@{

///@addtogroup Reduce
///@{

///
/// Reduce the scores associated to each read in the scoring queue to find the best 2 alignments.
///
template <typename ScoringScheme, typename ReduceContext>
void score_reduce_t(
    const ReduceContext                                     context,
    const BestApproxScoringPipelineState<ScoringScheme>&    pipeline,
    const ParamsPOD                                         params);

///
/// Reduce the scores associated to each paired-end read in the scoring queue to find the best 2 alignments.
///
template <typename ScoringScheme, typename ReduceContext>
void score_reduce_paired_t(
    const ReduceContext                                     context,
    const BestApproxScoringPipelineState<ScoringScheme>&    pipeline,
    const ParamsPOD                                         params);

///@}  // group Reduce
///@}  // group nvBowtie

} // namespace cuda
} // namespace bowtie2
} // namespace nvbio

#include <nvBowtie/bowtie2/cuda/reduce_inl.h>
