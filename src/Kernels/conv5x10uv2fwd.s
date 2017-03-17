/*
 * Convolution Kernel for 5x10 kernel with stride=2 pad=0 
 *
 */

.hsa_code_object_version 2,1
.hsa_code_object_isa

///////////////////////////////////////////////////
// ******* global-work and work-group-size
//  work-group-size = [64, 8, 1]
//  global-work = [align(out_w,64), (align(out_h,4)/4)*align(wei_k/2,8), batch_n]
//    * def align(a,b) = ((a + b - 1)/b)*b
//    * NOTE: wei_k must be multiple of 2
///////////////////////////////////////////////////
// ******* changeable configuration parameters
//   inp_w      - input image width
//   inp_h      - input image height
//   wei_c      - input image channels
//   wei_k      - output image channels
//   wei_layout - weights layout 0:"KCHW" or 1:"CKHW"
.ifndef params_defined
.set inp_w       , 341
.set inp_h       ,  79
.set wei_c       ,  32
.set wei_k       ,  32
.set wei_layout  ,   0
.endif
.if (wei_k % 2) != 0
.err "ERROR: wei_k must be multiple of 2"
.endif
// ******* fixed configuration parameters
.set wei_w       ,  10
.set wei_h       ,   5
.set inp_u       ,   2
.set inp_v       ,   2
// ******* LDS allocation
.set LDS_SIZE    ,4*(64*inp_u-1+(wei_w-1))*(4*inp_v-1+(wei_h-1))+32 // = 6016 bytes
// ******* SGPR allocation
// For used during initialization or as temporary
.set sreg_karg   ,   4   // [2]
.set sreg_group_0,   6   // [1]
.set sreg_group_1,   7   // [1]
.set sreg_group_2,   8   // [1]
.set sreg_tmp0   ,   9   // [1]
.set sreg_tmp1   ,  10   // [1]
.set sreg_tmp2   ,  11   // [1]
.set sreg_iinc   ,  12   // [1]
.set sreg_winc   ,  13   // [1]
.set sreg_inp_addr, 14   // [2]
.set sreg_out_addr, 16   // [2]
.set sreg_dswr1vcc, 18   // [2]
.set sreg_k       , 20   // [1]
.set sreg_c       , 21   // [1]
.set sreg_dy      , 22   // [1]
// For use during core-loop and later
.set sreg_wval    ,  0   // [50]
.set sreg_wei_addr,100   // [2]
.set SGPR_COUNT   ,102   // COUNT
// ******* VGPR allocation
// For used during initialization
.set vreg_local_0 ,  0   // [1]
.set vreg_local_1 ,  1   // [1]
.set vreg_local_2 ,  2   // [1] unused
.set vreg_tmp0    ,  3   // [1]
.set vreg_tmp1    ,  4   // [1]
.set vreg_tmp2    ,  5   // [1]
.set vreg_tmp3    ,  6   // [1]
.set vreg_iinc0   ,  7   // [1]
.set vreg_iinc1   ,  8   // [1]
.set vreg_oinc    ,  9   // [1]
// For use during core-loop and later
.set vreg_ival    ,  0   // [8]
.set vreg_oval    ,  8   // [4]
.set vreg_out_addr, 16   // [2]
.set vreg_inp_addr0,18   // [2]
.set vreg_inp_addr1,20   // [2]
.set vreg_inp_dswr0,22   // [1]
.set vreg_inp_dswr1,23   // [1]
.set vreg_inp_dsrd0,24   // [1]
.set vreg_inp_dsrd1,25   // [1]
.set vreg_dx      , 26   // [1]
.set vreg_save    , 27   // [1]
.set VGPR_COUNT    ,28   // COUNT
// ******* derived constants
.set out_w       ,(inp_w + inp_u - wei_w) / inp_u
.set out_h       ,(inp_h + inp_v - wei_h) / inp_v
.set inp_stride_y,(inp_w * 4)
.set inp_stride_c,(inp_h * inp_stride_y)
.set inp_stride_n,(wei_c * inp_stride_c)
.set out_stride_y,(out_w * 4)
.set out_stride_k,(out_h * out_stride_y)
.set out_stride_n,(wei_k * out_stride_k)
.if wei_layout == 0 // KCHW
.set wei_stride_c,(wei_h * wei_w * 4)
.set wei_stride_k,(wei_c * wei_stride_c)
.elseif wei_layout == 1 // CKHW
.set wei_stride_k,(wei_h * wei_w * 4)
.set wei_stride_c,(wei_c * wei_stride_k)
.else
.err "ERROR: wei_layout should be 0 (for:KCHW) or 1 (for:CKHW)"
.endif
.macro .bitcount, n, bits
  .if (1 << \bits) < \n
    .set \bits, \bits + 1
    .bitcount wei_k, wei_k_bits
  .endif
.endm
.set wei_k_bits  , 0
.bitcount wei_k  , wei_k_bits
.set wei_k_mask  , ((1 << wei_k_bits) - 1)

