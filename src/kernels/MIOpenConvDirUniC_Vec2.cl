/*******************************************************************************
 *
 * MIT License
 *
 * Copyright (c) 2017 Advanced Micro Devices, Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 *******************************************************************************/

#define PPCAT_NX(A, B) A##B
#define PPCAT(A, B) PPCAT_NX(A, B)
#define TWO 2
#define FOUR 4
#define EIGHT 8

#if MIOPEN_USE_FP16 == 1
#pragma OPENCL EXTENSION cl_khr_fp16 : enable
#define _FLOAT half
#ifndef HALF_MAX
#define MAX_VAL 65504 /* max value */
#else
#define MAX_VAL HALF_MAX
#endif
#endif
#if MIOPEN_USE_FP32 == 1
#define _FLOAT float
#ifndef FLT_MAX
#define MAX_VAL 3.402823466e+38F /* max value */
#else
#define MAX_VAL FLT_MAX
#endif
#endif

#define _FLOAT2 PPCAT(_FLOAT, TWO)
#define _FLOAT4 PPCAT(_FLOAT, FOUR)
#define _FLOAT8 PPCAT(_FLOAT, EIGHT)

#define UNUSED __attribute__((__unused__))
#define INLINE __attribute__((always_inline))
//#define IDIV(A,B) (iDiv(A, B))
//#define IMOD(A,B,C) (iMod(A, B, C))
#define IDIV(A, B) ((uint)((float)A * (1.0f / (float)B) + 0.00001f))
#define IMOD(A, B, C) (A - mul24(B, (uint)C))

#define MLO_FILTER_SZ (MLO_FILTER_SIZE1 * MLO_FILTER_SIZE0)

#define MLO_GRP_SZ0 (MLO_GRP_TILE0 * MLO_GRP_TILE1)
#define MLO_GRP_SZ1 1
#define MLO_GRP_SZ2 1
#define MLO_GRP_SZ (MLO_GRP_SZ0 * MLO_GRP_SZ1 * MLO_GRP_SZ2)
#define MLO_N_PROC_WAVES ((MLO_GRP_SZ + MLO_N_READ_PROCS - 1) / MLO_N_READ_PROCS)
#define MLO_OUT_TILE_SZ (MLO_OUT_PIX_TILE1 * MLO_OUT_PIX_TILE0)
#define MLO_ALU_TILE_SZ (MLO_ALU_VTILE1 * MLO_ALU_VTILE0)

#if MLO_IN_TILE0 < MLO_OUT_WIDTH || MLO_IN_TILE1 < MLO_OUT_HEIGHT
#define MLO_LARGE_MAP 1
#else
#define MLO_LARGE_MAP 0
#endif

#if(MLO_IN_WIDTH == MLO_OUT_WIDTH &&                                \
    (MLO_IN_WIDTH / MLO_IN_TILE0) * MLO_IN_TILE0 == MLO_IN_WIDTH && \
    MLO_IN_HEIGHT == MLO_OUT_HEIGHT &&                              \
    (MLO_IN_HEIGHT / MLO_IN_TILE1) * MLO_IN_TILE1 == MLO_IN_HEIGHT)
#define MLO_OUT_ALIGNED 1
#else
#define MLO_OUT_ALIGNED 0
#endif

#define MLO_ALUTILES_STACK_SZ (MLO_N_ALUTILES_PERSTACK * MLO_ALU_TILE_SZ)
#define MLO_N_IN_TILES_TOTAL (MLO_N_IN_TILES_PERSTACK * MLO_N_STACKS)

#define MLO_N_OUT_TILE_BLOCKS0 ((MLO_OUT_WIDTH + MLO_IN_TILE0 - 1) / MLO_IN_TILE0)
#define MLO_N_OUT_TILE_BLOCKS1 ((MLO_OUT_HEIGHT + MLO_IN_TILE1 - 1) / MLO_IN_TILE1)
#define MLO_N_IN_PACKS (MLO_N_INPUTS / MLO_N_IN_TILES_PERSTACK)

#define MLO_N_IN_READ (MLO_N_IN_PACKS * MLO_N_IN_TILES_PERSTACK)
#if MLO_N_IN_READ == MLO_N_INPUTS
#define MLO_INPUTS_ALIGNED 1
#else
#define MLO_INPUTS_ALIGNED 0
#endif

#define MLO_N_OUT_PACKS (MLO_N_OUTPUTS / MLO_N_OUT_TILES_PERSTACK)
#if MLO_N_OUT_PACKS * MLO_N_OUT_TILES_PERSTACK == MLO_N_OUTPUTS && \
    MLO_N_OUT_TILES_PERSTACK != MLO_N_OUTPUTS
