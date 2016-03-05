// DNBRegisterInfoX86_64.cpp is based on DNBArchImplX86_64.cpp,
// DNBArchImplX86_64.h and MachRegisterStatesX86_64.h.
//
//===-- DNBArchImplX86_64.cpp -----------------------------------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
//  Created by Greg Clayton on 6/25/07.
//
//===----------------------------------------------------------------------===//

#if defined (__x86_64__)

#include <sys/cdefs.h>
#include <sys/types.h>
#include <sys/sysctl.h>

#include "DNBRegisterInfoX86_64.h"
#include "HasAVX.h"
#include <mach/mach.h>
#include <stdlib.h>
#include <stddef.h>
#include <assert.h>

extern "C" bool
CPUHasAVX() {
    enum AVXPresence
    {
        eAVXUnknown     = -1,
        eAVXNotPresent  =  0,
        eAVXPresent     =  1
    };

    static AVXPresence g_has_avx = eAVXUnknown;
    if (g_has_avx == eAVXUnknown)
    {
        g_has_avx = eAVXNotPresent;

        // Only xnu-2020 or later has AVX support, any versions before
        // this have a busted thread_get_state RPC where it would truncate
        // the thread state buffer (<rdar://problem/10122874>). So we need to
        // verify the kernel version number manually or disable AVX support.
        int mib[2];
        char buffer[1024];
        size_t length = sizeof(buffer);
        uint64_t xnu_version = 0;
        mib[0] = CTL_KERN;
        mib[1] = KERN_VERSION;
        int err = ::sysctl(mib, 2, &buffer, &length, NULL, 0);
        if (err == 0)
        {
            const char *xnu = strstr (buffer, "xnu-");
            if (xnu)
            {
                const char *xnu_version_cstr = xnu + 4;
                xnu_version = strtoull (xnu_version_cstr, NULL, 0);
                if (xnu_version >= 2020 && xnu_version != ULLONG_MAX)
                {
                    if (::HasAVX())
                    {
                        g_has_avx = eAVXPresent;
                    }
                }
            }
        }
    }

    return (g_has_avx == eAVXPresent);
}

#define __x86_64_THREAD_STATE       4
#define __x86_64_FLOAT_STATE        5
#define __x86_64_EXCEPTION_STATE    6
#define __x86_64_DEBUG_STATE        11
#define __x86_64_AVX_STATE          17

typedef struct {
    uint64_t    __rax;
    uint64_t    __rbx;
    uint64_t    __rcx;
    uint64_t    __rdx;
    uint64_t    __rdi;
    uint64_t    __rsi;
    uint64_t    __rbp;
    uint64_t    __rsp;
    uint64_t    __r8;
    uint64_t    __r9;
    uint64_t    __r10;
    uint64_t    __r11;
    uint64_t    __r12;
    uint64_t    __r13;
    uint64_t    __r14;
    uint64_t    __r15;
    uint64_t    __rip;
    uint64_t    __rflags;
    uint64_t    __cs;
    uint64_t    __fs;
    uint64_t    __gs;
} __x86_64_thread_state_t;

typedef struct {
    uint16_t    __invalid   : 1;
    uint16_t    __denorm    : 1;
    uint16_t    __zdiv      : 1;
    uint16_t    __ovrfl     : 1;
    uint16_t    __undfl     : 1;
    uint16_t    __precis    : 1;
    uint16_t    __PAD1      : 2;
    uint16_t    __pc        : 2;
    uint16_t    __rc        : 2;
    uint16_t    __PAD2      : 1;
    uint16_t    __PAD3      : 3;
} __x86_64_fp_control_t;

typedef struct {
    uint16_t    __invalid   : 1;
    uint16_t    __denorm    : 1;
    uint16_t    __zdiv      : 1;
    uint16_t    __ovrfl     : 1;
    uint16_t    __undfl     : 1;
    uint16_t    __precis    : 1;
    uint16_t    __stkflt    : 1;
    uint16_t    __errsumm   : 1;
    uint16_t    __c0        : 1;
    uint16_t    __c1        : 1;
    uint16_t    __c2        : 1;
    uint16_t    __tos       : 3;
    uint16_t    __c3        : 1;
    uint16_t    __busy      : 1;
} __x86_64_fp_status_t;

typedef struct {
    uint8_t     __mmst_reg[10];
    uint8_t     __mmst_rsrv[6];
} __x86_64_mmst_reg;

typedef struct {
    uint8_t     __xmm_reg[16];
} __x86_64_xmm_reg;

typedef struct {
    int32_t                 __fpu_reserved[2];
    __x86_64_fp_control_t   __fpu_fcw;
    __x86_64_fp_status_t    __fpu_fsw;
    uint8_t                 __fpu_ftw;
    uint8_t                 __fpu_rsrv1;
    uint16_t                __fpu_fop;
    uint32_t                __fpu_ip;
    uint16_t                __fpu_cs;
    uint16_t                __fpu_rsrv2;
    uint32_t                __fpu_dp;
    uint16_t                __fpu_ds;
    uint16_t                __fpu_rsrv3;
    uint32_t                __fpu_mxcsr;
    uint32_t                __fpu_mxcsrmask;
    __x86_64_mmst_reg       __fpu_stmm0;
    __x86_64_mmst_reg       __fpu_stmm1;
    __x86_64_mmst_reg       __fpu_stmm2;
    __x86_64_mmst_reg       __fpu_stmm3;
    __x86_64_mmst_reg       __fpu_stmm4;
    __x86_64_mmst_reg       __fpu_stmm5;
    __x86_64_mmst_reg       __fpu_stmm6;
    __x86_64_mmst_reg       __fpu_stmm7;
    __x86_64_xmm_reg        __fpu_xmm0;
    __x86_64_xmm_reg        __fpu_xmm1;
    __x86_64_xmm_reg        __fpu_xmm2;
    __x86_64_xmm_reg        __fpu_xmm3;
    __x86_64_xmm_reg        __fpu_xmm4;
    __x86_64_xmm_reg        __fpu_xmm5;
    __x86_64_xmm_reg        __fpu_xmm6;
    __x86_64_xmm_reg        __fpu_xmm7;
    __x86_64_xmm_reg        __fpu_xmm8;
    __x86_64_xmm_reg        __fpu_xmm9;
    __x86_64_xmm_reg        __fpu_xmm10;
    __x86_64_xmm_reg        __fpu_xmm11;
    __x86_64_xmm_reg        __fpu_xmm12;
    __x86_64_xmm_reg        __fpu_xmm13;
    __x86_64_xmm_reg        __fpu_xmm14;
    __x86_64_xmm_reg        __fpu_xmm15;
    uint8_t                 __fpu_rsrv4[6*16];
    int32_t                 __fpu_reserved1;
} __x86_64_float_state_t;

typedef struct {
    uint32_t                __fpu_reserved[2];
    __x86_64_fp_control_t   __fpu_fcw;
    __x86_64_fp_status_t    __fpu_fsw;
    uint8_t                 __fpu_ftw;
    uint8_t                 __fpu_rsrv1;
    uint16_t                __fpu_fop;
    uint32_t                __fpu_ip;
    uint16_t                __fpu_cs;
    uint16_t                __fpu_rsrv2;
    uint32_t                __fpu_dp;
    uint16_t                __fpu_ds;
    uint16_t                __fpu_rsrv3;
    uint32_t                __fpu_mxcsr;
    uint32_t                __fpu_mxcsrmask;
    __x86_64_mmst_reg       __fpu_stmm0;
    __x86_64_mmst_reg       __fpu_stmm1;
    __x86_64_mmst_reg       __fpu_stmm2;
    __x86_64_mmst_reg       __fpu_stmm3;
    __x86_64_mmst_reg       __fpu_stmm4;
    __x86_64_mmst_reg       __fpu_stmm5;
    __x86_64_mmst_reg       __fpu_stmm6;
    __x86_64_mmst_reg       __fpu_stmm7;
    __x86_64_xmm_reg        __fpu_xmm0;
    __x86_64_xmm_reg        __fpu_xmm1;
    __x86_64_xmm_reg        __fpu_xmm2;
    __x86_64_xmm_reg        __fpu_xmm3;
    __x86_64_xmm_reg        __fpu_xmm4;
    __x86_64_xmm_reg        __fpu_xmm5;
    __x86_64_xmm_reg        __fpu_xmm6;
    __x86_64_xmm_reg        __fpu_xmm7;
    __x86_64_xmm_reg        __fpu_xmm8;
    __x86_64_xmm_reg        __fpu_xmm9;
    __x86_64_xmm_reg        __fpu_xmm10;
    __x86_64_xmm_reg        __fpu_xmm11;
    __x86_64_xmm_reg        __fpu_xmm12;
    __x86_64_xmm_reg        __fpu_xmm13;
    __x86_64_xmm_reg        __fpu_xmm14;
    __x86_64_xmm_reg        __fpu_xmm15;
    uint8_t                 __fpu_rsrv4[6*16];
    uint32_t                __fpu_reserved1;
    uint8_t                 __avx_reserved1[64];
    __x86_64_xmm_reg        __fpu_ymmh0;
    __x86_64_xmm_reg        __fpu_ymmh1;
    __x86_64_xmm_reg        __fpu_ymmh2;
    __x86_64_xmm_reg        __fpu_ymmh3;
    __x86_64_xmm_reg        __fpu_ymmh4;
    __x86_64_xmm_reg        __fpu_ymmh5;
    __x86_64_xmm_reg        __fpu_ymmh6;
    __x86_64_xmm_reg        __fpu_ymmh7;
    __x86_64_xmm_reg        __fpu_ymmh8;
    __x86_64_xmm_reg        __fpu_ymmh9;
    __x86_64_xmm_reg        __fpu_ymmh10;
    __x86_64_xmm_reg        __fpu_ymmh11;
    __x86_64_xmm_reg        __fpu_ymmh12;
    __x86_64_xmm_reg        __fpu_ymmh13;
    __x86_64_xmm_reg        __fpu_ymmh14;
    __x86_64_xmm_reg        __fpu_ymmh15;
} __x86_64_avx_state_t;