///////////////////////////////////////////////////
// ******* text section of the kernels
///////////////////////////////////////////////////
.text
.p2align 8
.global conv5x10uv2fwd
.type conv5x10uv2fwd, @function
.amdgpu_hsa_kernel conv5x10uv2fwd
conv5x10uv2fwd:

	.amd_kernel_code_t
		float_mode = 192
		user_sgpr_count = 6
		enable_sgpr_workgroup_id_x = 1
		enable_sgpr_workgroup_id_y = 1
		enable_sgpr_workgroup_id_z = 1
		enable_sgpr_workgroup_info = 0
		enable_vgpr_workitem_id = 1
		enable_sgpr_private_segment_buffer = 1
		enable_sgpr_dispatch_ptr = 0
		enable_sgpr_queue_ptr = 0
		enable_sgpr_kernarg_segment_ptr = 1
		enable_sgpr_grid_workgroup_count_x = 0
		enable_sgpr_grid_workgroup_count_y = 0
		enable_sgpr_grid_workgroup_count_z = 0
		workitem_vgpr_count = VGPR_COUNT
		wavefront_sgpr_count = SGPR_COUNT
		workgroup_group_segment_byte_size = LDS_SIZE
		granulated_workitem_vgpr_count = (VGPR_COUNT-1)/4
		granulated_wavefront_sgpr_count = (SGPR_COUNT-1)/8
		granulated_lds_size = (LDS_SIZE+511)/512
	.end_amd_kernel_code_t

	//////////////////////////////////////////////////////////////////////////////
	// initialization
	//  - work-items:
	//      work-group-size = [64, 8, 1]
	//      global-work = [align(out_w,64), (align(out_h,4)/4)*align(wei_k/2,8), batch_n]
	//      work-item relation to output buffer:
	//        dx =  global-work[0]
	//        dy = (global-work[1] >> (wei_k_bits-4)) * 4
	//        k  = (global-work[1] << 1) & wei_k_mask
	//        n  =  global-work[2]
	//      calculation:
	//        dx =  group_id(0) * 64 + local_id(0)
	//        dy = (group_id(1) >> (wei_k_bits-4)) * 4
	//        k  =((group_id(1) << 3) + local_id(1))*2 & wei_k_mask
	//        n  =  group_id(2)
	// - calculate vreg_wei_addr for current wave
	//      vreg_wei_addr += k * wei_stride_k
	//  - calculate vreg_out_addr for current work-item
	//      vreg_out_addr += n * out_stride_n + k * out_stride_k +
	//           dy * out_stride_y + dx * 4
	//      Note-1: vreg_out_addr is valid if (dx < out_w) && (dy < out_h) && (k < wei_k)
	//      Note-2: since work-item has 4 values, make sure not to write values outside out_h
	//  - calculate vreg_inp_addr0&1, vreg_inp_dswr0&1, vreg_inp_dsrd0&1
	//        vreg_inp_dsrd0 = local_id(0) * 8
	//        vreg_inp_addr0 = sreg_inp_addr + n * inp_stride_n +
	//            (dy * inp_v + local_id(1)) * inp_stride_y + dx * 4 * inp_u
	//        vreg_inp_dswr0 = local_id(0) * 8 + local_id(1) * 136 * 4
	//        if local_id(1) < 3:
	//          vreg_inp_addr1 = vreg_inp_addr0 + 8 * inp_stride_y
	//          vreg_inp_dswr1 = vreg_inp_dswr0 + 8 * 136 * 4
	//        else if local_id(1) == 3:
	//          vreg_inp_addr1 = sreg_inp_addr + n * inp_stride_n +
	//            (dy * inp_v + (local_id(0) >> 2)) * inp_stride_y +
	//            group_id(0) * 64 * 4 + 128 * 4 + (local_id(0) & 3) * 8
	//          vreg_inp_dswr1 = (local_id(0) >> 2) * 136 * 4 +
	//            128 * 4 + (local_id(0) & 3) * 8
	//        else:
	//          vreg_inp_addr1 & vreg_inp_dswr1 are not used
	//////////////////////////////////////////////////////////////////////////////
	s_mov_b32 m0, LDS_SIZE
	// load for parameters
	s_load_dwordx2 s[sreg_inp_addr:sreg_inp_addr+1], s[sreg_karg:sreg_karg+1], 0x00
	s_load_dwordx2 s[sreg_wei_addr:sreg_wei_addr+1], s[sreg_karg:sreg_karg+1], 0x08
	s_load_dwordx2 s[sreg_out_addr:sreg_out_addr+1], s[sreg_karg:sreg_karg+1], 0x10
	// compute: sreg_dx =  group_id(0) * 64 + local_id(0)
	//          sreg_dy = (group_id(1) >> (wei_k_bits-4)) * 4
	//          sreg_k  = (group_id(1) * 8 + local_id(1))*2 & wei_k_mask
	s_lshl_b32 s[sreg_tmp0], s[sreg_group_0], 6
	v_add_u32  v[vreg_dx], vcc, s[sreg_tmp0], v[vreg_local_0]
	s_lshr_b32 s[sreg_dy], s[sreg_group_1], wei_k_bits-4
	s_lshl_b32 s[sreg_dy], s[sreg_dy], 2
	v_readfirstlane_b32 s[sreg_k], v[vreg_local_1]
	s_lshl_b32 s[sreg_tmp0], s[sreg_group_1], 3
	s_add_u32  s[sreg_k], s[sreg_k], s[sreg_tmp0]
	s_lshl_b32 s[sreg_k], s[sreg_k], 1
	s_and_b32  s[sreg_k], s[sreg_k], wei_k_mask
	// compute: sreg_winc = k * wei_stride_k
	s_mul_i32  s[sreg_winc], s[sreg_k], wei_stride_k
	// compute: vreg_oinc = group_id(2) * out_stride_n + k * out_stride_k + dy * out_stride_y + dx * 4
	s_mul_i32  s[sreg_tmp0], s[sreg_group_2], out_stride_n
	s_mul_i32  s[sreg_tmp1], s[sreg_k], out_stride_k
	s_add_u32  s[sreg_tmp0], s[sreg_tmp0], s[sreg_tmp1]
	s_mul_i32  s[sreg_tmp1], s[sreg_dy], out_stride_y
	s_add_u32  s[sreg_tmp0], s[sreg_tmp0], s[sreg_tmp1]
	v_mad_u32_u24 v[vreg_oinc], v[vreg_dx], 4, s[sreg_tmp0]
	// compute: vreg_iinc0 = group_id(2) * inp_stride_n + dy * inp_v * inp_stride_y +
	//                       group_id(0) * 64 * 4 * inp_u +
	//                       local_id(0) * 8 + local_id(1) * inp_stride_y
	//          vreg_inp_dswr0 = local_id(0) * 8 + local_id(1) * 136 * 4
	//          vreg_iinc1 = (local_id(1) < 2)
	//                     ? vreg_iinc0 + 8 * inp_stride_y
	//                     : (local_id(0) >> 2) * inp_stride_y + 128 * 4 + (local_id(0) & 3) * 8
	//          vreg_inp_dswr1 = (local_id(1) < 2)
	//                     ? vreg_inp_dswr0 + 8 * 136 * 4
	//                     : (local_id(0) >> 2) * 136 * 4 + 128 * 4 + (local_id(0) & 3) * 8
	//          vreg_inp_dsrd0 = local_id(0) * 8
	s_mul_i32     s[sreg_iinc], s[sreg_group_2], inp_stride_n
	s_mul_i32     s[sreg_tmp0], s[sreg_dy], inp_stride_y * inp_v
	s_add_u32     s[sreg_iinc], s[sreg_iinc], s[sreg_tmp0]
	s_mul_i32     s[sreg_tmp0], s[sreg_group_0], 4 * 64 * inp_u
	s_add_u32     s[sreg_iinc], s[sreg_iinc], s[sreg_tmp0]
	s_movk_i32    s[sreg_tmp2], 0+inp_stride_y
	s_movk_i32    s[sreg_tmp1], 136*4
	v_lshlrev_b32 v[vreg_tmp0], 3, v[vreg_local_0]
	v_mad_u32_u24 v[vreg_iinc0], v[vreg_local_1], s[sreg_tmp2], v[vreg_tmp0]
	v_mad_u32_u24 v[vreg_inp_dswr0], v[vreg_local_1], s[sreg_tmp1], v[vreg_tmp0]
	v_add_u32     v[vreg_iinc0], vcc, s[sreg_iinc], v[vreg_iinc0]
	v_add_u32     v[vreg_iinc1], vcc, 8 * inp_stride_y, v[vreg_iinc0]
	v_add_u32     v[vreg_inp_dswr1], vcc, 8 * 136 * 4, v[vreg_inp_dswr0]
	v_and_b32     v[vreg_tmp0], 3, v[vreg_local_0]
	v_lshlrev_b32 v[vreg_tmp0], 3, v[vreg_tmp0]
	v_add_u32     v[vreg_tmp0], vcc, 128 * 4, v[vreg_tmp0]
	v_lshrrev_b32 v[vreg_tmp1], 2, v[vreg_local_0]
	v_mov_b32     v[vreg_tmp2], 0+inp_stride_y
	v_mad_u32_u24 v[vreg_tmp2], v[vreg_tmp2], v[vreg_tmp1], v[vreg_tmp0]
	v_add_u32     v[vreg_tmp2], vcc, s[sreg_iinc], v[vreg_tmp2]
	v_cmp_gt_u32  vcc, 3, v[vreg_local_1]
	v_mov_b32     v[vreg_tmp3], 136 * 4
	v_mad_u32_u24 v[vreg_tmp3], v[vreg_tmp3], v[vreg_tmp1], v[vreg_tmp0]
	v_cndmask_b32 v[vreg_iinc1], v[vreg_tmp2], v[vreg_iinc1], vcc
	v_cndmask_b32 v[vreg_inp_dswr1], v[vreg_tmp3], v[vreg_inp_dswr1], vcc
	v_lshlrev_b32 v[vreg_inp_dsrd0], 3, v[vreg_local_0]
	// check validity of vreg_inp_dswr1 and set a flag in vreg_dx
	//   flag = (local_1 * 64 + local_0 < 3*64+44) ? 0 : 1
	//   vreg_inp_dswr1 = flag ? 4*136*11 : vreg_inp_dswr1
	//   sreg_dswr1vcc(b64) = flag
	v_lshlrev_b32 v[vreg_tmp0], 6, v[vreg_local_1]
	v_add_i32     v[vreg_tmp0], vcc, v[vreg_local_0], v[vreg_tmp0]
	v_mov_b32     v[vreg_tmp1], 3*64+44
	v_cmp_ge_u32  vcc, v[vreg_tmp0], v[vreg_tmp1]
	v_mov_b32     v[vreg_tmp1], 4*136*11
	v_cndmask_b32 v[vreg_inp_dswr1], v[vreg_inp_dswr1], v[vreg_tmp1], vcc
	s_not_b64     s[sreg_dswr1vcc:sreg_dswr1vcc+1], vcc
	// wait for load completion
	s_waitcnt lgkmcnt(0)
	// update address registers
	s_add_u32  s[sreg_wei_addr], s[sreg_wei_addr], s[sreg_winc]
	s_addc_u32 s[sreg_wei_addr+1], s[sreg_wei_addr+1], 0
	v_add_u32  v[vreg_out_addr], vcc, s[sreg_out_addr], v[vreg_oinc]
	v_mov_b32  v[vreg_out_addr+1], s[sreg_out_addr+1]
	v_addc_u32 v[vreg_out_addr+1], vcc, v[vreg_out_addr+1], 0, vcc
	v_add_u32  v[vreg_inp_addr0], vcc, s[sreg_inp_addr], v[vreg_iinc0]
	v_mov_b32  v[vreg_inp_addr0+1], s[sreg_inp_addr+1]
	v_addc_u32 v[vreg_inp_addr0+1], vcc, v[vreg_inp_addr0+1], 0, vcc
	v_add_u32  v[vreg_inp_addr1], vcc, s[sreg_inp_addr], v[vreg_iinc1]
	v_mov_b32  v[vreg_inp_addr1+1], s[sreg_inp_addr+1]
	v_addc_u32 v[vreg_inp_addr1+1], vcc, v[vreg_inp_addr1+1], 0, vcc
	// initialize output values and channel count
	s_movk_i32 s[sreg_c], 0+wei_c
	v_mov_b32 v[vreg_oval+0], 0
	v_mov_b32 v[vreg_oval+1], 0
	v_mov_b32 v[vreg_oval+2], 0
	v_mov_b32 v[vreg_oval+3], 0
	v_mov_b32 v[vreg_oval+4], 0
	v_mov_b32 v[vreg_oval+5], 0
	v_mov_b32 v[vreg_oval+6], 0
	v_mov_b32 v[vreg_oval+7], 0
	// save sreg_c, sreg_k, sreg_dy, sreg_dswrvcc:sreg_dswrvcc+1 into vreg_save
	v_writelane_b32 v[vreg_save], s[sreg_dswr1vcc], 0
	v_writelane_b32 v[vreg_save], s[sreg_dswr1vcc+1], 1
	v_writelane_b32 v[vreg_save], s[sreg_c], 2
	v_writelane_b32 v[vreg_save], s[sreg_k], 3
	v_writelane_b32 v[vreg_save], s[sreg_dy], 4

	//////////////////////////////////////////////////////////////////////////////
	// loop though all channels:
	// registers with valid data from initialization
	//  - s[sreg_wei_addr:sreg_wei_addr+1]
	//  - v[vreg_save]
	//  - v[vreg_dx]
	//  - v[vreg_inp_addr0:vreg_inp_addr0+1]
	//  - v[vreg_inp_addr1:vreg_inp_addr1+1]
	//  - v[vreg_dswr0]
	//  - v[vreg_dswr1]
	//  - v[vreg_dsrd0]
	//  - v[vreg_out_addr:vreg_out_addr+1]
	//  - v[vreg_oval:vreg_oval+7]
	// temporary registers used inside this loop:
	//  - s[sreg_wval:sreg_wval+99]
	//  - v[vreg_ival:vreg_ival+7]
	//  - v[vreg_dsrd1]
	//////////////////////////////////////////////////////////////////////////////
