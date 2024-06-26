/*
 * PROJECT: Pairwise sequence alignments on GPU
 * FILE: psa_swgotoh_registers_32b_gpu
 * AUTHOR(S): Alejandro Chacon <alejandro.chacon@uab.es>
 * DESCRIPTION: Device functions for the SW-Gotoh GPU implementation:
 *				(A) Using video instructions to pack 4 SW in the same register
 *				(B) 2D tilling to reduce the number of accesses (reference / queries / intermediate column)
 */

extern "C" {
#include "../../../include/psa_pairwise_gpu.h"
}
#include <cuda_runtime.h>
#include <cuda.h>
#include "../../../includes/simd_functions.h"

#define V4_PACKET1(NUM_A,NUM_B,NUM_C,NUM_D)     ((NUM_A << 24) | (NUM_B << 16) | (NUM_C << 8) | NUM_D)
#define V4_PACKET4(NUM) 						((NUM   << 24) | (NUM   << 16) | (NUM   << 8) | NUM)

#ifndef QUERIES_SIZE
	#define QUERIES_SIZE 		100
#endif

#ifndef CANDIDATES_SIZE
	#define CANDIDATES_SIZE 	120
#endif

#define MAX3(a,b,c)				(MAX(MAX(a, b), c))
//#define SCORE(a,b)				((r_j.x == q_i.x) ? MATCH_SCORE : MISMATCH_SCORE)

#define WARP_SIZE				32
#define MAX_THREADS_PER_SM		128
#define CUDA_NUM_THREADS		128

#define BAND_LEN			 	4
#define VECTOR_ELEMENTS			4
#define MAX_QUERY_SIZE			QUERIES_SIZE

//typedef char4	score_type;
typedef union {
	char4 c4;
	uint32_t i;
}score_type;

typedef char4	score_type2;


inline __device__
int32_t max3(const int32_t op1, const int32_t op2, const int32_t op3)
{
    uint32_t r;
    asm( "  vmax.s32.s32.s32.max %0, %1, %2, %3;"               : "=r"(r)                              : "r"(op1), "r"(op2), "r"(op3) );
    return r;
}


inline __device__
void update_band(const uint32_t q_i, const uint32_t *ref_cache, uint32_t *H_band, uint32_t *F_band,
				uint32_t *H_temp, uint32_t *E_temp, uint32_t *H_maxScore,
				const uint32_t MATCH_SCORE, const uint32_t MISMATCH_SCORE,
				const uint32_t OPEN_INDEL_SCORE, const uint32_t EXTEND_INDEL_SCORE)
{

	const uint32_t   	ZERO		= 0;
	uint32_t			H_diag		= H_band[0];
						H_band[0]	= (* H_temp);
	uint32_t			E 	    	= (* E_temp);

    #pragma unroll
    for (uint32_t j = 1; j <= BAND_LEN; ++j)
    {
        // update F
        const uint32_t   ftop 	   = vaddss4(F_band[j], EXTEND_INDEL_SCORE);
        const uint32_t   htop 	   = vaddss4(H_band[j], OPEN_INDEL_SCORE);
        			     F_band[j]   = vmaxs4(ftop, htop);

        // update E
        const uint32_t   eleft = vaddss4(E, EXTEND_INDEL_SCORE);

        const uint32_t   hleft = vaddss4(H_band[j-1], OPEN_INDEL_SCORE);
					     E     = vmaxs4(eleft, hleft);

        // update H
        const uint32_t   r_j   = ref_cache[j-1];
        const uint32_t   Eq    = vcmpeq4(r_j, q_i);
        const uint32_t   W_ij	 = (~Eq & MISMATCH_SCORE) | (Eq & MATCH_SCORE);
        const uint32_t   diagonal = vaddss4(H_diag, W_ij);

        const uint32_t   top      = F_band[j];
        const uint32_t   left     = E;
        	  uint32_t   hi       = vmaxs4(vmaxs4(left, top), diagonal);
                         hi       = vmaxs4(hi, ZERO);

        H_diag                      = H_band[j];
        H_band[j]                   = hi;
        (* H_maxScore) = vmaxs4((* H_maxScore), hi);
    }

     (* H_temp) = H_band[BAND_LEN];
     (* E_temp) = E;
}