typedef struct {
    uint32_t    __trapno;
    uint32_t    __err;
    uint64_t    __faultvaddr;
} __x86_64_exception_state_t;


typedef struct {
    uint64_t	__dr0;
    uint64_t	__dr1;
    uint64_t	__dr2;
    uint64_t	__dr3;
    uint64_t	__dr4;
    uint64_t	__dr5;
    uint64_t	__dr6;
    uint64_t	__dr7;
} __x86_64_debug_state_t;

class DNBArchImplX86_64 {
public:
    typedef __x86_64_thread_state_t GPR;
    typedef __x86_64_float_state_t FPU;
    typedef __x86_64_exception_state_t EXC;
    typedef __x86_64_avx_state_t AVX;
    typedef __x86_64_debug_state_t DBG;
    
    static const DNBRegisterInfo g_gpr_registers[];
    static const DNBRegisterInfo g_fpu_registers_no_avx[];
    static const DNBRegisterInfo g_fpu_registers_avx[];
    static const DNBRegisterInfo g_exc_registers[];
    static const DNBRegisterSetInfo g_reg_sets_no_avx[];
    static const DNBRegisterSetInfo g_reg_sets_avx[];
    static const size_t k_num_gpr_registers;
    static const size_t k_num_fpu_registers_no_avx;
    static const size_t k_num_fpu_registers_avx;
    static const size_t k_num_exc_registers;
    static const size_t k_num_all_registers_no_avx;
    static const size_t k_num_all_registers_avx;
    static const size_t k_num_register_sets;

    typedef enum RegisterSetTag
    {
        e_regSetALL = REGISTER_SET_ALL,
        e_regSetGPR,
        e_regSetFPU,
        e_regSetEXC,
        e_regSetDBG,
        kNumRegisterSets
    } RegisterSet;
    
    typedef enum RegisterSetWordSizeTag
    {
        e_regSetWordSizeGPR = sizeof(GPR) / sizeof(int),
        e_regSetWordSizeFPU = sizeof(FPU) / sizeof(int),
        e_regSetWordSizeEXC = sizeof(EXC) / sizeof(int),
        e_regSetWordSizeAVX = sizeof(AVX) / sizeof(int),
        e_regSetWordSizeDBG = sizeof(DBG) / sizeof(int)
    } RegisterSetWordSize;

    struct Context
    {
        GPR gpr;
        union {
            FPU no_avx;
            AVX avx;
        } fpu;
        EXC exc;
        DBG dbg;
    };

    static const DNBRegisterSetInfo *
    GetRegisterSetInfo(nub_size_t *num_reg_sets);
};

//----------------------------------------------------------------------
// Register information definitions
//----------------------------------------------------------------------

enum
{
    gpr_rax = 0,
    gpr_rbx,
    gpr_rcx,
    gpr_rdx,
    gpr_rdi,
    gpr_rsi,
    gpr_rbp,
    gpr_rsp,
    gpr_r8,
    gpr_r9,
    gpr_r10,
    gpr_r11,
    gpr_r12,
    gpr_r13,
    gpr_r14,
    gpr_r15,
    gpr_rip,
    gpr_rflags,
    gpr_cs,
    gpr_fs,
    gpr_gs,
    gpr_eax,
    gpr_ebx,
    gpr_ecx,
    gpr_edx,
    gpr_edi,
    gpr_esi,
    gpr_ebp,
    gpr_esp,
    gpr_r8d,    // Low 32 bits or r8
    gpr_r9d,    // Low 32 bits or r9
    gpr_r10d,   // Low 32 bits or r10
    gpr_r11d,   // Low 32 bits or r11
    gpr_r12d,   // Low 32 bits or r12
    gpr_r13d,   // Low 32 bits or r13
    gpr_r14d,   // Low 32 bits or r14
    gpr_r15d,   // Low 32 bits or r15
    gpr_ax ,
    gpr_bx ,
    gpr_cx ,
    gpr_dx ,
    gpr_di ,
    gpr_si ,
    gpr_bp ,
    gpr_sp ,
    gpr_r8w,    // Low 16 bits or r8
    gpr_r9w,    // Low 16 bits or r9
    gpr_r10w,   // Low 16 bits or r10
    gpr_r11w,   // Low 16 bits or r11
    gpr_r12w,   // Low 16 bits or r12
    gpr_r13w,   // Low 16 bits or r13
    gpr_r14w,   // Low 16 bits or r14
    gpr_r15w,   // Low 16 bits or r15
    gpr_ah ,
    gpr_bh ,
    gpr_ch ,
    gpr_dh ,
    gpr_al ,
    gpr_bl ,
    gpr_cl ,
    gpr_dl ,
    gpr_dil,
    gpr_sil,
    gpr_bpl,
    gpr_spl,
    gpr_r8l,    // Low 8 bits or r8
    gpr_r9l,    // Low 8 bits or r9
    gpr_r10l,   // Low 8 bits or r10
    gpr_r11l,   // Low 8 bits or r11
    gpr_r12l,   // Low 8 bits or r12
    gpr_r13l,   // Low 8 bits or r13
    gpr_r14l,   // Low 8 bits or r14
    gpr_r15l,   // Low 8 bits or r15
    k_num_gpr_regs
};

enum {
    fpu_fcw,
    fpu_fsw,
    fpu_ftw,
    fpu_fop,
    fpu_ip,
    fpu_cs,
    fpu_dp,
    fpu_ds,
    fpu_mxcsr,
    fpu_mxcsrmask,
    fpu_stmm0,
    fpu_stmm1,
    fpu_stmm2,
    fpu_stmm3,
    fpu_stmm4,
    fpu_stmm5,
    fpu_stmm6,
    fpu_stmm7,
    fpu_xmm0,
    fpu_xmm1,
    fpu_xmm2,
    fpu_xmm3,
    fpu_xmm4,
    fpu_xmm5,
    fpu_xmm6,
    fpu_xmm7,
    fpu_xmm8,
    fpu_xmm9,
    fpu_xmm10,
    fpu_xmm11,
    fpu_xmm12,
    fpu_xmm13,
    fpu_xmm14,
    fpu_xmm15,
    fpu_ymm0,
    fpu_ymm1,
    fpu_ymm2,
    fpu_ymm3,
    fpu_ymm4,
    fpu_ymm5,
    fpu_ymm6,
    fpu_ymm7,
    fpu_ymm8,
    fpu_ymm9,
    fpu_ymm10,
    fpu_ymm11,
    fpu_ymm12,
    fpu_ymm13,
    fpu_ymm14,
    fpu_ymm15,
    k_num_fpu_regs,
    
    // Aliases
    fpu_fctrl = fpu_fcw,
    fpu_fstat = fpu_fsw,
    fpu_ftag  = fpu_ftw,
    fpu_fiseg = fpu_cs,
    fpu_fioff = fpu_ip,
    fpu_foseg = fpu_ds,
    fpu_fooff = fpu_dp
};

enum {
    exc_trapno,
    exc_err,
    exc_faultvaddr,
    k_num_exc_regs,
};


enum ehframe_dwarf_regnums
{
    ehframe_dwarf_rax = 0,
    ehframe_dwarf_rdx = 1,
    ehframe_dwarf_rcx = 2,
    ehframe_dwarf_rbx = 3,
    ehframe_dwarf_rsi = 4,
    ehframe_dwarf_rdi = 5,
    ehframe_dwarf_rbp = 6,
    ehframe_dwarf_rsp = 7,
    ehframe_dwarf_r8,
    ehframe_dwarf_r9,
    ehframe_dwarf_r10,
    ehframe_dwarf_r11,
    ehframe_dwarf_r12,
    ehframe_dwarf_r13,
    ehframe_dwarf_r14,
    ehframe_dwarf_r15,
    ehframe_dwarf_rip,
    ehframe_dwarf_xmm0,
    ehframe_dwarf_xmm1,
    ehframe_dwarf_xmm2,
    ehframe_dwarf_xmm3,
    ehframe_dwarf_xmm4,
    ehframe_dwarf_xmm5,
    ehframe_dwarf_xmm6,
    ehframe_dwarf_xmm7,
    ehframe_dwarf_xmm8,
    ehframe_dwarf_xmm9,
    ehframe_dwarf_xmm10,
    ehframe_dwarf_xmm11,
    ehframe_dwarf_xmm12,
    ehframe_dwarf_xmm13,
    ehframe_dwarf_xmm14,
    ehframe_dwarf_xmm15,
    ehframe_dwarf_stmm0,
    ehframe_dwarf_stmm1,
    ehframe_dwarf_stmm2,
    ehframe_dwarf_stmm3,
    ehframe_dwarf_stmm4,
    ehframe_dwarf_stmm5,
    ehframe_dwarf_stmm6,
    ehframe_dwarf_stmm7,
    ehframe_dwarf_ymm0 = ehframe_dwarf_xmm0,
    ehframe_dwarf_ymm1 = ehframe_dwarf_xmm1,
    ehframe_dwarf_ymm2 = ehframe_dwarf_xmm2,
    ehframe_dwarf_ymm3 = ehframe_dwarf_xmm3,
    ehframe_dwarf_ymm4 = ehframe_dwarf_xmm4,
    ehframe_dwarf_ymm5 = ehframe_dwarf_xmm5,
    ehframe_dwarf_ymm6 = ehframe_dwarf_xmm6,
    ehframe_dwarf_ymm7 = ehframe_dwarf_xmm7,
    ehframe_dwarf_ymm8 = ehframe_dwarf_xmm8,
    ehframe_dwarf_ymm9 = ehframe_dwarf_xmm9,
    ehframe_dwarf_ymm10 = ehframe_dwarf_xmm10,
    ehframe_dwarf_ymm11 = ehframe_dwarf_xmm11,
    ehframe_dwarf_ymm12 = ehframe_dwarf_xmm12,
    ehframe_dwarf_ymm13 = ehframe_dwarf_xmm13,
    ehframe_dwarf_ymm14 = ehframe_dwarf_xmm14,
    ehframe_dwarf_ymm15 = ehframe_dwarf_xmm15
};