#define MLO_OUTPUTS_ALIGNED 1
#else
#define MLO_OUTPUTS_ALIGNED 0
#endif

#define MLO_N_BATCH_PACKS (MLO_BATCH_SZ / MLO_N_STACKS)
#if MLO_N_BATCH_PACKS * MLO_N_STACKS == MLO_BATCH_SZ && MLO_N_STACKS != MLO_BATCH_SZ
#define MLO_BATCH_ALIGNED 1
#else
#define MLO_BATCH_ALIGNED 0
#endif

#define MLO_IN_LCL_WIDTH               \
    (MLO_IN_TILE0 + MLO_FILTER_SIZE0 - \
     1) // here we use kernel size. it's important when padding == 0
#define MLO_IN_LCL_HEIGHT (MLO_IN_TILE1 + MLO_FILTER_SIZE1 - 1)
#define MLO_IN_LCL_TILE_SZ (MLO_IN_LCL_WIDTH * MLO_IN_LCL_HEIGHT)
#define MLO_IN_LCL_PERSTACK_SZ (MLO_IN_LCL_TILE_SZ * MLO_N_IN_TILES_PERSTACK)
#define MLO_IN_LCL_SZ (MLO_IN_LCL_PERSTACK_SZ * MLO_N_STACKS)

#define MLO_WEIGHTS_SZ (MLO_N_OUT_TILES_PERSTACK * MLO_N_IN_TILES_PERSTACK * MLO_FILTER_SZ)

#define MLO_PVT_ACCUM_DATA_SZ (MLO_N_OUT_TILES * MLO_OUT_TILE_SZ)
#define MLO_PVT_IN_WIDTH (MLO_FILTER_SIZE0 + MLO_OUT_PIX_TILE0 - 1)
#define MLO_PVT_IN_HEIGHT (MLO_OUT_PIX_TILE1)

#define MLO_LCL_WEIGHTS 1

#if defined(__AMDGCN__)
extern uint __llvm_amdgcn_readfirstlane(uint) __asm("llvm.amdgcn.readfirstlane");
#define uniform(x) __llvm_amdgcn_readfirstlane(x)
#else
#define uniform(x) (x)
#endif

INLINE
uint iDiv(uint v, uint d)
{
    uint r = (uint)((float)v * (1.0f / (float)d) + 0.00001f);
    return (r);
}

INLINE
uint iMod(uint v, uint u, uint d)
{
    uint r = v - mul24((uint)u, (uint)d);
    return (r);
}

INLINE
void calculateXYPos(uint linPos, uint width, uint* __restrict x, uint* __restrict y)
{

    (*y) = (uint)((float)linPos * (1.0f / (float)width) + 0.00001f);

    (*x) = linPos - mul24((*y), width);
}

INLINE
uint calculateOffset(uint stride, uint x, uint y)
{
    uint ret = y * stride + x;
    return (ret);
}

INLINE
void readDataVec2(uint lcl_id,
                  uint size,
                  uint lcl_p_stride,
                  __local _FLOAT2* lcl_data,
                  uint lcl_base,
                  UNUSED uint lcl_height,
                  uint lcl_width,
#if MLO_LARGE_MAP != 1
                  uint lcl_stride,
                  uint lcl_y,
                  uint lcl_x,
#endif
                  const __global _FLOAT* gbl_data,
                  uint2 gbl_base,
#if MLO_LARGE_MAP == 1
                  uint gbl_height,
                  uint gbl_width,
#endif
                  uint gbl_stride,
                  uint gbl_y,
                  uint gbl_x,
                  bool visX,
                  bool visY,
#if MLO_N_INPUTS % (2 * MLO_N_IN_TILES_PERSTACK) <= MLO_N_IN_TILES_PERSTACK
                  bool IsLast,
#endif
                  UNUSED bool debug)
{

    uint x, y;
    for(uint i = lcl_id; i < size; i += lcl_p_stride)
    {
        bool lvisX = visX, lvisY = visY;
        calculateXYPos(i, lcl_width, &x, &y);
        uint g_x         = x + gbl_x;
        uint g_y         = y + gbl_y;
        uint gbl_off0    = calculateOffset(gbl_stride, g_x, g_y);
        uint2 gbl_off_v2 = (uint2)(gbl_off0) + gbl_base;

#if MLO_LARGE_MAP == 1
        uint lcl_off = lcl_base + i;
        lvisX &= (g_x < gbl_width && g_y < gbl_height);
        lvisY &= (g_x < gbl_width && g_y < gbl_height);
#else
        uint l_x            = x + lcl_x;
        uint l_y            = y + lcl_y;
        uint lcl_off        = lcl_base + mad24(l_y, lcl_stride, l_x);
#endif
        lcl_data[lcl_off].x = (lvisX) ? gbl_data[gbl_off_v2.x] : (_FLOAT)0;
#if MLO_N_INPUTS % (2 * MLO_N_IN_TILES_PERSTACK) <= MLO_N_IN_TILES_PERSTACK
        lcl_data[lcl_off].y = (IsLast) ? (_FLOAT)0 : ((lvisY) ? gbl_data[gbl_off_v2.y] : (_FLOAT)0);
#else
        lcl_data[lcl_off].y = (lvisY) ? gbl_data[gbl_off_v2.y] : (_FLOAT)0;
#endif
    }
}