loop_channel:
	// load input row into LDS and precompute vreg_dsrd1 register
	v_readlane_b32 s[sreg_dswr1vcc], v[vreg_save], 0
	v_readlane_b32 s[sreg_dswr1vcc+1], v[vreg_save], 1
	flat_load_dwordx2 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_addr0:vreg_inp_addr0+1]
	s_mov_b64 exec, s[sreg_dswr1vcc:sreg_dswr1vcc+1]
	flat_load_dwordx2 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_addr1:vreg_inp_addr1+1]
	s_mov_b64 exec, -1
	v_mov_b32  v[vreg_ival+4], 0+inp_stride_c
	v_add_u32  v[vreg_inp_addr0], vcc, v[vreg_inp_addr0], v[vreg_ival+4]
	v_addc_u32 v[vreg_inp_addr0+1], vcc, v[vreg_inp_addr0+1], 0, vcc
	v_add_u32  v[vreg_inp_addr1], vcc, v[vreg_inp_addr1], v[vreg_ival+4]
	v_addc_u32 v[vreg_inp_addr1+1], vcc, v[vreg_inp_addr1+1], 0, vcc
	s_waitcnt lgkmcnt(0) vmcnt(0)
	s_barrier
	ds_write_b64 v[vreg_inp_dswr0], v[vreg_ival+0:vreg_ival+1]
	s_mov_b64 exec, s[sreg_dswr1vcc:sreg_dswr1vcc+1]
	ds_write_b64 v[vreg_inp_dswr1], v[vreg_ival+2:vreg_ival+3]
	s_mov_b64 exec, -1
	v_add_u32 v[vreg_inp_dsrd1], vcc, 2 * 136 * 4, v[vreg_inp_dsrd0]
	s_waitcnt lgkmcnt(0)
	s_barrier
	// load channel weights and update sreg_wei_addr for next loop iteration
	s_load_dwordx16 s[sreg_wval   :sreg_wval+15], s[sreg_wei_addr:sreg_wei_addr+1], 0
	s_load_dwordx16 s[sreg_wval+16:sreg_wval+31], s[sreg_wei_addr:sreg_wei_addr+1], 4*16
	s_load_dwordx16 s[sreg_wval+32:sreg_wval+47], s[sreg_wei_addr:sreg_wei_addr+1], 4*32
	s_load_dwordx2  s[sreg_wval+96:sreg_wval+97], s[sreg_wei_addr:sreg_wei_addr+1], 4*48
	s_add_u32  s[sreg_wei_addr], s[sreg_wei_addr], wei_stride_k
	s_addc_u32 s[sreg_wei_addr+1], s[sreg_wei_addr+1], 0
	s_load_dwordx16 s[sreg_wval+48:sreg_wval+63], s[sreg_wei_addr:sreg_wei_addr+1], 0
	s_load_dwordx16 s[sreg_wval+64:sreg_wval+79], s[sreg_wei_addr:sreg_wei_addr+1], 4*16
	s_load_dwordx16 s[sreg_wval+80:sreg_wval+95], s[sreg_wei_addr:sreg_wei_addr+1], 4*32
	s_load_dwordx2  s[sreg_wval+98:sreg_wval+99], s[sreg_wei_addr:sreg_wei_addr+1], 4*48
	s_add_u32  s[sreg_wei_addr], s[sreg_wei_addr], wei_stride_c-wei_stride_k
	s_addc_u32 s[sreg_wei_addr+1], s[sreg_wei_addr+1], -1
	s_waitcnt lgkmcnt(0) vmcnt(0)

	// compute 2D conv
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd0] offset0:0*136+0 offset1:0*136+1
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd0] offset0:0*136+2 offset1:0*136+3
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd0] offset0:0*136+4 offset1:0*136+5
	ds_read2_b32 v[vreg_ival+6:vreg_ival+7], v[vreg_inp_dsrd0] offset0:0*136+6 offset1:0*136+7
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+0], s[sreg_wval+0*10+0]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+1], s[sreg_wval+0*10+1]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+2], s[sreg_wval+0*10+2]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+3], s[sreg_wval+0*10+3]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+4], s[sreg_wval+0*10+4]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+5], s[sreg_wval+0*10+5]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+6], s[sreg_wval+0*10+6]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+7], s[sreg_wval+0*10+7]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+0], s[sreg_wval+0*10+0+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+1], s[sreg_wval+0*10+1+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+2], s[sreg_wval+0*10+2+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+3], s[sreg_wval+0*10+3+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+4], s[sreg_wval+0*10+4+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+5], s[sreg_wval+0*10+5+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+6], s[sreg_wval+0*10+6+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+7], s[sreg_wval+0*10+7+48]
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd0] offset0:0*136+8 offset1:0*136+9
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd0] offset0:1*136+0 offset1:1*136+1
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd0] offset0:1*136+2 offset1:1*136+3
	ds_read2_b32 v[vreg_ival+6:vreg_ival+7], v[vreg_inp_dsrd0] offset0:1*136+4 offset1:1*136+5
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+0], s[sreg_wval+0*10+8]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+1], s[sreg_wval+0*10+9]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+2], s[sreg_wval+1*10+0]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+3], s[sreg_wval+1*10+1]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+4], s[sreg_wval+1*10+2]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+5], s[sreg_wval+1*10+3]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+6], s[sreg_wval+1*10+4]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+7], s[sreg_wval+1*10+5]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+0], s[sreg_wval+0*10+8+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+1], s[sreg_wval+0*10+9+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+2], s[sreg_wval+1*10+0+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+3], s[sreg_wval+1*10+1+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+4], s[sreg_wval+1*10+2+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+5], s[sreg_wval+1*10+3+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+6], s[sreg_wval+1*10+4+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+7], s[sreg_wval+1*10+5+48]
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd0] offset0:1*136+6 offset1:1*136+7
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd0] offset0:1*136+8 offset1:1*136+9
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd1] offset0:0*136+0 offset1:0*136+1
	ds_read2_b32 v[vreg_ival+6:vreg_ival+7], v[vreg_inp_dsrd1] offset0:0*136+2 offset1:0*136+3
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+0], s[sreg_wval+1*10+6]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+1], s[sreg_wval+1*10+7]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+2], s[sreg_wval+1*10+8]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+3], s[sreg_wval+1*10+9]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+4], s[sreg_wval+2*10+0]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+5], s[sreg_wval+2*10+1]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+6], s[sreg_wval+2*10+2]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+7], s[sreg_wval+2*10+3]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+4], s[sreg_wval+0*10+0]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+5], s[sreg_wval+0*10+1]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+6], s[sreg_wval+0*10+2]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+7], s[sreg_wval+0*10+3]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+0], s[sreg_wval+1*10+6+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+1], s[sreg_wval+1*10+7+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+2], s[sreg_wval+1*10+8+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+3], s[sreg_wval+1*10+9+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+4], s[sreg_wval+2*10+0+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+5], s[sreg_wval+2*10+1+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+6], s[sreg_wval+2*10+2+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+7], s[sreg_wval+2*10+3+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+4], s[sreg_wval+0*10+0+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+5], s[sreg_wval+0*10+1+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+6], s[sreg_wval+0*10+2+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+7], s[sreg_wval+0*10+3+48]
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd1] offset0:0*136+4 offset1:0*136+5
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd1] offset0:0*136+6 offset1:0*136+7
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd1] offset0:0*136+8 offset1:0*136+9
	ds_read2_b32 v[vreg_ival+6:vreg_ival+7], v[vreg_inp_dsrd1] offset0:1*136+0 offset1:1*136+1
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+0], s[sreg_wval+2*10+4]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+1], s[sreg_wval+2*10+5]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+2], s[sreg_wval+2*10+6]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+3], s[sreg_wval+2*10+7]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+4], s[sreg_wval+2*10+8]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+5], s[sreg_wval+2*10+9]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+6], s[sreg_wval+3*10+0]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+7], s[sreg_wval+3*10+1]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+0], s[sreg_wval+0*10+4]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+1], s[sreg_wval+0*10+5]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+2], s[sreg_wval+0*10+6]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+3], s[sreg_wval+0*10+7]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+4], s[sreg_wval+0*10+8]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+5], s[sreg_wval+0*10+9]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+6], s[sreg_wval+1*10+0]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+7], s[sreg_wval+1*10+1]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+0], s[sreg_wval+2*10+4+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+1], s[sreg_wval+2*10+5+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+2], s[sreg_wval+2*10+6+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+3], s[sreg_wval+2*10+7+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+4], s[sreg_wval+2*10+8+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+5], s[sreg_wval+2*10+9+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+6], s[sreg_wval+3*10+0+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+7], s[sreg_wval+3*10+1+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+0], s[sreg_wval+0*10+4+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+1], s[sreg_wval+0*10+5+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+2], s[sreg_wval+0*10+6+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+3], s[sreg_wval+0*10+7+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+4], s[sreg_wval+0*10+8+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+5], s[sreg_wval+0*10+9+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+6], s[sreg_wval+1*10+0+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+7], s[sreg_wval+1*10+1+48]
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd1] offset0:1*136+2 offset1:1*136+3
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd1] offset0:1*136+4 offset1:1*136+5
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd1] offset0:1*136+6 offset1:1*136+7
	ds_read2_b32 v[vreg_ival+6:vreg_ival+7], v[vreg_inp_dsrd1] offset0:1*136+8 offset1:1*136+9
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+0], s[sreg_wval+3*10+2]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+1], s[sreg_wval+3*10+3]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+2], s[sreg_wval+3*10+4]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+3], s[sreg_wval+3*10+5]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+4], s[sreg_wval+3*10+6]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+5], s[sreg_wval+3*10+7]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+6], s[sreg_wval+3*10+8]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+7], s[sreg_wval+3*10+9]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+0], s[sreg_wval+1*10+2]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+1], s[sreg_wval+1*10+3]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+2], s[sreg_wval+1*10+4]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+3], s[sreg_wval+1*10+5]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+4], s[sreg_wval+1*10+6]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+5], s[sreg_wval+1*10+7]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+6], s[sreg_wval+1*10+8]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+7], s[sreg_wval+1*10+9]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+0], s[sreg_wval+3*10+2+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+1], s[sreg_wval+3*10+3+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+2], s[sreg_wval+3*10+4+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+3], s[sreg_wval+3*10+5+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+4], s[sreg_wval+3*10+6+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+5], s[sreg_wval+3*10+7+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+6], s[sreg_wval+3*10+8+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+7], s[sreg_wval+3*10+9+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+0], s[sreg_wval+1*10+2+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+1], s[sreg_wval+1*10+3+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+2], s[sreg_wval+1*10+4+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+3], s[sreg_wval+1*10+5+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+4], s[sreg_wval+1*10+6+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+5], s[sreg_wval+1*10+7+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+6], s[sreg_wval+1*10+8+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+7], s[sreg_wval+1*10+9+48]
	v_add_u32 v[vreg_inp_dsrd1], vcc, 4 * 136 * 4, v[vreg_inp_dsrd0]
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd1] offset0:0*136+0 offset1:0*136+1
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd1] offset0:0*136+2 offset1:0*136+3
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd1] offset0:0*136+4 offset1:0*136+5
	ds_read2_b32 v[vreg_ival+6:vreg_ival+7], v[vreg_inp_dsrd1] offset0:0*136+6 offset1:0*136+7
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+0], s[sreg_wval+4*10+0]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+1], s[sreg_wval+4*10+1]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+2], s[sreg_wval+4*10+2]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+3], s[sreg_wval+4*10+3]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+4], s[sreg_wval+4*10+4]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+5], s[sreg_wval+4*10+5]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+6], s[sreg_wval+4*10+6]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+7], s[sreg_wval+4*10+7]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+0], s[sreg_wval+2*10+0]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+1], s[sreg_wval+2*10+1]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+2], s[sreg_wval+2*10+2]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+3], s[sreg_wval+2*10+3]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+4], s[sreg_wval+2*10+4]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+5], s[sreg_wval+2*10+5]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+6], s[sreg_wval+2*10+6]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+7], s[sreg_wval+2*10+7]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+0], s[sreg_wval+0*10+0]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+1], s[sreg_wval+0*10+1]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+2], s[sreg_wval+0*10+2]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+3], s[sreg_wval+0*10+3]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+4], s[sreg_wval+0*10+4]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+5], s[sreg_wval+0*10+5]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+6], s[sreg_wval+0*10+6]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+7], s[sreg_wval+0*10+7]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+0], s[sreg_wval+4*10+0+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+1], s[sreg_wval+4*10+1+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+2], s[sreg_wval+4*10+2+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+3], s[sreg_wval+4*10+3+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+4], s[sreg_wval+4*10+4+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+5], s[sreg_wval+4*10+5+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+6], s[sreg_wval+4*10+6+48]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+7], s[sreg_wval+4*10+7+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+0], s[sreg_wval+2*10+0+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+1], s[sreg_wval+2*10+1+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+2], s[sreg_wval+2*10+2+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+3], s[sreg_wval+2*10+3+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+4], s[sreg_wval+2*10+4+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+5], s[sreg_wval+2*10+5+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+6], s[sreg_wval+2*10+6+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+7], s[sreg_wval+2*10+7+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+0], s[sreg_wval+0*10+0+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+1], s[sreg_wval+0*10+1+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+2], s[sreg_wval+0*10+2+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+3], s[sreg_wval+0*10+3+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+4], s[sreg_wval+0*10+4+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+5], s[sreg_wval+0*10+5+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+6], s[sreg_wval+0*10+6+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+7], s[sreg_wval+0*10+7+48]
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd1] offset0:0*136+8 offset1:0*136+9
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd1] offset0:1*136+0 offset1:1*136+1
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd1] offset0:1*136+2 offset1:1*136+3
	ds_read2_b32 v[vreg_ival+6:vreg_ival+7], v[vreg_inp_dsrd1] offset0:1*136+4 offset1:1*136+5
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+0], s[sreg_wval+4*10+8+48]
	v_mac_f32 v[vreg_oval+0], v[vreg_ival+1], s[sreg_wval+4*10+9+48]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+0], s[sreg_wval+2*10+8]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+1], s[sreg_wval+2*10+9]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+2], s[sreg_wval+3*10+0]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+3], s[sreg_wval+3*10+1]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+4], s[sreg_wval+3*10+2]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+5], s[sreg_wval+3*10+3]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+6], s[sreg_wval+3*10+4]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+7], s[sreg_wval+3*10+5]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+0], s[sreg_wval+0*10+8]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+1], s[sreg_wval+0*10+9]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+2], s[sreg_wval+1*10+0]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+3], s[sreg_wval+1*10+1]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+4], s[sreg_wval+1*10+2]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+5], s[sreg_wval+1*10+3]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+6], s[sreg_wval+1*10+4]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+7], s[sreg_wval+1*10+5]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+0], s[sreg_wval+4*10+8+50]
	v_mac_f32 v[vreg_oval+4], v[vreg_ival+1], s[sreg_wval+4*10+9+50]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+0], s[sreg_wval+2*10+8+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+1], s[sreg_wval+2*10+9+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+2], s[sreg_wval+3*10+0+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+3], s[sreg_wval+3*10+1+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+4], s[sreg_wval+3*10+2+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+5], s[sreg_wval+3*10+3+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+6], s[sreg_wval+3*10+4+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+7], s[sreg_wval+3*10+5+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+0], s[sreg_wval+0*10+8+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+1], s[sreg_wval+0*10+9+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+2], s[sreg_wval+1*10+0+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+3], s[sreg_wval+1*10+1+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+4], s[sreg_wval+1*10+2+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+5], s[sreg_wval+1*10+3+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+6], s[sreg_wval+1*10+4+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+7], s[sreg_wval+1*10+5+48]
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd1] offset0:1*136+6 offset1:1*136+7
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd1] offset0:1*136+8 offset1:1*136+9
	v_add_u32 v[vreg_inp_dsrd1], vcc, 6 * 136 * 4, v[vreg_inp_dsrd0]
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd1] offset0:0*136+0 offset1:0*136+1
	ds_read2_b32 v[vreg_ival+6:vreg_ival+7], v[vreg_inp_dsrd1] offset0:0*136+2 offset1:0*136+3
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+0], s[sreg_wval+3*10+6]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+1], s[sreg_wval+3*10+7]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+2], s[sreg_wval+3*10+8]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+3], s[sreg_wval+3*10+9]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+4], s[sreg_wval+4*10+0]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+5], s[sreg_wval+4*10+1]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+6], s[sreg_wval+4*10+2]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+7], s[sreg_wval+4*10+3]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+0], s[sreg_wval+1*10+6]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+1], s[sreg_wval+1*10+7]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+2], s[sreg_wval+1*10+8]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+3], s[sreg_wval+1*10+9]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+4], s[sreg_wval+2*10+0]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+5], s[sreg_wval+2*10+1]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+6], s[sreg_wval+2*10+2]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+7], s[sreg_wval+2*10+3]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+4], s[sreg_wval+0*10+0]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+5], s[sreg_wval+0*10+1]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+6], s[sreg_wval+0*10+2]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+7], s[sreg_wval+0*10+3]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+0], s[sreg_wval+3*10+6+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+1], s[sreg_wval+3*10+7+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+2], s[sreg_wval+3*10+8+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+3], s[sreg_wval+3*10+9+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+4], s[sreg_wval+4*10+0+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+5], s[sreg_wval+4*10+1+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+6], s[sreg_wval+4*10+2+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+7], s[sreg_wval+4*10+3+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+0], s[sreg_wval+1*10+6+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+1], s[sreg_wval+1*10+7+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+2], s[sreg_wval+1*10+8+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+3], s[sreg_wval+1*10+9+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+4], s[sreg_wval+2*10+0+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+5], s[sreg_wval+2*10+1+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+6], s[sreg_wval+2*10+2+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+7], s[sreg_wval+2*10+3+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+4], s[sreg_wval+0*10+0+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+5], s[sreg_wval+0*10+1+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+6], s[sreg_wval+0*10+2+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+7], s[sreg_wval+0*10+3+48]
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd1] offset0:0*136+4 offset1:0*136+5
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd1] offset0:0*136+6 offset1:0*136+7
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd1] offset0:0*136+8 offset1:0*136+9
	ds_read2_b32 v[vreg_ival+6:vreg_ival+7], v[vreg_inp_dsrd1] offset0:1*136+0 offset1:1*136+1
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+0], s[sreg_wval+4*10+4]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+1], s[sreg_wval+4*10+5]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+2], s[sreg_wval+4*10+6]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+3], s[sreg_wval+4*10+7]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+4], s[sreg_wval+4*10+8+48]
	v_mac_f32 v[vreg_oval+1], v[vreg_ival+5], s[sreg_wval+4*10+9+48]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+0], s[sreg_wval+2*10+4]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+1], s[sreg_wval+2*10+5]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+2], s[sreg_wval+2*10+6]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+3], s[sreg_wval+2*10+7]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+4], s[sreg_wval+2*10+8]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+5], s[sreg_wval+2*10+9]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+6], s[sreg_wval+3*10+0]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+7], s[sreg_wval+3*10+1]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+0], s[sreg_wval+0*10+4]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+1], s[sreg_wval+0*10+5]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+2], s[sreg_wval+0*10+6]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+3], s[sreg_wval+0*10+7]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+4], s[sreg_wval+0*10+8]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+5], s[sreg_wval+0*10+9]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+6], s[sreg_wval+1*10+0]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+7], s[sreg_wval+1*10+1]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+0], s[sreg_wval+4*10+4+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+1], s[sreg_wval+4*10+5+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+2], s[sreg_wval+4*10+6+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+3], s[sreg_wval+4*10+7+48]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+4], s[sreg_wval+4*10+8+50]
	v_mac_f32 v[vreg_oval+5], v[vreg_ival+5], s[sreg_wval+4*10+9+50]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+0], s[sreg_wval+2*10+4+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+1], s[sreg_wval+2*10+5+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+2], s[sreg_wval+2*10+6+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+3], s[sreg_wval+2*10+7+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+4], s[sreg_wval+2*10+8+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+5], s[sreg_wval+2*10+9+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+6], s[sreg_wval+3*10+0+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+7], s[sreg_wval+3*10+1+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+0], s[sreg_wval+0*10+4+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+1], s[sreg_wval+0*10+5+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+2], s[sreg_wval+0*10+6+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+3], s[sreg_wval+0*10+7+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+4], s[sreg_wval+0*10+8+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+5], s[sreg_wval+0*10+9+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+6], s[sreg_wval+1*10+0+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+7], s[sreg_wval+1*10+1+48]
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd1] offset0:1*136+2 offset1:1*136+3
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd1] offset0:1*136+4 offset1:1*136+5
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd1] offset0:1*136+6 offset1:1*136+7
	ds_read2_b32 v[vreg_ival+6:vreg_ival+7], v[vreg_inp_dsrd1] offset0:1*136+8 offset1:1*136+9
	v_add_u32 v[vreg_inp_dsrd1], vcc, 8 * 136 * 4, v[vreg_inp_dsrd0]
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+0], s[sreg_wval+3*10+2]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+1], s[sreg_wval+3*10+3]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+2], s[sreg_wval+3*10+4]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+3], s[sreg_wval+3*10+5]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+4], s[sreg_wval+3*10+6]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+5], s[sreg_wval+3*10+7]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+6], s[sreg_wval+3*10+8]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+7], s[sreg_wval+3*10+9]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+0], s[sreg_wval+1*10+2]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+1], s[sreg_wval+1*10+3]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+2], s[sreg_wval+1*10+4]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+3], s[sreg_wval+1*10+5]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+4], s[sreg_wval+1*10+6]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+5], s[sreg_wval+1*10+7]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+6], s[sreg_wval+1*10+8]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+7], s[sreg_wval+1*10+9]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+0], s[sreg_wval+3*10+2+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+1], s[sreg_wval+3*10+3+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+2], s[sreg_wval+3*10+4+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+3], s[sreg_wval+3*10+5+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+4], s[sreg_wval+3*10+6+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+5], s[sreg_wval+3*10+7+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+6], s[sreg_wval+3*10+8+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+7], s[sreg_wval+3*10+9+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+0], s[sreg_wval+1*10+2+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+1], s[sreg_wval+1*10+3+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+2], s[sreg_wval+1*10+4+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+3], s[sreg_wval+1*10+5+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+4], s[sreg_wval+1*10+6+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+5], s[sreg_wval+1*10+7+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+6], s[sreg_wval+1*10+8+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+7], s[sreg_wval+1*10+9+48]
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd1] offset0:0*136+0 offset1:0*136+1
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd1] offset0:0*136+2 offset1:0*136+3
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd1] offset0:0*136+4 offset1:0*136+5
	ds_read2_b32 v[vreg_ival+6:vreg_ival+7], v[vreg_inp_dsrd1] offset0:0*136+6 offset1:0*136+7
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+0], s[sreg_wval+4*10+0]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+1], s[sreg_wval+4*10+1]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+2], s[sreg_wval+4*10+2]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+3], s[sreg_wval+4*10+3]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+4], s[sreg_wval+4*10+4]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+5], s[sreg_wval+4*10+5]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+6], s[sreg_wval+4*10+6]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+7], s[sreg_wval+4*10+7]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+0], s[sreg_wval+2*10+0]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+1], s[sreg_wval+2*10+1]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+2], s[sreg_wval+2*10+2]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+3], s[sreg_wval+2*10+3]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+4], s[sreg_wval+2*10+4]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+5], s[sreg_wval+2*10+5]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+6], s[sreg_wval+2*10+6]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+7], s[sreg_wval+2*10+7]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+0], s[sreg_wval+4*10+0+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+1], s[sreg_wval+4*10+1+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+2], s[sreg_wval+4*10+2+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+3], s[sreg_wval+4*10+3+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+4], s[sreg_wval+4*10+4+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+5], s[sreg_wval+4*10+5+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+6], s[sreg_wval+4*10+6+48]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+7], s[sreg_wval+4*10+7+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+0], s[sreg_wval+2*10+0+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+1], s[sreg_wval+2*10+1+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+2], s[sreg_wval+2*10+2+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+3], s[sreg_wval+2*10+3+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+4], s[sreg_wval+2*10+4+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+5], s[sreg_wval+2*10+5+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+6], s[sreg_wval+2*10+6+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+7], s[sreg_wval+2*10+7+48]
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd1] offset0:0*136+8 offset1:0*136+9
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd1] offset0:1*136+0 offset1:1*136+1
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd1] offset0:1*136+2 offset1:1*136+3
	ds_read2_b32 v[vreg_ival+6:vreg_ival+7], v[vreg_inp_dsrd1] offset0:1*136+4 offset1:1*136+5
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+0], s[sreg_wval+4*10+8+48]
	v_mac_f32 v[vreg_oval+2], v[vreg_ival+1], s[sreg_wval+4*10+9+48]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+0], s[sreg_wval+2*10+8]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+1], s[sreg_wval+2*10+9]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+2], s[sreg_wval+3*10+0]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+3], s[sreg_wval+3*10+1]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+4], s[sreg_wval+3*10+2]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+5], s[sreg_wval+3*10+3]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+6], s[sreg_wval+3*10+4]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+7], s[sreg_wval+3*10+5]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+0], s[sreg_wval+4*10+8+50]
	v_mac_f32 v[vreg_oval+6], v[vreg_ival+1], s[sreg_wval+4*10+9+50]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+0], s[sreg_wval+2*10+8+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+1], s[sreg_wval+2*10+9+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+2], s[sreg_wval+3*10+0+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+3], s[sreg_wval+3*10+1+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+4], s[sreg_wval+3*10+2+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+5], s[sreg_wval+3*10+3+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+6], s[sreg_wval+3*10+4+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+7], s[sreg_wval+3*10+5+48]
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd1] offset0:1*136+6 offset1:1*136+7
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd1] offset0:1*136+8 offset1:1*136+9
	v_add_u32 v[vreg_inp_dsrd1], vcc,10 * 136 * 4, v[vreg_inp_dsrd0]
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd1] offset0:0*136+0 offset1:0*136+1
	ds_read2_b32 v[vreg_ival+6:vreg_ival+7], v[vreg_inp_dsrd1] offset0:0*136+2 offset1:0*136+3
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+0], s[sreg_wval+3*10+6]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+1], s[sreg_wval+3*10+7]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+2], s[sreg_wval+3*10+8]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+3], s[sreg_wval+3*10+9]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+4], s[sreg_wval+4*10+0]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+5], s[sreg_wval+4*10+1]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+6], s[sreg_wval+4*10+2]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+7], s[sreg_wval+4*10+3]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+0], s[sreg_wval+3*10+6+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+1], s[sreg_wval+3*10+7+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+2], s[sreg_wval+3*10+8+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+3], s[sreg_wval+3*10+9+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+4], s[sreg_wval+4*10+0+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+5], s[sreg_wval+4*10+1+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+6], s[sreg_wval+4*10+2+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+7], s[sreg_wval+4*10+3+48]
	ds_read2_b32 v[vreg_ival+0:vreg_ival+1], v[vreg_inp_dsrd1] offset0:0*136+4 offset1:0*136+5
	ds_read2_b32 v[vreg_ival+2:vreg_ival+3], v[vreg_inp_dsrd1] offset0:0*136+6 offset1:0*136+7
	ds_read2_b32 v[vreg_ival+4:vreg_ival+5], v[vreg_inp_dsrd1] offset0:0*136+8 offset1:0*136+9
	s_waitcnt lgkmcnt(0)
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+0], s[sreg_wval+4*10+4]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+1], s[sreg_wval+4*10+5]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+2], s[sreg_wval+4*10+6]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+3], s[sreg_wval+4*10+7]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+4], s[sreg_wval+4*10+8+48]
	v_mac_f32 v[vreg_oval+3], v[vreg_ival+5], s[sreg_wval+4*10+9+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+0], s[sreg_wval+4*10+4+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+1], s[sreg_wval+4*10+5+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+2], s[sreg_wval+4*10+6+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+3], s[sreg_wval+4*10+7+48]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+4], s[sreg_wval+4*10+8+50]
	v_mac_f32 v[vreg_oval+7], v[vreg_ival+5], s[sreg_wval+4*10+9+50]

	// loop if more channels needs to be processed
	v_readlane_b32 s[sreg_c], v[vreg_save], 2
	s_sub_u32  s[sreg_c], s[sreg_c], 1
	v_writelane_b32 v[vreg_save], s[sreg_c], 2
	s_cmp_gt_u32 s[sreg_c], 0
	s_cbranch_scc1 loop_channel

	//////////////////////////////////////////////////////////////////////////////
	// write output values
	//  - do bound checks before writing
	//  - use s[sreg_wei_addr:sreg_wei_addr+1] as temporary registers
	v_readlane_b32 s[sreg_k], v[vreg_save], 3
	v_readlane_b32 s[sreg_dy], v[vreg_save], 4
	v_mov_b32 v[vreg_ival+0], v[vreg_out_addr+0]
	v_mov_b32 v[vreg_ival+1], v[vreg_out_addr+1]
	v_cmpx_gt_u32 vcc, 0+out_w, v[vreg_dx]
	s_cmpk_ge_u32 s[sreg_k], 0+wei_k
	s_cbranch_scc1 skip_write0
	flat_store_dword v[vreg_out_addr:vreg_out_addr+1], v[vreg_oval]
	s_cmpk_ge_u32 s[sreg_dy], 0+out_h-1
	s_cbranch_scc1 skip_write0
	v_add_u32  v[vreg_out_addr], vcc, 0+out_stride_y, v[vreg_out_addr]
	v_addc_u32 v[vreg_out_addr+1], vcc, v[vreg_out_addr+1], 0, vcc
	flat_store_dword v[vreg_out_addr:vreg_out_addr+1], v[vreg_oval+1]
	s_cmpk_ge_u32 s[sreg_dy], 0+out_h-2
	s_cbranch_scc1 skip_write0
	v_add_u32  v[vreg_out_addr], vcc, 0+out_stride_y, v[vreg_out_addr]
	v_addc_u32 v[vreg_out_addr+1], vcc, v[vreg_out_addr+1], 0, vcc
	flat_store_dword v[vreg_out_addr:vreg_out_addr+1], v[vreg_oval+2]
	s_cmpk_ge_u32 s[sreg_dy], 0+out_h-3
	s_cbranch_scc1 skip_write0
	v_add_u32  v[vreg_out_addr], vcc, 0+out_stride_y, v[vreg_out_addr]
	v_addc_u32 v[vreg_out_addr+1], vcc, v[vreg_out_addr+1], 0, vcc
	flat_store_dword v[vreg_out_addr:vreg_out_addr+1], v[vreg_oval+3]
