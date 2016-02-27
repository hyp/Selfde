// Modified DNBDefs.h with register information only.
//
//===-- DNBDefs.h -----------------------------------------------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
//  Created by Greg Clayton on 6/26/07.
//
//===----------------------------------------------------------------------===//

#ifndef __DNBDefs_h__
#define __DNBDefs_h__

#include <stdint.h>
#include <signal.h>
#include <stdio.h>
#include <sys/syslimits.h>
#include <unistd.h>

#ifdef __cplusplus
extern "C" {
#endif

//----------------------------------------------------------------------
// Define nub_addr_t and the invalid address value from the architecture
//----------------------------------------------------------------------
#if defined (__x86_64__) || defined (__ppc64__) || defined (__arm64__) || defined (__aarch64__)

//----------------------------------------------------------------------
// 64 bit address architectures
//----------------------------------------------------------------------
typedef uint64_t        nub_addr_t;
#define INVALID_NUB_ADDRESS     ((nub_addr_t)~0ull)

#elif defined (__i386__) || defined (__powerpc__) || defined (__ppc__) || defined (__arm__)

//----------------------------------------------------------------------
// 32 bit address architectures
//----------------------------------------------------------------------

typedef uint32_t        nub_addr_t;
#define INVALID_NUB_ADDRESS     ((nub_addr_t)~0ul)

#else

//----------------------------------------------------------------------
// Default to 64 bit address for unrecognized architectures.
//----------------------------------------------------------------------

#warning undefined architecture, defaulting to 8 byte addresses
typedef uint64_t        nub_addr_t;
#define INVALID_NUB_ADDRESS     ((nub_addr_t)~0ull)


#endif

typedef size_t          nub_size_t;
typedef ssize_t         nub_ssize_t;
typedef uint32_t        nub_index_t;
typedef pid_t           nub_process_t;
typedef uint64_t        nub_thread_t;
typedef uint32_t        nub_event_t;
typedef uint32_t        nub_bool_t;
    
#define INVALID_NUB_REGNUM      UINT32_MAX

#define REGISTER_SET_ALL        0
// Generic Register set to be defined by each architecture for access to common
// register values.
#define REGISTER_SET_GENERIC    ((uint32_t)0xFFFFFFFFu)
#define GENERIC_REGNUM_PC       0   // Program Counter
#define GENERIC_REGNUM_SP       1   // Stack Pointer
#define GENERIC_REGNUM_FP       2   // Frame Pointer
#define GENERIC_REGNUM_RA       3   // Return Address
#define GENERIC_REGNUM_FLAGS    4   // Processor flags register
#define GENERIC_REGNUM_ARG1     5   // The register that would contain pointer size or less argument 1 (if any)
#define GENERIC_REGNUM_ARG2     6   // The register that would contain pointer size or less argument 2 (if any)
#define GENERIC_REGNUM_ARG3     7   // The register that would contain pointer size or less argument 3 (if any)
#define GENERIC_REGNUM_ARG4     8   // The register that would contain pointer size or less argument 4 (if any)
#define GENERIC_REGNUM_ARG5     9   // The register that would contain pointer size or less argument 5 (if any)
#define GENERIC_REGNUM_ARG6     10  // The register that would contain pointer size or less argument 6 (if any)
#define GENERIC_REGNUM_ARG7     11  // The register that would contain pointer size or less argument 7 (if any)
#define GENERIC_REGNUM_ARG8     12  // The register that would contain pointer size or less argument 8 (if any)

enum DNBRegisterType
{
    InvalidRegType = 0,
    Uint,               // unsigned integer
    Sint,               // signed integer
    IEEE754,            // float
    Vector              // vector registers
};

enum DNBRegisterFormat
{
    InvalidRegFormat = 0,
    Binary,
    Decimal,
    Hex,
    Float,
    VectorOfSInt8,
    VectorOfUInt8,
    VectorOfSInt16,
    VectorOfUInt16,
    VectorOfSInt32,
    VectorOfUInt32,
    VectorOfFloat32,
    VectorOfUInt128
};

struct DNBRegisterInfo
{
    uint32_t    set;            // Register set
    uint32_t    reg;            // Register number
    const char *name;           // Name of this register
    const char *alt;            // Alternate name
    uint16_t    type;           // Type of the register bits (DNBRegisterType)
    uint16_t    format;         // Default format for display (DNBRegisterFormat),
    uint32_t    size;           // Size in bytes of the register
    uint32_t    offset;         // Offset from the beginning of the register context
    uint32_t    reg_ehframe;    // eh_frame register number (INVALID_NUB_REGNUM when none)
    uint32_t    reg_dwarf;      // DWARF register number (INVALID_NUB_REGNUM when none)
    uint32_t    reg_generic;    // Generic register number (INVALID_NUB_REGNUM when none)
    uint32_t    reg_debugserver;// The debugserver register number we'll use over gdb-remote protocol (INVALID_NUB_REGNUM when none)
    const char **value_regs;    // If this register is a part of other registers, list the register names terminated by NULL
    const char **update_regs;   // If modifying this register will invalidate other registers, list the register names terminated by NULL
};

struct DNBRegisterSetInfo
{
    const char *name;                           // Name of this register set
    const struct DNBRegisterInfo *registers;    // An array of register descriptions
    nub_size_t num_registers;                   // The number of registers in REGISTERS array above
};

#ifdef __cplusplus
}
#endif

#endif    // #ifndef __DNBDefs_h__