INLINE
void Conv(uint o_map_base,
          uint in_stg_off,
          __private _FLOAT2* __restrict pvt_in_stage,
          __local _FLOAT2* __restrict lcl_indata,
          __private _FLOAT2* __restrict pvt_wei_stage,
          __local _FLOAT2* __restrict lcl_wei,
          __private _FLOAT2* __restrict pvt_accum)
{
    // convolution

    // over all inputs in stack
    uint in_stg_off1 = in_stg_off;
    for(uint i_c = 0; i_c < MLO_N_IN_TILES_PERSTACK; ++i_c, in_stg_off1 += MLO_IN_LCL_TILE_SZ)
    {
        // preload input
        uint wei_stg_base_off = mad24(o_map_base,
                                      (uint)(MLO_N_IN_TILES_PERSTACK * MLO_FILTER_SZ),
                                      mul24(i_c, (uint)MLO_FILTER_SZ));
        uint in_stg_off2 = in_stg_off1;
        for(uint j = 0; j < MLO_PVT_IN_HEIGHT - 1; ++j, in_stg_off2 += MLO_IN_LCL_WIDTH)
        {
            for(uint i = 0; i < MLO_PVT_IN_WIDTH; ++i)
            {
                pvt_in_stage[j * MLO_PVT_IN_WIDTH + i] = lcl_indata[in_stg_off2 + i];
            }
        }

// over filter rows
#ifdef __AMDGCN__
#if(MLO_FILTER_SZ > 9) || (MLO_IN_CHANNEL_STRIDE <= 196) || \
    (MLO_IN_CHANNEL_STRIDE > 784 && MLO_DIR_FORWARD != 1)
#pragma unroll
#else
#pragma unroll 2
#endif
#endif
        for(uint k = 0; k < MLO_FILTER_SIZE1; ++k, in_stg_off2 += MLO_IN_LCL_WIDTH)
        {
            uint k_act = 0;
#if MLO_DIR_FORWARD == 1
            k_act = k;
#else
            // load filter in reverse order
            k_act = MLO_FILTER_SIZE1 - 1 - k;
#endif
            // load next input row
            for(uint i_pvt = 0; i_pvt < MLO_PVT_IN_WIDTH; ++i_pvt)
            {
                pvt_in_stage[(MLO_PVT_IN_HEIGHT - 1) * MLO_PVT_IN_WIDTH + i_pvt] =
                    lcl_indata[in_stg_off2 + i_pvt];
            }

            // over all outputs
            for(uint o_c = 0; o_c < MLO_N_OUT_TILES; ++o_c)
            {
                uint wei_stg_off = wei_stg_base_off +
                                   o_c * MLO_N_IN_TILES_PERSTACK * MLO_FILTER_SZ +
                                   k_act * MLO_FILTER_SIZE0;
                for(uint i = 0; i < MLO_FILTER_SIZE0; ++i)
                {
                    pvt_wei_stage[i] = lcl_wei[wei_stg_off + i];
                }

                // actual conv

                for(uint j = 0; j < MLO_OUT_PIX_TILE1; ++j)
                {
                    for(uint i = 0; i < MLO_OUT_PIX_TILE0; ++i)
                    {
                        _FLOAT2 sum = (_FLOAT2)(0);
                        for(uint l = 0; l < MLO_FILTER_SIZE0; ++l)
                        {

                            uint l_act = 0;
#if MLO_DIR_FORWARD == 1
                            l_act = l;

#else
                            // in reverse horizontal and vertical orders
                            l_act = MLO_FILTER_SIZE0 - 1 - l;

#endif

                            sum +=
                                pvt_in_stage[j * MLO_PVT_IN_WIDTH + i + l] * pvt_wei_stage[l_act];
                        }
                        pvt_accum[(o_c * MLO_OUT_PIX_TILE1 + j) * MLO_OUT_PIX_TILE0 + i] += sum;
                    }
                }

            } // for(uint o_c = 0; o_c < MLO_N_OUT_TILES; ++o_c)

            // move data up
            for(uint j = 0; j < MLO_PVT_IN_HEIGHT - 1; ++j)
            {
                for(uint i = 0; i < MLO_PVT_IN_WIDTH; ++i)
                {
                    pvt_in_stage[j * MLO_PVT_IN_WIDTH + i] =
                        pvt_in_stage[(j + 1) * MLO_PVT_IN_WIDTH + i];
                }
            }

            //			mem_fence(CLK_LOCAL_MEM_FENCE);

        } // for(uint k = 0; k < MLO_FILER_SIZE1; ++k,in_stg_off2+=MLO_IN_LCL_WIDTH)

    } // for(uint i_c = 0; i_c < MLO_N_IN_TILES_PERSTACK; ++i_c, in_stg_off1 +=
      // MLO_IN_LCL_PERSTACK_SZ)
}