skip_write0:
	s_cmpk_ge_u32 s[sreg_k], -1+wei_k
	s_cbranch_scc1 skip_write1
	v_add_u32  v[vreg_out_addr], vcc, 0+out_stride_k, v[vreg_ival]
	v_addc_u32 v[vreg_out_addr+1], vcc, v[vreg_ival+1], 0, vcc
	flat_store_dword v[vreg_out_addr:vreg_out_addr+1], v[vreg_oval+4]
	s_cmpk_ge_u32 s[sreg_dy], 0+out_h-1
	s_cbranch_scc1 skip_write1
	v_add_u32  v[vreg_out_addr], vcc, 0+out_stride_y, v[vreg_out_addr]
	v_addc_u32 v[vreg_out_addr+1], vcc, v[vreg_out_addr+1], 0, vcc
	flat_store_dword v[vreg_out_addr:vreg_out_addr+1], v[vreg_oval+5]
	s_cmpk_ge_u32 s[sreg_dy], 0+out_h-2
	s_cbranch_scc1 skip_write1
	v_add_u32  v[vreg_out_addr], vcc, 0+out_stride_y, v[vreg_out_addr]
	v_addc_u32 v[vreg_out_addr+1], vcc, v[vreg_out_addr+1], 0, vcc
	flat_store_dword v[vreg_out_addr:vreg_out_addr+1], v[vreg_oval+6]
	s_cmpk_ge_u32 s[sreg_dy], 0+out_h-3
	s_cbranch_scc1 skip_write1
	v_add_u32  v[vreg_out_addr], vcc, 0+out_stride_y, v[vreg_out_addr]
	v_addc_u32 v[vreg_out_addr+1], vcc, v[vreg_out_addr+1], 0, vcc
	flat_store_dword v[vreg_out_addr:vreg_out_addr+1], v[vreg_oval+7]