enum debugserver_regnums
{
    debugserver_rax     =   0,
    debugserver_rbx     =   1,
    debugserver_rcx     =   2,
    debugserver_rdx     =   3,
    debugserver_rsi     =   4,
    debugserver_rdi     =   5,
    debugserver_rbp     =   6,
    debugserver_rsp     =   7,
    debugserver_r8      =   8,
    debugserver_r9      =   9,
    debugserver_r10     =  10,
    debugserver_r11     =  11,
    debugserver_r12     =  12,
    debugserver_r13     =  13,
    debugserver_r14     =  14,
    debugserver_r15     =  15,
    debugserver_rip     =  16,
    debugserver_rflags  =  17,
    debugserver_cs      =  18,
    debugserver_ss      =  19,
    debugserver_ds      =  20,
    debugserver_es      =  21,
    debugserver_fs      =  22,
    debugserver_gs      =  23,
    debugserver_stmm0   =  24,
    debugserver_stmm1   =  25,
    debugserver_stmm2   =  26,
    debugserver_stmm3   =  27,
    debugserver_stmm4   =  28,
    debugserver_stmm5   =  29,
    debugserver_stmm6   =  30,
    debugserver_stmm7   =  31,
    debugserver_fctrl   =  32,  debugserver_fcw = debugserver_fctrl,
    debugserver_fstat   =  33,  debugserver_fsw = debugserver_fstat,
    debugserver_ftag    =  34,  debugserver_ftw = debugserver_ftag,
    debugserver_fiseg   =  35,  debugserver_fpu_cs  = debugserver_fiseg,
    debugserver_fioff   =  36,  debugserver_ip  = debugserver_fioff,
    debugserver_foseg   =  37,  debugserver_fpu_ds  = debugserver_foseg,
    debugserver_fooff   =  38,  debugserver_dp  = debugserver_fooff,
    debugserver_fop     =  39,
    debugserver_xmm0    =  40,
    debugserver_xmm1    =  41,
    debugserver_xmm2    =  42,
    debugserver_xmm3    =  43,
    debugserver_xmm4    =  44,
    debugserver_xmm5    =  45,
    debugserver_xmm6    =  46,
    debugserver_xmm7    =  47,
    debugserver_xmm8    =  48,
    debugserver_xmm9    =  49,
    debugserver_xmm10   =  50,
    debugserver_xmm11   =  51,
    debugserver_xmm12   =  52,
    debugserver_xmm13   =  53,
    debugserver_xmm14   =  54,
    debugserver_xmm15   =  55,
    debugserver_mxcsr   =  56,
    debugserver_ymm0    =  debugserver_xmm0,
    debugserver_ymm1    =  debugserver_xmm1,
    debugserver_ymm2    =  debugserver_xmm2,
    debugserver_ymm3    =  debugserver_xmm3,
    debugserver_ymm4    =  debugserver_xmm4,
    debugserver_ymm5    =  debugserver_xmm5,
    debugserver_ymm6    =  debugserver_xmm6,
    debugserver_ymm7    =  debugserver_xmm7,
    debugserver_ymm8    =  debugserver_xmm8,
    debugserver_ymm9    =  debugserver_xmm9,
    debugserver_ymm10   =  debugserver_xmm10,
    debugserver_ymm11   =  debugserver_xmm11,
    debugserver_ymm12   =  debugserver_xmm12,
    debugserver_ymm13   =  debugserver_xmm13,
    debugserver_ymm14   =  debugserver_xmm14,
    debugserver_ymm15   =  debugserver_xmm15
};

#define GPR_OFFSET(reg) (offsetof (DNBArchImplX86_64::GPR, __##reg))
#define FPU_OFFSET(reg) (offsetof (DNBArchImplX86_64::FPU, __fpu_##reg) + offsetof (DNBArchImplX86_64::Context, fpu.no_avx))
#define AVX_OFFSET(reg) (offsetof (DNBArchImplX86_64::AVX, __fpu_##reg) + offsetof (DNBArchImplX86_64::Context, fpu.avx))
#define EXC_OFFSET(reg) (offsetof (DNBArchImplX86_64::EXC, __##reg)     + offsetof (DNBArchImplX86_64::Context, exc))
#define AVX_OFFSET_YMM(n)   (AVX_OFFSET(ymmh0) + (32 * n))

#define GPR_SIZE(reg)       (sizeof(((DNBArchImplX86_64::GPR *)NULL)->__##reg))
#define FPU_SIZE_UINT(reg)  (sizeof(((DNBArchImplX86_64::FPU *)NULL)->__fpu_##reg))
#define FPU_SIZE_MMST(reg)  (sizeof(((DNBArchImplX86_64::FPU *)NULL)->__fpu_##reg.__mmst_reg))
#define FPU_SIZE_XMM(reg)   (sizeof(((DNBArchImplX86_64::FPU *)NULL)->__fpu_##reg.__xmm_reg))
#define FPU_SIZE_YMM(reg)   (32)
#define EXC_SIZE(reg)       (sizeof(((DNBArchImplX86_64::EXC *)NULL)->__##reg))

// These macros will auto define the register name, alt name, register size,
// register offset, encoding, format and native register. This ensures that
// the register state structures are defined correctly and have the correct
// sizes and offsets.
#define DEFINE_GPR(reg)                   { e_regSetGPR, gpr_##reg, #reg, NULL, Uint, Hex, GPR_SIZE(reg), GPR_OFFSET(reg), ehframe_dwarf_##reg, ehframe_dwarf_##reg, INVALID_NUB_REGNUM, debugserver_##reg, NULL, g_invalidate_##reg }
#define DEFINE_GPR_ALT(reg, alt, gen)     { e_regSetGPR, gpr_##reg, #reg, alt, Uint, Hex, GPR_SIZE(reg), GPR_OFFSET(reg), ehframe_dwarf_##reg, ehframe_dwarf_##reg, gen, debugserver_##reg, NULL, g_invalidate_##reg }
#define DEFINE_GPR_ALT2(reg, alt)         { e_regSetGPR, gpr_##reg, #reg, alt, Uint, Hex, GPR_SIZE(reg), GPR_OFFSET(reg), INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, debugserver_##reg, NULL, NULL }
#define DEFINE_GPR_ALT3(reg, alt, gen)    { e_regSetGPR, gpr_##reg, #reg, alt, Uint, Hex, GPR_SIZE(reg), GPR_OFFSET(reg), INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, gen, debugserver_##reg, NULL, NULL }
#define DEFINE_GPR_ALT4(reg, alt, gen)     { e_regSetGPR, gpr_##reg, #reg, alt, Uint, Hex, GPR_SIZE(reg), GPR_OFFSET(reg), ehframe_dwarf_##reg, ehframe_dwarf_##reg, gen, debugserver_##reg, NULL, NULL }

#define DEFINE_GPR_PSEUDO_32(reg32,reg64) { e_regSetGPR, gpr_##reg32, #reg32, NULL, Uint, Hex, 4, 0,INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, g_contained_##reg64, g_invalidate_##reg64 }
#define DEFINE_GPR_PSEUDO_16(reg16,reg64) { e_regSetGPR, gpr_##reg16, #reg16, NULL, Uint, Hex, 2, 0,INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, g_contained_##reg64, g_invalidate_##reg64 }
#define DEFINE_GPR_PSEUDO_8H(reg8,reg64)  { e_regSetGPR, gpr_##reg8 , #reg8 , NULL, Uint, Hex, 1, 1,INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, g_contained_##reg64, g_invalidate_##reg64 }
#define DEFINE_GPR_PSEUDO_8L(reg8,reg64)  { e_regSetGPR, gpr_##reg8 , #reg8 , NULL, Uint, Hex, 1, 0,INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, INVALID_NUB_REGNUM, g_contained_##reg64, g_invalidate_##reg64 }

// General purpose registers for 64 bit

const char *g_contained_rax[] = { "rax", NULL };
const char *g_contained_rbx[] = { "rbx", NULL };
const char *g_contained_rcx[] = { "rcx", NULL };
const char *g_contained_rdx[] = { "rdx", NULL };
const char *g_contained_rdi[] = { "rdi", NULL };
const char *g_contained_rsi[] = { "rsi", NULL };
const char *g_contained_rbp[] = { "rbp", NULL };
const char *g_contained_rsp[] = { "rsp", NULL };
const char *g_contained_r8[]  = { "r8",  NULL };
const char *g_contained_r9[]  = { "r9",  NULL };
const char *g_contained_r10[] = { "r10", NULL };
const char *g_contained_r11[] = { "r11", NULL };
const char *g_contained_r12[] = { "r12", NULL };
const char *g_contained_r13[] = { "r13", NULL };
const char *g_contained_r14[] = { "r14", NULL };
const char *g_contained_r15[] = { "r15", NULL };