__global__
void localProcessSWTiling(ASCIIEntry_t *d_CandidatesASCII, uint32_t *d_CandidatesASCIIposition,
		   ASCIIEntry_t *d_QueriesASCII, uint32_t *d_QueriesASCIIposition,
		   alignmentInfo_t *d_AlignmentsInfo, alignmentEntry_t *d_AlignmentsResults,
		   uint32_t querySize, uint32_t candidateSize, uint32_t candidatesNum)
{
	const uint32_t idCandidate  = (blockIdx.x * MAX_THREADS_PER_SM + threadIdx.x) * VECTOR_ELEMENTS;

	//if (idCandidate < candidatesNum)
	if (idCandidate < (candidatesNum - 4))
	{
		const char* candidate0 	= d_CandidatesASCII + d_CandidatesASCIIposition[idCandidate];
		const char* candidate1 	= d_CandidatesASCII + d_CandidatesASCIIposition[idCandidate + 1];
		const char* candidate2 	= d_CandidatesASCII + d_CandidatesASCIIposition[idCandidate + 2];
		const char* candidate3 	= d_CandidatesASCII + d_CandidatesASCIIposition[idCandidate + 3];

		const char* query0 		= d_QueriesASCII + d_QueriesASCIIposition[d_AlignmentsInfo[idCandidate]];
		const char* query1 		= d_QueriesASCII + d_QueriesASCIIposition[d_AlignmentsInfo[idCandidate + 1]];
		const char* query2 		= d_QueriesASCII + d_QueriesASCIIposition[d_AlignmentsInfo[idCandidate + 2]];
		const char* query3 		= d_QueriesASCII + d_QueriesASCIIposition[d_AlignmentsInfo[idCandidate + 3]];

		const score_type   MATCH_SCORE			=	{ 2, 2, 2, 2};
		const score_type   MISMATCH_SCORE 		=	{-5,-5,-5,-5};
		const score_type   OPEN_INDEL_SCORE		=	{-2,-2,-2,-2};
		const score_type   EXTEND_INDEL_SCORE	=	{-1,-1,-1,-1};
		const score_type   ZERO					=	{ 0, 0, 0, 0};


		score_type		r_cache[BAND_LEN];

		score_type	 	H_temp [MAX_QUERY_SIZE];
		score_type 		E_temp [MAX_QUERY_SIZE];

		score_type 		H_band [BAND_LEN + 1];
		score_type 		F_band [BAND_LEN + 1];

		const int32_t numRows = querySize, numColumns = candidateSize;
		int32_t idColumn, idRow, idBand;
		score_type H_maxScore = ZERO;

		for(idBand = 0; idBand < MAX_QUERY_SIZE; ++idBand){
			H_temp[idBand] = ZERO;
			E_temp[idBand] = ZERO;
		}

		// Compute Score SW-GOTOH
		for(idColumn = 0; idColumn < numColumns; idColumn += BAND_LEN){

	        // load a block of entries from the reference
	        #pragma unroll
	        for (uint32_t idBand = 0; idBand < BAND_LEN; ++idBand){
	            r_cache[idBand].c4.x = candidate0[idColumn + idBand];
	            r_cache[idBand].c4.y = candidate1[idColumn + idBand];
	            r_cache[idBand].c4.z = candidate2[idColumn + idBand];
	            r_cache[idBand].c4.w = candidate3[idColumn + idBand];
	        }

	        // initialize the first band
	        #pragma unroll
	        for (uint32_t idBand = 0; idBand <= BAND_LEN; ++idBand){
	        	H_band[idBand] = ZERO;
	        	F_band[idBand] = ZERO;
	        }

			#pragma unroll 1
	        for(idRow = 0; idRow < numRows; idRow += 4){
	        	const uint idTile = idRow / 4;
	        	uint4 H_temp_v4 = ((uint4 *)H_temp)[idTile];
	        	uint4 E_temp_v4 = ((uint4 *)E_temp)[idTile];

	        	const score_type query0_v4 = ((score_type *)query0)[idTile];
	        	const score_type query1_v4 = ((score_type *)query1)[idTile];
	        	const score_type query2_v4 = ((score_type *)query2)[idTile];
	        	const score_type query3_v4 = ((score_type *)query3)[idTile];

	        	const score_type q_i0 = {query0_v4.c4.x, query1_v4.c4.x, query2_v4.c4.x, query3_v4.c4.x};
	        	const score_type q_i1 = {query0_v4.c4.y, query1_v4.c4.y, query2_v4.c4.y, query3_v4.c4.y};
	        	const score_type q_i2 = {query0_v4.c4.z, query1_v4.c4.z, query2_v4.c4.z, query3_v4.c4.z};
	        	const score_type q_i3 = {query0_v4.c4.w, query1_v4.c4.w, query2_v4.c4.w, query3_v4.c4.w};

	        	{
	        		update_band(q_i0.i, (uint32_t *) r_cache, (uint32_t *) H_band, (uint32_t *) F_band, &H_temp_v4.x, &E_temp_v4.x, &H_maxScore.i,
	        					MATCH_SCORE.i, MISMATCH_SCORE.i, OPEN_INDEL_SCORE.i, EXTEND_INDEL_SCORE.i);
	        	}
				{
					update_band(q_i1.i, (uint32_t *) r_cache, (uint32_t *) H_band, (uint32_t *) F_band, &H_temp_v4.y, &E_temp_v4.y, &H_maxScore.i,
								MATCH_SCORE.i, MISMATCH_SCORE.i, OPEN_INDEL_SCORE.i, EXTEND_INDEL_SCORE.i);
				}
				{
					update_band(q_i2.i, (uint32_t *) r_cache, (uint32_t *) H_band, (uint32_t *) F_band, &H_temp_v4.z, &E_temp_v4.z, &H_maxScore.i,
								MATCH_SCORE.i, MISMATCH_SCORE.i, OPEN_INDEL_SCORE.i, EXTEND_INDEL_SCORE.i);
	        	}
				{
					update_band(q_i3.i, (uint32_t *) r_cache, (uint32_t *) H_band, (uint32_t *) F_band, &H_temp_v4.w, &E_temp_v4.w, &H_maxScore.i,
								MATCH_SCORE.i, MISMATCH_SCORE.i, OPEN_INDEL_SCORE.i, EXTEND_INDEL_SCORE.i);
				}

				((uint4 *)H_temp)[idTile] = H_temp_v4;
				((uint4 *)E_temp)[idTile] = E_temp_v4;
	        }
		}

		d_AlignmentsResults[idCandidate].score  	= H_maxScore.c4.x;
		d_AlignmentsResults[idCandidate + 1].score  = H_maxScore.c4.y;
		d_AlignmentsResults[idCandidate + 2].score  = H_maxScore.c4.z;
		d_AlignmentsResults[idCandidate + 3].score  = H_maxScore.c4.w;

		d_AlignmentsResults[idCandidate].column     = 0;
		d_AlignmentsResults[idCandidate + 1].column = 0;
		d_AlignmentsResults[idCandidate + 2].column = 0;
		d_AlignmentsResults[idCandidate + 3].column = 0;
	}
}


extern "C"
psaError_t localProcessPairwise(sequences_t *candidates, sequences_t *queries, alignments_t *alignments)
{
	uint32_t blocks = DIV_CEIL(DIV_CEIL(candidates->num, VECTOR_ELEMENTS), CUDA_NUM_THREADS);
	uint32_t threads = CUDA_NUM_THREADS;
	uint32_t querySize = queries->h_size[0];
	uint32_t candidateSize = candidates->h_size[0];

	cudaThreadSetCacheConfig(cudaFuncCachePreferL1);

	printf("Grid Size: %d, Block Size: %d, Total alignments: %d, BAND_LEN: %d \n", blocks, threads, candidates->num, BAND_LEN);
	localProcessSWTiling<<<blocks, threads>>>(candidates->d_ASCII, candidates->d_ASCIIposition,
								 			queries->d_ASCII, queries->d_ASCIIposition, 
											alignments->d_info, alignments->d_results,
								 			querySize, candidateSize, candidates->num);

	cudaThreadSynchronize();

	return (SUCCESS);
}