skip_write1:
	s_endpgm

///////////////////////////////////////////////////
// ******* meta-data section of the kernels
///////////////////////////////////////////////////
.section .note
.ifdef ROCM_METADATA_V2
.amdgpu_runtime_metadata
{ amd.MDVersion: [ 2, 1 ],
    amd.Kernels:
    - { amd.KernelName: conv5x10uv2fwd, amd.Language: OpenCL C, amd.LanguageVersion: [ 1, 2 ],
        # FIXME amd.ReqdWorkGroupSize: [ 64, 8, 1 ], 
        amd.Args:
        - { amd.ArgSize: 8, amd.ArgAlign: 8, amd.ArgKind: 1, amd.ArgValueType: 8, amd.ArgTypeName: 'float*', amd.ArgName: in,          amd.ArgAddrQual: 1, amd.ArgAccQual: 0, amd.ArgIsConst: 1 }
        - { amd.ArgSize: 8, amd.ArgAlign: 8, amd.ArgKind: 1, amd.ArgValueType: 8, amd.ArgTypeName: 'float*', amd.ArgName: weights,     amd.ArgAddrQual: 1, amd.ArgAccQual: 0, amd.ArgIsConst: 1 }
        - { amd.ArgSize: 8, amd.ArgAlign: 8, amd.ArgKind: 1, amd.ArgValueType: 8, amd.ArgTypeName: 'float*', amd.ArgName: out,         amd.ArgAddrQual: 1, amd.ArgAccQual: 0 }
        - { amd.ArgSize: 4, amd.ArgAlign: 4, amd.ArgKind: 0, amd.ArgValueType: 8, amd.ArgTypeName:  float,   amd.ArgName: padding_val,                     amd.ArgAccQual: 0 }
      }
}
.end_amdgpu_runtime_metadata
.else
	// old ROCm metadata
	.long 4
	.long .Lmeta_end - .Lmeta_begin
	.long 7
	.asciz "AMD"
	.p2align 2
	.Lmeta_begin:
	.long  0x02010001, 0x00780300
	.short 0x0604, 14, 0
	.ascii "conv5x10uv2fwd"
	.long  0x00080907, 0x080a0000, 0x0b000000, 0x00000006
	.long  0x616f6c66, 0x030c2a74, 0x69000000, 0x010d706e
	.long  0x1000080e, 0x08010f00, 0x00080907, 0x080a0000
	.long  0x0b000000, 0x00000006, 0x616f6c66, 0x070c2a74
	.long  0x77000000, 0x68676965, 0x010d7374, 0x1000080e
	.long  0x08010f00, 0x00080907, 0x080a0000, 0x0b000000
	.long  0x00000006, 0x616f6c66, 0x030c2a74, 0x6f000000
	.long  0x010d7475, 0x1000080e, 0x08010f00, 0x00040907
	.long  0x040a0000, 0x0b000000, 0x00000005, 0x616f6c66
	.long  0x000b0c74, 0x61700000, 0x6e696464, 0x61765f67
	.long  0x0e000d6c, 0x00100008, 0x08090708, 0x0a000000
	.long  0x00000008, 0x090e070d, 0x09070800, 0x00000008
	.long  0x0000080a, 0x0e080d00, 0x07080009, 0x00000809
	.long  0x00080a00, 0x090d0000, 0x0800090e, 0x00004015
	.long  0x00000800, 0x00000100, 0x00000500
	.Lmeta_end:
	.p2align 2
.endif