const char *g_invalidate_rax[] = { "rax",  "eax",   "ax",   "ah", "al", NULL };
const char *g_invalidate_rbx[] = { "rbx",  "ebx",   "bx",   "bh", "bl", NULL };
const char *g_invalidate_rcx[] = { "rcx",  "ecx",   "cx",   "ch", "cl", NULL };
const char *g_invalidate_rdx[] = { "rdx",  "edx",   "dx",   "dh", "dl", NULL };
const char *g_invalidate_rdi[] = { "rdi",  "edi",   "di",  "dil",       NULL };
const char *g_invalidate_rsi[] = { "rsi",  "esi",   "si",  "sil",       NULL };
const char *g_invalidate_rbp[] = { "rbp",  "ebp",   "bp",  "bpl",       NULL };
const char *g_invalidate_rsp[] = { "rsp",  "esp",   "sp",  "spl",       NULL };
const char *g_invalidate_r8 [] = {  "r8",  "r8d",  "r8w",  "r8l",       NULL };
const char *g_invalidate_r9 [] = {  "r9",  "r9d",  "r9w",  "r9l",       NULL };
const char *g_invalidate_r10[] = { "r10", "r10d", "r10w", "r10l",       NULL };
const char *g_invalidate_r11[] = { "r11", "r11d", "r11w", "r11l",       NULL };
const char *g_invalidate_r12[] = { "r12", "r12d", "r12w", "r12l",       NULL };
const char *g_invalidate_r13[] = { "r13", "r13d", "r13w", "r13l",       NULL };
const char *g_invalidate_r14[] = { "r14", "r14d", "r14w", "r14l",       NULL };
const char *g_invalidate_r15[] = { "r15", "r15d", "r15w", "r15l",       NULL };

const DNBRegisterInfo
DNBArchImplX86_64::g_gpr_registers[] =
{
    DEFINE_GPR      (rax),
    DEFINE_GPR      (rbx),
    DEFINE_GPR_ALT  (rcx , "arg4", GENERIC_REGNUM_ARG4),
    DEFINE_GPR_ALT  (rdx , "arg3", GENERIC_REGNUM_ARG3),
    DEFINE_GPR_ALT  (rdi , "arg1", GENERIC_REGNUM_ARG1),
    DEFINE_GPR_ALT  (rsi , "arg2", GENERIC_REGNUM_ARG2),
    DEFINE_GPR_ALT  (rbp , "fp"  , GENERIC_REGNUM_FP),
    DEFINE_GPR_ALT  (rsp , "sp"  , GENERIC_REGNUM_SP),
    DEFINE_GPR_ALT  (r8  , "arg5", GENERIC_REGNUM_ARG5),
    DEFINE_GPR_ALT  (r9  , "arg6", GENERIC_REGNUM_ARG6),
    DEFINE_GPR      (r10),
    DEFINE_GPR      (r11),
    DEFINE_GPR      (r12),
    DEFINE_GPR      (r13),
    DEFINE_GPR      (r14),
    DEFINE_GPR      (r15),
    DEFINE_GPR_ALT4 (rip , "pc", GENERIC_REGNUM_PC),
    DEFINE_GPR_ALT3 (rflags, "flags", GENERIC_REGNUM_FLAGS),
    DEFINE_GPR_ALT2 (cs,        NULL),
    DEFINE_GPR_ALT2 (fs,        NULL),
    DEFINE_GPR_ALT2 (gs,        NULL),
    DEFINE_GPR_PSEUDO_32 (eax, rax),
    DEFINE_GPR_PSEUDO_32 (ebx, rbx),
    DEFINE_GPR_PSEUDO_32 (ecx, rcx),
    DEFINE_GPR_PSEUDO_32 (edx, rdx),
    DEFINE_GPR_PSEUDO_32 (edi, rdi),
    DEFINE_GPR_PSEUDO_32 (esi, rsi),
    DEFINE_GPR_PSEUDO_32 (ebp, rbp),
    DEFINE_GPR_PSEUDO_32 (esp, rsp),
    DEFINE_GPR_PSEUDO_32 (r8d, r8),
    DEFINE_GPR_PSEUDO_32 (r9d, r9),
    DEFINE_GPR_PSEUDO_32 (r10d, r10),
    DEFINE_GPR_PSEUDO_32 (r11d, r11),
    DEFINE_GPR_PSEUDO_32 (r12d, r12),
    DEFINE_GPR_PSEUDO_32 (r13d, r13),
    DEFINE_GPR_PSEUDO_32 (r14d, r14),
    DEFINE_GPR_PSEUDO_32 (r15d, r15),
    DEFINE_GPR_PSEUDO_16 (ax , rax),
    DEFINE_GPR_PSEUDO_16 (bx , rbx),
    DEFINE_GPR_PSEUDO_16 (cx , rcx),
    DEFINE_GPR_PSEUDO_16 (dx , rdx),
    DEFINE_GPR_PSEUDO_16 (di , rdi),
    DEFINE_GPR_PSEUDO_16 (si , rsi),
    DEFINE_GPR_PSEUDO_16 (bp , rbp),
    DEFINE_GPR_PSEUDO_16 (sp , rsp),
    DEFINE_GPR_PSEUDO_16 (r8w, r8),
    DEFINE_GPR_PSEUDO_16 (r9w, r9),
    DEFINE_GPR_PSEUDO_16 (r10w, r10),
    DEFINE_GPR_PSEUDO_16 (r11w, r11),
    DEFINE_GPR_PSEUDO_16 (r12w, r12),
    DEFINE_GPR_PSEUDO_16 (r13w, r13),
    DEFINE_GPR_PSEUDO_16 (r14w, r14),
    DEFINE_GPR_PSEUDO_16 (r15w, r15),
    DEFINE_GPR_PSEUDO_8H (ah , rax),
    DEFINE_GPR_PSEUDO_8H (bh , rbx),
    DEFINE_GPR_PSEUDO_8H (ch , rcx),
    DEFINE_GPR_PSEUDO_8H (dh , rdx),
    DEFINE_GPR_PSEUDO_8L (al , rax),
    DEFINE_GPR_PSEUDO_8L (bl , rbx),
    DEFINE_GPR_PSEUDO_8L (cl , rcx),
    DEFINE_GPR_PSEUDO_8L (dl , rdx),
    DEFINE_GPR_PSEUDO_8L (dil, rdi),
    DEFINE_GPR_PSEUDO_8L (sil, rsi),
    DEFINE_GPR_PSEUDO_8L (bpl, rbp),
    DEFINE_GPR_PSEUDO_8L (spl, rsp),
    DEFINE_GPR_PSEUDO_8L (r8l, r8),
    DEFINE_GPR_PSEUDO_8L (r9l, r9),
    DEFINE_GPR_PSEUDO_8L (r10l, r10),
    DEFINE_GPR_PSEUDO_8L (r11l, r11),
    DEFINE_GPR_PSEUDO_8L (r12l, r12),
    DEFINE_GPR_PSEUDO_8L (r13l, r13),
    DEFINE_GPR_PSEUDO_8L (r14l, r14),
    DEFINE_GPR_PSEUDO_8L (r15l, r15)
};