INLINE
__kernel void MIOpenConvUniC(const __global _FLOAT* __restrict in,
                             const __global _FLOAT* __restrict weights,
#if MLO_CONV_BIAS == 1
                             const __global _FLOAT* __restrict bias,
#endif
                             __global _FLOAT* __restrict out,
                             UNUSED _FLOAT padding_val)
{
    // Local and private arrays are defined as _FLOAT2
    __local _FLOAT2 lcl_indata[MLO_IN_LCL_SZ];
    __local _FLOAT2 lcl_wei[MLO_WEIGHTS_SZ];

    __private _FLOAT2 pvt_accum[MLO_PVT_ACCUM_DATA_SZ] = {MLO_PVT_ACCUM_DATA_SZ * ((_FLOAT2)(0))};
    __private _FLOAT2 pvt_in_stage[MLO_PVT_IN_HEIGHT * MLO_PVT_IN_WIDTH];
    __private _FLOAT2 pvt_wei_stage[MLO_FILTER_SIZE0];

    uint grp_id0 = get_group_id(0);
#if MLO_OUT_WIDTH == MLO_IN_TILE0
    uint y_tile_blk = grp_id0;
    uint x_tile_blk = 0;
#else
#if MLO_N_OUT_TILE_BLOCKS0 & (MLO_N_OUT_TILE_BLOCKS0 - 1)
    uint y_tile_blk               = IDIV(grp_id0, MLO_N_OUT_TILE_BLOCKS0);
    uint x_tile_blk               = IMOD(grp_id0, y_tile_blk, MLO_N_OUT_TILE_BLOCKS0);
#else
    uint y_tile_blk = grp_id0 / MLO_N_OUT_TILE_BLOCKS0;
    uint x_tile_blk = grp_id0 & (MLO_N_OUT_TILE_BLOCKS0 - 1);
#endif
#endif
    uint o_pack = get_group_id(1); // block of outputs
    uint b_pack = get_group_id(2); // batch block

    uint lcl_id = get_local_id(0);
#if MLO_ALUTILES_STACK_SZ & (MLO_ALUTILES_STACK_SZ - 1)
    uint stack        = IDIV(lcl_id, MLO_ALUTILES_STACK_SZ);        // stack
    uint alu_stack_id = IMOD(lcl_id, stack, MLO_ALUTILES_STACK_SZ); // alu index in stack
#else
    uint stack                    = lcl_id / MLO_ALUTILES_STACK_SZ; // stack
    uint alu_stack_id = lcl_id & (MLO_ALUTILES_STACK_SZ - 1); // alu index in stack
#if MLO_ALUTILES_STACK_SZ >= 64
    stack                 = uniform(stack);
#endif
#endif
// ALU plane inside stack
#if MLO_ALU_TILE_SZ & (MLO_ALU_TILE_SZ - 1)
    uint alu_out_plane_id = IDIV(alu_stack_id, MLO_ALU_TILE_SZ); // alu output plane index
    uint alu_out_id       = IMOD(
        alu_stack_id, alu_out_plane_id, MLO_ALU_TILE_SZ); // alu index inside an ALU output plane
#else
    uint alu_out_plane_id = alu_stack_id / MLO_ALU_TILE_SZ;       // alu output plane index
    uint alu_out_id       = alu_stack_id & (MLO_ALU_TILE_SZ - 1); // alu index inside an ALU output plane
#endif
// pos inside ALU tile
#if MLO_ALU_VTILE0 & (MLO_ALU_VTILE0 - 1)
    uint alu_tl1 = IDIV(alu_out_id, MLO_ALU_VTILE0);
    uint alu_tl0 = IMOD(alu_out_id, alu_tl1, MLO_ALU_VTILE0);
#else
    uint alu_tl1          = alu_out_id / MLO_ALU_VTILE0;
    uint alu_tl0          = alu_out_id & (MLO_ALU_VTILE0 - 1);
#endif

    uint o_map_plane =
        o_pack * MLO_N_OUT_TILES_PERSTACK; // first output maps index per full ALU plane stack
    uint o_map_base = alu_out_plane_id * MLO_N_OUT_TILES; // local output map offset
    uint o_map      = o_map_plane + o_map_base;           // output map index per ALU plane
    uint b_index    = b_pack * MLO_N_STACKS;

#if MLO_LARGE_MAP != 1
#if MLO_GRP_SZ <= MLO_N_READ_PROCS
    uint wave_id     = 0;
    uint wave_lcl_id = lcl_id;
#elif MLO_N_READ_PROCS & (MLO_N_READ_PROCS - 1)
    uint wave_id     = IDIV(lcl_id, MLO_N_READ_PROCS);
    uint wave_lcl_id = IMOD(lcl_id, wave_id, MLO_N_READ_PROCS);
#else
    uint wave_id     = (uint)((uint)lcl_id / MLO_N_READ_PROCS);
    uint wave_lcl_id = lcl_id & (MLO_N_READ_PROCS - 1);
#if MLO_N_READ_PROCS >= 64
    wave_id          = uniform(wave_id);
#endif
#endif
#endif

    uint x_grp = x_tile_blk * MLO_IN_TILE0;
    uint y_grp = y_tile_blk * MLO_IN_TILE1;

// TO DO: scale
#if MLO_LARGE_MAP == 1
    uint x_in_grp = x_grp - MLO_FILTER_PAD0;
    uint y_in_grp = y_grp - MLO_FILTER_PAD1;
#endif
    uint x_in_lcl = alu_tl0 * MLO_OUT_PIX_TILE0;
    uint y_in_lcl = alu_tl1 * MLO_OUT_PIX_TILE1;

    // base offset to read data from local input data
    uint in_stg_off = stack * MLO_IN_LCL_PERSTACK_SZ + (y_in_lcl)*MLO_IN_LCL_WIDTH + x_in_lcl;

    uint in_off    = b_index * MLO_IN_BATCH_STRIDE;
    uint2 in_offv2 = (uint2)(in_off, in_off + MLO_IN_CHANNEL_STRIDE * MLO_N_IN_TILES_PERSTACK);

#if MLO_DIR_FORWARD == 1
    uint wei_off    = mul24(o_map_plane, (uint)(MLO_N_INPUTS * MLO_FILTER_SZ));
    uint2 wei_offv2 = (uint2)(wei_off, wei_off + MLO_N_IN_TILES_PERSTACK * MLO_FILTER_SZ);
#else
    uint wei_off          = mul24(o_map_plane, (uint)MLO_FILTER_SZ);
    uint2 wei_offv2 =
        (uint2)(wei_off, wei_off + MLO_N_IN_TILES_PERSTACK * MLO_FILTER_SZ * MLO_N_OUTPUTS);
#endif

#if MLO_LARGE_MAP == 0
    for(uint i = lcl_id; i < MLO_IN_LCL_SZ; i += MLO_GRP_SZ)
    {
        lcl_indata[i] = (_FLOAT2)(0);
    }
#endif

    for(uint i = 0; i < MLO_PVT_ACCUM_DATA_SZ; ++i)
    {
        pvt_accum[i] = (_FLOAT2)(0);
    }

    // Two consecutive inputs are packed into _FLOAT2 vectors.
    for(uint ic = 0; ic < MLO_N_INPUTS; ic += 2 * MLO_N_IN_TILES_PERSTACK,
             in_offv2 += (uint2)(2 * MLO_IN_CHANNEL_STRIDE * MLO_N_IN_TILES_PERSTACK),
             wei_offv2 += (uint2)(2 * MLO_N_IN_TILES_PERSTACK * MLO_FILTER_SZ
#if MLO_DIR_FORWARD != 1
                                  *
                                  MLO_N_OUTPUTS
#endif
                                  ))
    {
        barrier(CLK_LOCAL_MEM_FENCE);

#if MLO_N_INPUTS % (2 * MLO_N_IN_TILES_PERSTACK) <= MLO_N_IN_TILES_PERSTACK
        bool IsLast = (ic + MLO_N_IN_TILES_PERSTACK >= MLO_N_INPUTS);
#endif
// small map has been read in full continiously into the lDS buffer within padded rect,
// padding has been done on initilization.
// large map calculates padding on the fly and fills it with 0.

#if 1 // all inputs

#if MLO_LARGE_MAP == 1
        uint in_lcl_off1 = 0;
        uint2 in_off1    = in_offv2;
        for(uint i_b = 0; i_b < MLO_N_STACKS;
            ++i_b, in_off1 += (uint2)(MLO_IN_BATCH_STRIDE), in_lcl_off1 += MLO_IN_LCL_PERSTACK_SZ)
        {
            bool visX = true;
            bool visY = true;
#if MLO_BATCH_ALIGNED == 0
            visX &= (b_index + i_b < MLO_BATCH_SZ);
            visY &= (b_index + i_b < MLO_BATCH_SZ);
#endif

            // over all inputs in stack
            uint2 in_off2    = in_off1;
            uint in_lcl_off2 = in_lcl_off1;
            for(uint i_c = 0; i_c < MLO_N_IN_TILES_PERSTACK;
                ++i_c, in_off2 += (uint2)(MLO_IN_CHANNEL_STRIDE), in_lcl_off2 += MLO_IN_LCL_TILE_SZ)
            {
#if MLO_INPUTS_ALIGNED == 0
                visX &= (ic + i_c < MLO_N_INPUTS);
                visY &= (ic + MLO_N_IN_TILES_PERSTACK + i_c < MLO_N_INPUTS);
#endif
                readDataVec2(lcl_id,
                             (MLO_IN_LCL_HEIGHT * MLO_IN_LCL_WIDTH),
                             MLO_GRP_SZ0,
                             &lcl_indata[in_lcl_off2],
                             0,
                             MLO_IN_LCL_HEIGHT,
                             MLO_IN_LCL_WIDTH,
                             &in[0],
                             in_off2,
                             MLO_IN_HEIGHT,
                             MLO_IN_WIDTH,
                             MLO_IN_STRIDE,
                             y_in_grp,
                             x_in_grp,
                             visX,
                             visY,
#if MLO_N_INPUTS % (2 * MLO_N_IN_TILES_PERSTACK) <= MLO_N_IN_TILES_PERSTACK
                             IsLast,
#endif
                             true);
            }
        }
#else
#ifdef __AMDGCN__
#if(MLO_FILTER_SZ <= 9) && (MLO_IN_CHANNEL_STRIDE <= 784)
#pragma unroll
#endif
#endif
        for(uint i = wave_id; i < MLO_N_IN_TILES_TOTAL; i += MLO_N_PROC_WAVES)
        {
//(MLO_N_STACKS * MLO_N_OUT_TILES_PERSTACK)
#if MLO_N_IN_TILES_PERSTACK & (MLO_N_IN_TILES_PERSTACK - 1)
            uint i_b = IDIV(i, MLO_N_IN_TILES_PERSTACK);
            uint i_c = IMOD(i, i_b, MLO_N_IN_TILES_PERSTACK);
#else
            uint i_b = i / MLO_N_IN_TILES_PERSTACK;
            uint i_c = i & (MLO_N_IN_TILES_PERSTACK - 1);
#endif

            bool visX = true;
            bool visY = true;

#if MLO_BATCH_ALIGNED == 0
            visX &= (b_index + i_b < MLO_BATCH_SZ);
            visY &= (b_index + i_b < MLO_BATCH_SZ);
#endif

#if MLO_INPUTS_ALIGNED == 0
            visX &= (ic + i_c < MLO_N_INPUTS);
            visY &= (ic + MLO_N_IN_TILES_PERSTACK + i_c < MLO_N_INPUTS);
#endif
            uint2 in_off2 =
                in_offv2 + (uint2)(i_b * MLO_IN_BATCH_STRIDE + i_c * MLO_IN_CHANNEL_STRIDE);
            uint in_lcl_off2 = i_b * MLO_IN_LCL_PERSTACK_SZ + i_c * MLO_IN_LCL_TILE_SZ;

            readDataVec2(wave_lcl_id,
                         (MLO_IN_HEIGHT * MLO_IN_WIDTH),
                         MLO_N_READ_PROCS,
                         &lcl_indata[in_lcl_off2],
                         0,
                         MLO_IN_HEIGHT,
                         MLO_IN_WIDTH,
                         MLO_IN_LCL_WIDTH,
                         MLO_FILTER_PAD1,
                         MLO_FILTER_PAD0,
                         &in[0],
                         in_off2,
                         MLO_IN_STRIDE,
                         y_grp,
                         x_grp,
                         visX,
                         visY,
#if MLO_N_INPUTS % (2 * MLO_N_IN_TILES_PERSTACK) <= MLO_N_IN_TILES_PERSTACK
                         IsLast,
#endif
                         true);
        }
#endif

// read inputs and weights
// put weights into LDS

#if 1 // only weights

#if(MLO_WEIGHTS_SZ >= MLO_GRP_SZ) && defined(__AMDGCN__)
#if MLO_WEIGHTS_SZ / MLO_GRP_SZ > 4
#pragma unroll
#else
#pragma unroll(MLO_WEIGHTS_SZ / MLO_GRP_SZ)
#endif
#endif
        for(uint i = lcl_id; i < MLO_WEIGHTS_SZ; i += MLO_GRP_SZ)
        {
#if MLO_DIR_FORWARD == 1
// here is [tops][bottoms]
#if(MLO_N_IN_TILES_PERSTACK * MLO_FILTER_SZ) & ((MLO_N_IN_TILES_PERSTACK * MLO_FILTER_SZ) - 1)
            uint lcl_o = IDIV(i, (MLO_N_IN_TILES_PERSTACK * MLO_FILTER_SZ));
            uint gbl_i = IMOD(i, lcl_o, (MLO_N_IN_TILES_PERSTACK * MLO_FILTER_SZ));
#else
            uint lcl_o = i / (MLO_N_IN_TILES_PERSTACK * MLO_FILTER_SZ);
            uint gbl_i = i & ((MLO_N_IN_TILES_PERSTACK * MLO_FILTER_SZ) - 1);
#endif
            if((wei_offv2.x + lcl_o * MLO_N_INPUTS * MLO_FILTER_SZ + gbl_i) <
               (MLO_N_OUTPUTS * MLO_N_INPUTS * MLO_FILTER_SZ))
                lcl_wei[i].x = weights[wei_offv2.x + lcl_o * MLO_N_INPUTS * MLO_FILTER_SZ + gbl_i];
            else
                lcl_wei[i].x = weights[0];
            if((wei_offv2.y + lcl_o * MLO_N_INPUTS * MLO_FILTER_SZ + gbl_i) <
               (MLO_N_OUTPUTS * MLO_N_INPUTS * MLO_FILTER_SZ))
                lcl_wei[i].y = weights[wei_offv2.y + lcl_o * MLO_N_INPUTS * MLO_FILTER_SZ + gbl_i];
            else
                lcl_wei[i].y = weights[0];
#else
// outputs are botoms(inputs))
// inputs are tops(outputs)

#if(MLO_N_OUT_TILES_PERSTACK * MLO_FILTER_SZ) & ((MLO_N_OUT_TILES_PERSTACK * MLO_FILTER_SZ) - 1)
            uint lcl_o = IDIV(i, (MLO_N_OUT_TILES_PERSTACK * MLO_FILTER_SZ));
            uint gbl_i = IMOD(i, lcl_o, (MLO_N_OUT_TILES_PERSTACK * MLO_FILTER_SZ));
#else
            uint lcl_o            = i / (MLO_N_OUT_TILES_PERSTACK * MLO_FILTER_SZ);
            uint gbl_i            = i & ((MLO_N_OUT_TILES_PERSTACK * MLO_FILTER_SZ) - 1);
#endif
#if MLO_FILTER_SZ & (MLO_FILTER_SZ - 1)
            uint lcl_c = IDIV(gbl_i, MLO_FILTER_SZ);
            uint lcl_i = IMOD(gbl_i, lcl_c, MLO_FILTER_SZ);
#else
            uint lcl_c            = gbl_i / MLO_FILTER_SZ;
            uint lcl_i            = gbl_i & (MLO_FILTER_SZ - 1);
#endif

            uint lcl_we_off = mad24(
                mad24(lcl_c, (uint)MLO_N_IN_TILES_PERSTACK, lcl_o), (uint)MLO_FILTER_SZ, lcl_i);
            uint2 gbl_we_off =
                (uint2)(mad24(mad24((uint2)(lcl_o), (uint2)(MLO_N_OUTPUTS), (uint2)(lcl_c)),
                              (uint2)(MLO_FILTER_SZ),
                              wei_offv2 + (uint2)(lcl_i)));
#if 0
			bool within_rangeX = gbl_we_off.x < (MLO_N_OUTPUTS*MLO_N_INPUTS*MLO_FILTER_SZ);
			bool within_rangeY = gbl_we_off.y < (MLO_N_OUTPUTS*MLO_N_INPUTS*MLO_FILTER_SZ);
			gbl_we_off.x = (within_rangeX) ? gbl_we_off.x : 0u;
			gbl_we_off.y = (within_rangeY) ? gbl_we_off.y : 0u;
			_FLOAT2 wei = (_FLOAT2)(weights[gbl_we_off.x], weights[gbl_we_off.y]);
			wei.x = (within_rangeX) ? wei.x : (_FLOAT)0;
			wei.y = (within_rangeY) ? wei.y : (_FLOAT)0;
			lcl_wei[lcl_we_off] = wei;
#else
            lcl_wei[lcl_we_off].x = (gbl_we_off.x < (MLO_N_OUTPUTS * MLO_N_INPUTS * MLO_FILTER_SZ))
                                        ? weights[gbl_we_off.x]
                                        : (_FLOAT)0;
            lcl_wei[lcl_we_off].y = (gbl_we_off.y < (MLO_N_OUTPUTS * MLO_N_INPUTS * MLO_FILTER_SZ))
                                        ? weights[gbl_we_off.y]
                                        : (_FLOAT)0;
#endif

#endif
        }

#endif

// over all batch stacks

#endif // all input

        barrier(CLK_LOCAL_MEM_FENCE);

// convolution
#if MLO_GRP_SZ > MLO_ACTIVE_ALUS
        if(lcl_id < MLO_ACTIVE_ALUS)
#endif
            Conv(o_map_base,
                 in_stg_off,
                 pvt_in_stage,
                 lcl_indata,
                 pvt_wei_stage,
                 lcl_wei,
                 pvt_accum);

        //		barrier(CLK_LOCAL_MEM_FENCE);
    }

#if MLO_GRP_SZ > MLO_ACTIVE_ALUS
    if(lcl_id >= MLO_ACTIVE_ALUS)
    {
        return;
    }
#endif
    // write results out
    uint x_out_grp = x_grp;
    uint y_out_grp = y_grp;
    uint x_out_lcl = alu_tl0 * MLO_OUT_PIX_TILE0;
    uint y_out_lcl = alu_tl1 * MLO_OUT_PIX_TILE1;

    uint out_off = (b_index + stack) * MLO_OUT_BATCH_STRIDE + o_map * MLO_OUT_CHANNEL_STRIDE +
                   (y_out_grp + y_out_lcl) * MLO_OUT_STRIDE + x_out_grp + x_out_lcl;
// over all local stacks
#if MLO_BATCH_ALIGNED == 0
    if(b_index + stack < MLO_BATCH_SZ)
#endif
    {

        // over all local outputs
        uint out_off1 = out_off;
        for(uint o = 0; o < MLO_N_OUT_TILES; ++o, out_off1 += MLO_OUT_CHANNEL_STRIDE)
        {
// over output tile
#if MLO_CONV_BIAS == 1
            _FLOAT bias_val = bias[o_map + o];
#endif
            uint out_off2 = out_off1;
            for(uint j = 0; j < MLO_OUT_PIX_TILE1; ++j, out_off2 += MLO_OUT_STRIDE)
            {
                __global _FLOAT* out_p = &out[out_off2];
                for(uint i = 0; i < MLO_OUT_PIX_TILE0; ++i)
                {
                    if(true
#if 1 // MLO_OUT_ALIGNED == 0
                       &&
                       y_out_lcl + j < MLO_OUT_TILE1 &&
                       y_out_grp + y_out_lcl + j < MLO_OUT_HEIGHT &&
                       x_out_lcl + i < MLO_OUT_TILE0 && x_out_grp + x_out_lcl + i < MLO_OUT_WIDTH
#endif
#if MLO_OUTPUTS_ALIGNED == 0
                       &&
                       o_map + o < MLO_N_OUTPUTS
#endif
                       )
                    {
#if MLO_N_INPUTS <= MLO_N_IN_TILES_PERSTACK
                        out_p[i] = pvt_accum[o * MLO_OUT_TILE_SZ + j * MLO_OUT_PIX_TILE0 + i].x
#else
                        out_p[i] = pvt_accum[o * MLO_OUT_TILE_SZ + j * MLO_OUT_PIX_TILE0 + i].x +
                                   pvt_accum[o * MLO_OUT_TILE_SZ + j * MLO_OUT_PIX_TILE0 + i].y
#endif
#if MLO_CONV_BIAS == 1
                                   + bias_val
#endif
                            ;
                    }
                }
            }
        }
    }
}