// Floating point registers 64 bit
const DNBRegisterInfo
DNBArchImplX86_64::g_fpu_registers_no_avx[] =
{
    { e_regSetFPU, fpu_fcw      , "fctrl"       , NULL, Uint, Hex, FPU_SIZE_UINT(fcw)       , FPU_OFFSET(fcw)       , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_fsw      , "fstat"       , NULL, Uint, Hex, FPU_SIZE_UINT(fsw)       , FPU_OFFSET(fsw)       , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_ftw      , "ftag"        , NULL, Uint, Hex, FPU_SIZE_UINT(ftw)       , FPU_OFFSET(ftw)       , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_fop      , "fop"         , NULL, Uint, Hex, FPU_SIZE_UINT(fop)       , FPU_OFFSET(fop)       , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_ip       , "fioff"       , NULL, Uint, Hex, FPU_SIZE_UINT(ip)        , FPU_OFFSET(ip)        , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_cs       , "fiseg"       , NULL, Uint, Hex, FPU_SIZE_UINT(cs)        , FPU_OFFSET(cs)        , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_dp       , "fooff"       , NULL, Uint, Hex, FPU_SIZE_UINT(dp)        , FPU_OFFSET(dp)        , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_ds       , "foseg"       , NULL, Uint, Hex, FPU_SIZE_UINT(ds)        , FPU_OFFSET(ds)        , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_mxcsr    , "mxcsr"       , NULL, Uint, Hex, FPU_SIZE_UINT(mxcsr)     , FPU_OFFSET(mxcsr)     , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_mxcsrmask, "mxcsrmask"   , NULL, Uint, Hex, FPU_SIZE_UINT(mxcsrmask) , FPU_OFFSET(mxcsrmask) , -1U, -1U, -1U, -1U, NULL, NULL },
    
    { e_regSetFPU, fpu_stmm0, "stmm0", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm0), FPU_OFFSET(stmm0), ehframe_dwarf_stmm0, ehframe_dwarf_stmm0, -1U, debugserver_stmm0, NULL, NULL },
    { e_regSetFPU, fpu_stmm1, "stmm1", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm1), FPU_OFFSET(stmm1), ehframe_dwarf_stmm1, ehframe_dwarf_stmm1, -1U, debugserver_stmm1, NULL, NULL },
    { e_regSetFPU, fpu_stmm2, "stmm2", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm2), FPU_OFFSET(stmm2), ehframe_dwarf_stmm2, ehframe_dwarf_stmm2, -1U, debugserver_stmm2, NULL, NULL },
    { e_regSetFPU, fpu_stmm3, "stmm3", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm3), FPU_OFFSET(stmm3), ehframe_dwarf_stmm3, ehframe_dwarf_stmm3, -1U, debugserver_stmm3, NULL, NULL },
    { e_regSetFPU, fpu_stmm4, "stmm4", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm4), FPU_OFFSET(stmm4), ehframe_dwarf_stmm4, ehframe_dwarf_stmm4, -1U, debugserver_stmm4, NULL, NULL },
    { e_regSetFPU, fpu_stmm5, "stmm5", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm5), FPU_OFFSET(stmm5), ehframe_dwarf_stmm5, ehframe_dwarf_stmm5, -1U, debugserver_stmm5, NULL, NULL },
    { e_regSetFPU, fpu_stmm6, "stmm6", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm6), FPU_OFFSET(stmm6), ehframe_dwarf_stmm6, ehframe_dwarf_stmm6, -1U, debugserver_stmm6, NULL, NULL },
    { e_regSetFPU, fpu_stmm7, "stmm7", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm7), FPU_OFFSET(stmm7), ehframe_dwarf_stmm7, ehframe_dwarf_stmm7, -1U, debugserver_stmm7, NULL, NULL },
    
    { e_regSetFPU, fpu_xmm0 , "xmm0"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm0)   , FPU_OFFSET(xmm0) , ehframe_dwarf_xmm0 , ehframe_dwarf_xmm0 , -1U, debugserver_xmm0 , NULL, NULL },
    { e_regSetFPU, fpu_xmm1 , "xmm1"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm1)   , FPU_OFFSET(xmm1) , ehframe_dwarf_xmm1 , ehframe_dwarf_xmm1 , -1U, debugserver_xmm1 , NULL, NULL },
    { e_regSetFPU, fpu_xmm2 , "xmm2"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm2)   , FPU_OFFSET(xmm2) , ehframe_dwarf_xmm2 , ehframe_dwarf_xmm2 , -1U, debugserver_xmm2 , NULL, NULL },
    { e_regSetFPU, fpu_xmm3 , "xmm3"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm3)   , FPU_OFFSET(xmm3) , ehframe_dwarf_xmm3 , ehframe_dwarf_xmm3 , -1U, debugserver_xmm3 , NULL, NULL },
    { e_regSetFPU, fpu_xmm4 , "xmm4"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm4)   , FPU_OFFSET(xmm4) , ehframe_dwarf_xmm4 , ehframe_dwarf_xmm4 , -1U, debugserver_xmm4 , NULL, NULL },
    { e_regSetFPU, fpu_xmm5 , "xmm5"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm5)   , FPU_OFFSET(xmm5) , ehframe_dwarf_xmm5 , ehframe_dwarf_xmm5 , -1U, debugserver_xmm5 , NULL, NULL },
    { e_regSetFPU, fpu_xmm6 , "xmm6"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm6)   , FPU_OFFSET(xmm6) , ehframe_dwarf_xmm6 , ehframe_dwarf_xmm6 , -1U, debugserver_xmm6 , NULL, NULL },
    { e_regSetFPU, fpu_xmm7 , "xmm7"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm7)   , FPU_OFFSET(xmm7) , ehframe_dwarf_xmm7 , ehframe_dwarf_xmm7 , -1U, debugserver_xmm7 , NULL, NULL },
    { e_regSetFPU, fpu_xmm8 , "xmm8"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm8)   , FPU_OFFSET(xmm8) , ehframe_dwarf_xmm8 , ehframe_dwarf_xmm8 , -1U, debugserver_xmm8 , NULL, NULL },
    { e_regSetFPU, fpu_xmm9 , "xmm9"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm9)   , FPU_OFFSET(xmm9) , ehframe_dwarf_xmm9 , ehframe_dwarf_xmm9 , -1U, debugserver_xmm9 , NULL, NULL },
    { e_regSetFPU, fpu_xmm10, "xmm10"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm10)  , FPU_OFFSET(xmm10), ehframe_dwarf_xmm10, ehframe_dwarf_xmm10, -1U, debugserver_xmm10, NULL, NULL },
    { e_regSetFPU, fpu_xmm11, "xmm11"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm11)  , FPU_OFFSET(xmm11), ehframe_dwarf_xmm11, ehframe_dwarf_xmm11, -1U, debugserver_xmm11, NULL, NULL },
    { e_regSetFPU, fpu_xmm12, "xmm12"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm12)  , FPU_OFFSET(xmm12), ehframe_dwarf_xmm12, ehframe_dwarf_xmm12, -1U, debugserver_xmm12, NULL, NULL },
    { e_regSetFPU, fpu_xmm13, "xmm13"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm13)  , FPU_OFFSET(xmm13), ehframe_dwarf_xmm13, ehframe_dwarf_xmm13, -1U, debugserver_xmm13, NULL, NULL },
    { e_regSetFPU, fpu_xmm14, "xmm14"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm14)  , FPU_OFFSET(xmm14), ehframe_dwarf_xmm14, ehframe_dwarf_xmm14, -1U, debugserver_xmm14, NULL, NULL },
    { e_regSetFPU, fpu_xmm15, "xmm15"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm15)  , FPU_OFFSET(xmm15), ehframe_dwarf_xmm15, ehframe_dwarf_xmm15, -1U, debugserver_xmm15, NULL, NULL },
};

static const char *g_contained_ymm0 [] = { "ymm0", NULL };
static const char *g_contained_ymm1 [] = { "ymm1", NULL };
static const char *g_contained_ymm2 [] = { "ymm2", NULL };
static const char *g_contained_ymm3 [] = { "ymm3", NULL };
static const char *g_contained_ymm4 [] = { "ymm4", NULL };
static const char *g_contained_ymm5 [] = { "ymm5", NULL };
static const char *g_contained_ymm6 [] = { "ymm6", NULL };
static const char *g_contained_ymm7 [] = { "ymm7", NULL };
static const char *g_contained_ymm8 [] = { "ymm8", NULL };
static const char *g_contained_ymm9 [] = { "ymm9", NULL };
static const char *g_contained_ymm10[] = { "ymm10", NULL };
static const char *g_contained_ymm11[] = { "ymm11", NULL };
static const char *g_contained_ymm12[] = { "ymm12", NULL };
static const char *g_contained_ymm13[] = { "ymm13", NULL };
static const char *g_contained_ymm14[] = { "ymm14", NULL };
static const char *g_contained_ymm15[] = { "ymm15", NULL };

const DNBRegisterInfo
DNBArchImplX86_64::g_fpu_registers_avx[] =
{
    { e_regSetFPU, fpu_fcw      , "fctrl"       , NULL, Uint, Hex, FPU_SIZE_UINT(fcw)       , AVX_OFFSET(fcw)       , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_fsw      , "fstat"       , NULL, Uint, Hex, FPU_SIZE_UINT(fsw)       , AVX_OFFSET(fsw)       , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_ftw      , "ftag"        , NULL, Uint, Hex, FPU_SIZE_UINT(ftw)       , AVX_OFFSET(ftw)       , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_fop      , "fop"         , NULL, Uint, Hex, FPU_SIZE_UINT(fop)       , AVX_OFFSET(fop)       , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_ip       , "fioff"       , NULL, Uint, Hex, FPU_SIZE_UINT(ip)        , AVX_OFFSET(ip)        , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_cs       , "fiseg"       , NULL, Uint, Hex, FPU_SIZE_UINT(cs)        , AVX_OFFSET(cs)        , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_dp       , "fooff"       , NULL, Uint, Hex, FPU_SIZE_UINT(dp)        , AVX_OFFSET(dp)        , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_ds       , "foseg"       , NULL, Uint, Hex, FPU_SIZE_UINT(ds)        , AVX_OFFSET(ds)        , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_mxcsr    , "mxcsr"       , NULL, Uint, Hex, FPU_SIZE_UINT(mxcsr)     , AVX_OFFSET(mxcsr)     , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetFPU, fpu_mxcsrmask, "mxcsrmask"   , NULL, Uint, Hex, FPU_SIZE_UINT(mxcsrmask) , AVX_OFFSET(mxcsrmask) , -1U, -1U, -1U, -1U, NULL, NULL },
    
    { e_regSetFPU, fpu_stmm0, "stmm0", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm0), AVX_OFFSET(stmm0), ehframe_dwarf_stmm0, ehframe_dwarf_stmm0, -1U, debugserver_stmm0, NULL, NULL },
    { e_regSetFPU, fpu_stmm1, "stmm1", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm1), AVX_OFFSET(stmm1), ehframe_dwarf_stmm1, ehframe_dwarf_stmm1, -1U, debugserver_stmm1, NULL, NULL },
    { e_regSetFPU, fpu_stmm2, "stmm2", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm2), AVX_OFFSET(stmm2), ehframe_dwarf_stmm2, ehframe_dwarf_stmm2, -1U, debugserver_stmm2, NULL, NULL },
    { e_regSetFPU, fpu_stmm3, "stmm3", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm3), AVX_OFFSET(stmm3), ehframe_dwarf_stmm3, ehframe_dwarf_stmm3, -1U, debugserver_stmm3, NULL, NULL },
    { e_regSetFPU, fpu_stmm4, "stmm4", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm4), AVX_OFFSET(stmm4), ehframe_dwarf_stmm4, ehframe_dwarf_stmm4, -1U, debugserver_stmm4, NULL, NULL },
    { e_regSetFPU, fpu_stmm5, "stmm5", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm5), AVX_OFFSET(stmm5), ehframe_dwarf_stmm5, ehframe_dwarf_stmm5, -1U, debugserver_stmm5, NULL, NULL },
    { e_regSetFPU, fpu_stmm6, "stmm6", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm6), AVX_OFFSET(stmm6), ehframe_dwarf_stmm6, ehframe_dwarf_stmm6, -1U, debugserver_stmm6, NULL, NULL },
    { e_regSetFPU, fpu_stmm7, "stmm7", NULL, Vector, VectorOfUInt8, FPU_SIZE_MMST(stmm7), AVX_OFFSET(stmm7), ehframe_dwarf_stmm7, ehframe_dwarf_stmm7, -1U, debugserver_stmm7, NULL, NULL },
    
    { e_regSetFPU, fpu_ymm0 , "ymm0"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm0)   , AVX_OFFSET_YMM(0) , ehframe_dwarf_ymm0 , ehframe_dwarf_ymm0 , -1U, debugserver_ymm0, NULL, NULL },
    { e_regSetFPU, fpu_ymm1 , "ymm1"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm1)   , AVX_OFFSET_YMM(1) , ehframe_dwarf_ymm1 , ehframe_dwarf_ymm1 , -1U, debugserver_ymm1, NULL, NULL },
    { e_regSetFPU, fpu_ymm2 , "ymm2"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm2)   , AVX_OFFSET_YMM(2) , ehframe_dwarf_ymm2 , ehframe_dwarf_ymm2 , -1U, debugserver_ymm2, NULL, NULL },
    { e_regSetFPU, fpu_ymm3 , "ymm3"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm3)   , AVX_OFFSET_YMM(3) , ehframe_dwarf_ymm3 , ehframe_dwarf_ymm3 , -1U, debugserver_ymm3, NULL, NULL },
    { e_regSetFPU, fpu_ymm4 , "ymm4"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm4)   , AVX_OFFSET_YMM(4) , ehframe_dwarf_ymm4 , ehframe_dwarf_ymm4 , -1U, debugserver_ymm4, NULL, NULL },
    { e_regSetFPU, fpu_ymm5 , "ymm5"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm5)   , AVX_OFFSET_YMM(5) , ehframe_dwarf_ymm5 , ehframe_dwarf_ymm5 , -1U, debugserver_ymm5, NULL, NULL },
    { e_regSetFPU, fpu_ymm6 , "ymm6"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm6)   , AVX_OFFSET_YMM(6) , ehframe_dwarf_ymm6 , ehframe_dwarf_ymm6 , -1U, debugserver_ymm6, NULL, NULL },
    { e_regSetFPU, fpu_ymm7 , "ymm7"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm7)   , AVX_OFFSET_YMM(7) , ehframe_dwarf_ymm7 , ehframe_dwarf_ymm7 , -1U, debugserver_ymm7, NULL, NULL },
    { e_regSetFPU, fpu_ymm8 , "ymm8"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm8)   , AVX_OFFSET_YMM(8) , ehframe_dwarf_ymm8 , ehframe_dwarf_ymm8 , -1U, debugserver_ymm8 , NULL, NULL },
    { e_regSetFPU, fpu_ymm9 , "ymm9"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm9)   , AVX_OFFSET_YMM(9) , ehframe_dwarf_ymm9 , ehframe_dwarf_ymm9 , -1U, debugserver_ymm9 , NULL, NULL },
    { e_regSetFPU, fpu_ymm10, "ymm10"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm10)  , AVX_OFFSET_YMM(10), ehframe_dwarf_ymm10, ehframe_dwarf_ymm10, -1U, debugserver_ymm10, NULL, NULL },
    { e_regSetFPU, fpu_ymm11, "ymm11"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm11)  , AVX_OFFSET_YMM(11), ehframe_dwarf_ymm11, ehframe_dwarf_ymm11, -1U, debugserver_ymm11, NULL, NULL },
    { e_regSetFPU, fpu_ymm12, "ymm12"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm12)  , AVX_OFFSET_YMM(12), ehframe_dwarf_ymm12, ehframe_dwarf_ymm12, -1U, debugserver_ymm12, NULL, NULL },
    { e_regSetFPU, fpu_ymm13, "ymm13"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm13)  , AVX_OFFSET_YMM(13), ehframe_dwarf_ymm13, ehframe_dwarf_ymm13, -1U, debugserver_ymm13, NULL, NULL },
    { e_regSetFPU, fpu_ymm14, "ymm14"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm14)  , AVX_OFFSET_YMM(14), ehframe_dwarf_ymm14, ehframe_dwarf_ymm14, -1U, debugserver_ymm14, NULL, NULL },
    { e_regSetFPU, fpu_ymm15, "ymm15"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_YMM(ymm15)  , AVX_OFFSET_YMM(15), ehframe_dwarf_ymm15, ehframe_dwarf_ymm15, -1U, debugserver_ymm15, NULL, NULL },
    
    { e_regSetFPU, fpu_xmm0 , "xmm0"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm0)   , 0, ehframe_dwarf_xmm0 , ehframe_dwarf_xmm0 , -1U, debugserver_xmm0 , g_contained_ymm0 , NULL },
    { e_regSetFPU, fpu_xmm1 , "xmm1"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm1)   , 0, ehframe_dwarf_xmm1 , ehframe_dwarf_xmm1 , -1U, debugserver_xmm1 , g_contained_ymm1 , NULL },
    { e_regSetFPU, fpu_xmm2 , "xmm2"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm2)   , 0, ehframe_dwarf_xmm2 , ehframe_dwarf_xmm2 , -1U, debugserver_xmm2 , g_contained_ymm2 , NULL },
    { e_regSetFPU, fpu_xmm3 , "xmm3"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm3)   , 0, ehframe_dwarf_xmm3 , ehframe_dwarf_xmm3 , -1U, debugserver_xmm3 , g_contained_ymm3 , NULL },
    { e_regSetFPU, fpu_xmm4 , "xmm4"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm4)   , 0, ehframe_dwarf_xmm4 , ehframe_dwarf_xmm4 , -1U, debugserver_xmm4 , g_contained_ymm4 , NULL },
    { e_regSetFPU, fpu_xmm5 , "xmm5"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm5)   , 0, ehframe_dwarf_xmm5 , ehframe_dwarf_xmm5 , -1U, debugserver_xmm5 , g_contained_ymm5 , NULL },
    { e_regSetFPU, fpu_xmm6 , "xmm6"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm6)   , 0, ehframe_dwarf_xmm6 , ehframe_dwarf_xmm6 , -1U, debugserver_xmm6 , g_contained_ymm6 , NULL },
    { e_regSetFPU, fpu_xmm7 , "xmm7"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm7)   , 0, ehframe_dwarf_xmm7 , ehframe_dwarf_xmm7 , -1U, debugserver_xmm7 , g_contained_ymm7 , NULL },
    { e_regSetFPU, fpu_xmm8 , "xmm8"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm8)   , 0, ehframe_dwarf_xmm8 , ehframe_dwarf_xmm8 , -1U, debugserver_xmm8 , g_contained_ymm8 , NULL },
    { e_regSetFPU, fpu_xmm9 , "xmm9"    , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm9)   , 0, ehframe_dwarf_xmm9 , ehframe_dwarf_xmm9 , -1U, debugserver_xmm9 , g_contained_ymm9 , NULL },
    { e_regSetFPU, fpu_xmm10, "xmm10"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm10)  , 0, ehframe_dwarf_xmm10, ehframe_dwarf_xmm10, -1U, debugserver_xmm10, g_contained_ymm10, NULL },
    { e_regSetFPU, fpu_xmm11, "xmm11"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm11)  , 0, ehframe_dwarf_xmm11, ehframe_dwarf_xmm11, -1U, debugserver_xmm11, g_contained_ymm11, NULL },
    { e_regSetFPU, fpu_xmm12, "xmm12"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm12)  , 0, ehframe_dwarf_xmm12, ehframe_dwarf_xmm12, -1U, debugserver_xmm12, g_contained_ymm12, NULL },
    { e_regSetFPU, fpu_xmm13, "xmm13"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm13)  , 0, ehframe_dwarf_xmm13, ehframe_dwarf_xmm13, -1U, debugserver_xmm13, g_contained_ymm13, NULL },
    { e_regSetFPU, fpu_xmm14, "xmm14"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm14)  , 0, ehframe_dwarf_xmm14, ehframe_dwarf_xmm14, -1U, debugserver_xmm14, g_contained_ymm14, NULL },
    { e_regSetFPU, fpu_xmm15, "xmm15"   , NULL, Vector, VectorOfUInt8, FPU_SIZE_XMM(xmm15)  , 0, ehframe_dwarf_xmm15, ehframe_dwarf_xmm15, -1U, debugserver_xmm15, g_contained_ymm15, NULL }
    
    
};

// Exception registers

const DNBRegisterInfo
DNBArchImplX86_64::g_exc_registers[] =
{
    { e_regSetEXC, exc_trapno,      "trapno"    , NULL, Uint, Hex, EXC_SIZE (trapno)    , EXC_OFFSET (trapno)       , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetEXC, exc_err,         "err"       , NULL, Uint, Hex, EXC_SIZE (err)       , EXC_OFFSET (err)          , -1U, -1U, -1U, -1U, NULL, NULL },
    { e_regSetEXC, exc_faultvaddr,  "faultvaddr", NULL, Uint, Hex, EXC_SIZE (faultvaddr), EXC_OFFSET (faultvaddr)   , -1U, -1U, -1U, -1U, NULL, NULL }
};

// Number of registers in each register set
const size_t DNBArchImplX86_64::k_num_gpr_registers = sizeof(g_gpr_registers)/sizeof(DNBRegisterInfo);
const size_t DNBArchImplX86_64::k_num_fpu_registers_no_avx = sizeof(g_fpu_registers_no_avx)/sizeof(DNBRegisterInfo);
const size_t DNBArchImplX86_64::k_num_fpu_registers_avx = sizeof(g_fpu_registers_avx)/sizeof(DNBRegisterInfo);
const size_t DNBArchImplX86_64::k_num_exc_registers = sizeof(g_exc_registers)/sizeof(DNBRegisterInfo);
const size_t DNBArchImplX86_64::k_num_all_registers_no_avx = k_num_gpr_registers + k_num_fpu_registers_no_avx + k_num_exc_registers;
const size_t DNBArchImplX86_64::k_num_all_registers_avx = k_num_gpr_registers + k_num_fpu_registers_avx + k_num_exc_registers;

//----------------------------------------------------------------------
// Register set definitions. The first definitions at register set index
// of zero is for all registers, followed by other registers sets. The
// register information for the all register set need not be filled in.
//----------------------------------------------------------------------
const DNBRegisterSetInfo
DNBArchImplX86_64::g_reg_sets_no_avx[] =
{
    { "x86_64 Registers",           NULL,               k_num_all_registers_no_avx },
    { "General Purpose Registers",  g_gpr_registers,    k_num_gpr_registers },
    { "Floating Point Registers",   g_fpu_registers_no_avx, k_num_fpu_registers_no_avx },
    { "Exception State Registers",  g_exc_registers,    k_num_exc_registers }
};

const DNBRegisterSetInfo
DNBArchImplX86_64::g_reg_sets_avx[] =
{
    { "x86_64 Registers",           NULL,               k_num_all_registers_avx },
    { "General Purpose Registers",  g_gpr_registers,    k_num_gpr_registers },
    { "Floating Point Registers",   g_fpu_registers_avx, k_num_fpu_registers_avx },
    { "Exception State Registers",  g_exc_registers,    k_num_exc_registers }
};

// Total number of register sets for this architecture
const size_t DNBArchImplX86_64::k_num_register_sets = sizeof(g_reg_sets_avx)/sizeof(DNBRegisterSetInfo);

const DNBRegisterSetInfo *
DNBArchImplX86_64::GetRegisterSetInfo(nub_size_t *num_reg_sets)
{
    *num_reg_sets = k_num_register_sets;
    
    if (CPUHasAVX())
        return g_reg_sets_avx;
    else
        return g_reg_sets_no_avx;
}

//----------------------------------------------------------------------
// Custom Selfde interface to the DNB register information.
//----------------------------------------------------------------------

extern "C" {

const struct DNBRegisterSetInfo *getRegisterSetInfoX86_64(nub_size_t *size) {
    return DNBArchImplX86_64::GetRegisterSetInfo(size);
}

RegisterSetKindX86_64 getRegisterSetKindX86_64(uint32_t setID) {
    switch (setID) {
    case DNBArchImplX86_64::e_regSetGPR:
        return GPRKindX86_64;
    case DNBArchImplX86_64::e_regSetFPU:
        return FPUKindX86_64;
    case DNBArchImplX86_64::e_regSetEXC:
        return EXCKindX86_64;
    default:
        return InvalidRegisterKindX86_64;
    }
}

bool getGPRValueX86_64(uint32_t registerID, const x86_thread_state64_t *state, uint8_t *destination, nub_size_t *size) {
    uint64_t value;
    if (*size < sizeof(uint64_t)) {
        assert(false && "Destination value isn't big enough.");
        return false;
    }
    switch (registerID) {
#define CASE(name) case gpr_##name: value = state->__##name; break;
        CASE(rax)
        CASE(rbx)
        CASE(rcx)
        CASE(rdx)
        CASE(rdi)
        CASE(rsi)
        CASE(rbp)
        CASE(rsp)
        CASE(r8)
        CASE(r9)
        CASE(r10)
        CASE(r11)
        CASE(r12)
        CASE(r13)
        CASE(r14)
        CASE(r15)
        CASE(rip)
        CASE(rflags)
        CASE(cs)
        CASE(fs)
        CASE(gs)
#undef CASE
        default: return false;
    }
    memcpy(destination, &value, sizeof(uint64_t));
    *size = sizeof(uint64_t);
    return true;
}

bool setGPRValueX86_64(uint32_t registerID, x86_thread_state64_t *state, const uint8_t *source, nub_size_t size) {
    if (size != sizeof(uint64_t)) {
        assert(false && "Source value isn't of the right size!");
        return false;
    }
    uint64_t value;
    memcpy(&value, source, sizeof(uint64_t));
    switch (registerID) {
#define CASE(name) case gpr_##name: state->__##name = value; break;
        CASE(rax)
        CASE(rbx)
        CASE(rcx)
        CASE(rdx)
        CASE(rdi)
        CASE(rsi)
        CASE(rbp)
        CASE(rsp)
        CASE(r8)
        CASE(r9)
        CASE(r10)
        CASE(r11)
        CASE(r12)
        CASE(r13)
        CASE(r14)
        CASE(r15)
        CASE(rip)
        CASE(rflags)
        CASE(cs)
        CASE(fs)
        CASE(gs)
#undef CASE
        default: return false;
    }
    return true;
}

bool getFPUValueX86_64(uint32_t registerID, const x86_float_state64_t *fpuState, const x86_avx_state64_t *avxState, uint8_t *destination, nub_size_t *size) {
    assert(fpuState || avxState);
    if (fpuState) { assert(!avxState); }

    if (*size < 32) {
        assert(false && "Not enough destination memory");
        return false;
    }
    uint8_t u8;
    uint16_t u16;
    uint32_t u32;

    switch (registerID) {
#define GET_INTEGER_REG(name, dest, T) \
    static_assert(sizeof(fpuState->__##name) == sizeof(T), "Invalid register size"); \
    static_assert(sizeof(avxState->__##name) == sizeof(T), "Invalid register size"); \
    dest = fpuState != nullptr ? \
        *(reinterpret_cast<const T *>(&(fpuState->__##name))) : \
        *(reinterpret_cast<const T *>(&(avxState->__##name))); \
    memcpy(destination, &dest, sizeof(T)); \
    *size = sizeof(T); 

#define U8REG(name)  case name: GET_INTEGER_REG(name, u8, uint8_t) return true;
#define U16REG(name) case name: GET_INTEGER_REG(name, u16, uint16_t) return true;
#define U32REG(name) case name: GET_INTEGER_REG(name, u32, uint32_t) return true;
        U16REG(fpu_fcw)
        U16REG(fpu_fsw)
        U8REG(fpu_ftw)
        U16REG(fpu_fop)
        U32REG(fpu_ip)
        U16REG(fpu_cs)
        U32REG(fpu_dp)
        U16REG(fpu_ds)
        U32REG(fpu_mxcsr)
        U32REG(fpu_mxcsrmask)
#undef U32REG
#undef U16REG
#undef U8REG
#undef GET_INTEGER_REG
#define FPUREG(name) case name: \
            memcpy(destination, fpuState != nullptr ? &(fpuState->__##name) : &(avxState->__##name), 10); \
            *size = 10; \
            return true;

        FPUREG(fpu_stmm0)
        FPUREG(fpu_stmm1)
        FPUREG(fpu_stmm2)
        FPUREG(fpu_stmm3)
        FPUREG(fpu_stmm4)
        FPUREG(fpu_stmm5)
        FPUREG(fpu_stmm6)
        FPUREG(fpu_stmm7)
#undef FPUREG
#define XMMREG(n) case fpu_xmm##n: \
            static_assert(sizeof(fpuState->__fpu_xmm##n) == 16 && sizeof(avxState->__fpu_xmm##n) == 16, ""); \
            memcpy(destination, fpuState != nullptr ? &(fpuState->__fpu_xmm##n) : &(avxState->__fpu_xmm##n), 16); \
            *size = 16; \
            return true;

        XMMREG(0)
        XMMREG(1)
        XMMREG(2)
        XMMREG(3)
        XMMREG(4)
        XMMREG(5)
        XMMREG(6)
        XMMREG(7)
        XMMREG(8)
        XMMREG(9)
        XMMREG(10)
        XMMREG(11)
        XMMREG(12)
        XMMREG(13)
        XMMREG(14)
        XMMREG(15)
#undef XMMREG
        default: break;
    }
    // Continue only when we have the AVX state.
    if (!avxState) {
        return false;
    }
    switch (registerID) {
#define YMMREG(n) case fpu_ymm##n: \
            static_assert(sizeof(avxState->__fpu_xmm##n) == 16 && sizeof(avxState->__fpu_ymmh##n) == 16, ""); \
            memcpy(destination, &(avxState->__fpu_xmm##n), 16); \
            memcpy(destination + 16, &(avxState->__fpu_ymmh##n), 16); \
            *size = 32; \
            return true;

        YMMREG(0)
        YMMREG(1)
        YMMREG(2)
        YMMREG(3)
        YMMREG(4)
        YMMREG(5)
        YMMREG(6)
        YMMREG(7)
        YMMREG(8)
        YMMREG(9)
        YMMREG(10)
        YMMREG(11)
        YMMREG(12)
        YMMREG(13)
        YMMREG(14)
        YMMREG(15)
#undef YMMREG
    }
    return false;
}

bool setFPUValueX86_64(uint32_t registerID, x86_float_state64_t *fpuState, x86_avx_state64_t *avxState, const uint8_t *source, nub_size_t size) {
    assert(fpuState || avxState);
    if (fpuState) { assert(!avxState); }

    switch (registerID) {
#define SET_INTEGER_REG(name, dest, T) \
    static_assert(sizeof(fpuState->__##name) == sizeof(T), "Invalid register size"); \
    static_assert(sizeof(avxState->__##name) == sizeof(T), "Invalid register size"); \
    if (size != sizeof(T)) { assert(false && "Source value isn't of the right size"); return false; } \
    if (fpuState != nullptr) { \
        *(reinterpret_cast<T *>(&(fpuState->__##name))) = *reinterpret_cast<const T*>(source); \
    } else { \
        *(reinterpret_cast<T *>(&(avxState->__##name))) = *reinterpret_cast<const T*>(source); \
    }

#define U8REG(name)  case name: SET_INTEGER_REG(name, u8, uint8_t) return true;
#define U16REG(name) case name: SET_INTEGER_REG(name, u16, uint16_t) return true;
#define U32REG(name) case name: SET_INTEGER_REG(name, u32, uint32_t) return true;
        U16REG(fpu_fcw)
        U16REG(fpu_fsw)
        U8REG(fpu_ftw)
        U16REG(fpu_fop)
        U32REG(fpu_ip)
        U16REG(fpu_cs)
        U32REG(fpu_dp)
        U16REG(fpu_ds)
        U32REG(fpu_mxcsr)
        U32REG(fpu_mxcsrmask)
#undef U32REG
#undef U16REG
#undef U8REG
#undef SET_INTEGER_REG
#define FPUREG(name) case name: \
            if (size != 10) { assert(false && "Source value isn't of the right size"); return false; } \
            memcpy(fpuState != nullptr ? &(fpuState->__##name) : &(avxState->__##name), source, 10); \
            return true;

        FPUREG(fpu_stmm0)
        FPUREG(fpu_stmm1)
        FPUREG(fpu_stmm2)
        FPUREG(fpu_stmm3)
        FPUREG(fpu_stmm4)
        FPUREG(fpu_stmm5)
        FPUREG(fpu_stmm6)
        FPUREG(fpu_stmm7)
#undef FPUREG
#define XMMREG(n) case fpu_xmm##n: \
            static_assert(sizeof(fpuState->__fpu_xmm##n) == 16 && sizeof(avxState->__fpu_xmm##n) == 16, ""); \
            if (size != 16) { assert(false && "Source value isn't of the right size"); return false; } \
            memcpy(fpuState != nullptr ? &(fpuState->__fpu_xmm##n) : &(avxState->__fpu_xmm##n), source, 16); \
            return true;

        XMMREG(0)
        XMMREG(1)
        XMMREG(2)
        XMMREG(3)
        XMMREG(4)
        XMMREG(5)
        XMMREG(6)
        XMMREG(7)
        XMMREG(8)
        XMMREG(9)
        XMMREG(10)
        XMMREG(11)
        XMMREG(12)
        XMMREG(13)
        XMMREG(14)
        XMMREG(15)
#undef XMMREG
        default: break;
    }
    // Continue only when we have the AVX state.
    if (!avxState) {
        return false;
    }
    switch (registerID) {
#define YMMREG(n) case fpu_ymm##n: \
            static_assert(sizeof(avxState->__fpu_xmm##n) == 16 && sizeof(avxState->__fpu_ymmh##n) == 16, ""); \
            if (size != 32) { assert(false && "Source value isn't of the right size"); return false; } \
            memcpy(&(avxState->__fpu_xmm##n), source, 16); \
            memcpy(&(avxState->__fpu_ymmh##n), source + 16, 16); \
            return true;

        YMMREG(0)
        YMMREG(1)
        YMMREG(2)
        YMMREG(3)
        YMMREG(4)
        YMMREG(5)
        YMMREG(6)
        YMMREG(7)
        YMMREG(8)
        YMMREG(9)
        YMMREG(10)
        YMMREG(11)
        YMMREG(12)
        YMMREG(13)
        YMMREG(14)
        YMMREG(15)
#undef YMMREG
    }
    return false;
}

bool getEXCValueX86_64(uint32_t registerID, const x86_exception_state64_t *state, uint8_t *destination, nub_size_t *size) {
    if (*size < sizeof(uint64_t)) {
        assert(false && "Destination value isn't big enough.");
        return false;
    }
    switch (registerID) {
        case exc_trapno:
            // For some reason LLDB's debug server uses 32 bits for trapno with both the trapno and cpu there.
            static_assert(sizeof(state->__trapno) == sizeof(uint16_t), "Invalid size");
            static_assert(sizeof(state->__cpu) == sizeof(uint16_t), "Invalid size");
            memcpy(destination, &(state->__trapno), sizeof(state->__trapno));
            memcpy(destination + sizeof(state->__trapno), &(state->__cpu), sizeof(state->__cpu));
            *size = sizeof(state->__trapno) + sizeof(state->__cpu);
            return true;

#define INTEGER_REG(name, T) case exc_##name: \
            static_assert(sizeof(state->__##name) == sizeof(T), "Invalid size"); \
            memcpy(destination, &(state->__##name), sizeof(state->__##name)); \
            *size = sizeof(state->__##name); \
            return true;

        INTEGER_REG(err, uint32_t)
        INTEGER_REG(faultvaddr, uint64_t)
        default: break;
#undef INTEGER_REG
    }
    return false;
}

bool setEXCValueX86_64(uint32_t registerID, x86_exception_state64_t *state, const uint8_t *source, nub_size_t size) {
    switch (registerID) {
        case exc_trapno:
            // For some reason LLDB's debug server uses 32 bits for trapno with both the trapno and cpu there.
            if (size != (sizeof(state->__trapno) + sizeof(state->__cpu))) {
                assert(false && "Source value isn't of the right size");
                return false;
            }
            memcpy(&(state->__trapno), source, sizeof(state->__trapno));
            memcpy(&(state->__cpu), source + sizeof(state->__trapno), sizeof(state->__cpu));
            return true;

#define INTEGER_REG(name, T) case exc_##name: \
            if (size != sizeof(state->__##name)) { assert(false && "Source value isn't of the right size"); return false; } \
            memcpy(&(state->__##name), source, sizeof(state->__##name)); \
            return true;

        INTEGER_REG(err, uint32_t)
        INTEGER_REG(faultvaddr, uint64_t)
        default: break;
#undef INTEGER_REG
    }
    return false;
}

void getRegisterContextX86_64(const x86_thread_state64_t *state, const x86_float_state64_t *fpuState, const x86_avx_state64_t *avxState, const x86_exception_state64_t *excState, uint8_t *destination, nub_size_t *size) {
    assert(fpuState || avxState);
    if (fpuState) { assert(!avxState); }

    uint8_t *buffer = destination;
    size_t freeBufferSize = *size;

#define REGISTER_LOOP(firstRegister, lastRegister, fn, state) \
        for (uint32_t i = (firstRegister), lastI = (lastRegister); i <= lastI; ++i) { \
            size_t registerSize = freeBufferSize; \
            auto result = fn(i, state, buffer, &registerSize); assert(result); \
            buffer += registerSize; \
            assert(freeBufferSize >= registerSize); \
            freeBufferSize -= registerSize; \
        }
#define REGISTER_LOOP2(firstRegister, lastRegister, fn, state1, state2) \
        for (uint32_t i = (firstRegister), lastI = (lastRegister); i <= lastI; ++i) { \
            size_t registerSize = freeBufferSize; \
            auto result = fn(i, state1, state2, buffer, &registerSize); assert(result); \
            buffer += registerSize; \
            assert(freeBufferSize >= registerSize); \
            freeBufferSize -= registerSize; \
        }

    // GPR
    REGISTER_LOOP(gpr_rax, gpr_eax - 1, getGPRValueX86_64, state)
    // FPU
    REGISTER_LOOP2(fpu_fcw, fpu_mxcsrmask, getFPUValueX86_64, fpuState, avxState)
    REGISTER_LOOP2(fpu_stmm0, fpu_stmm7, getFPUValueX86_64, fpuState, avxState)
    if (fpuState) {
        REGISTER_LOOP2(fpu_xmm0, fpu_xmm15, getFPUValueX86_64, fpuState, avxState)
    } else {
        REGISTER_LOOP2(fpu_ymm0, fpu_ymm15, getFPUValueX86_64, fpuState, avxState)
    }
    // EXC
    REGISTER_LOOP(0, k_num_exc_regs - 1, getEXCValueX86_64, excState)
#undef REGISTER_LOOP
#undef REGISTER_LOOP2
    *size = size_t(buffer - destination);
}

void setRegisterContextX86_64(x86_thread_state64_t *state, x86_float_state64_t *fpuState, x86_avx_state64_t *avxState, x86_exception_state64_t *excState, const uint8_t *source, nub_size_t size) {
    assert(fpuState || avxState);
    if (fpuState) { assert(!avxState); }
    
    const uint8_t *buffer = source;
#define REGISTER_LOOP(firstRegister, lastRegister, fn, state, regSize) \
        for (uint32_t i = (firstRegister), lastI = (lastRegister); i <= lastI; ++i) { \
            size_t registerSize = regSize; \
            assert(size >= registerSize); \
            auto result = fn(i, state, buffer, registerSize); assert(result);\
            buffer += registerSize; \
            size -= registerSize; \
        }
#define REGISTER_LOOP2(firstRegister, lastRegister, fn, state1, state2, regSize) \
        for (uint32_t i = (firstRegister), lastI = (lastRegister); i <= lastI; ++i) { \
            size_t registerSize = regSize; \
            assert(size >= registerSize); \
            auto result = fn(i, state1, state2, buffer, registerSize); assert(result);\
            buffer += registerSize; \
            size -= registerSize; \
        }

    // GPR
    REGISTER_LOOP(gpr_rax, gpr_eax - 1, setGPRValueX86_64, state, sizeof(uint64_t))
    // FPU
    REGISTER_LOOP2(fpu_fcw, fpu_mxcsrmask, setFPUValueX86_64, fpuState, avxState, DNBArchImplX86_64::g_fpu_registers_no_avx[i].size)
    REGISTER_LOOP2(fpu_stmm0, fpu_stmm7, setFPUValueX86_64, fpuState, avxState, 10)
    if (fpuState) {
        REGISTER_LOOP2(fpu_xmm0, fpu_xmm15, setFPUValueX86_64, fpuState, avxState, 16)
    } else {
        REGISTER_LOOP2(fpu_ymm0, fpu_ymm15, setFPUValueX86_64, fpuState, avxState, 32)
    }
    // EXC
    REGISTER_LOOP(0, k_num_exc_regs - 1, setEXCValueX86_64, excState, DNBArchImplX86_64::g_exc_registers[i].size)
#undef REGISTER_LOOP
#undef REGISTER_LOOP2
    assert(size == 0);
}

} // end extern "C"

#endif
