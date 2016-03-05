//
//  DNBRegisterInfoX86_64.hpp
//  Selfde
//

#ifndef DNBRegisterInfoX86_64_hpp
#define DNBRegisterInfoX86_64_hpp

#include "DNBDefs.h"
#include <mach/mach.h>

#if defined (__x86_64__)

#ifdef __cplusplus
extern "C" {
#endif

bool CPUHasAVX();
    
enum RegisterSetKindX86_64 {
    GPRKindX86_64,
    FPUKindX86_64,
    EXCKindX86_64,
    InvalidRegisterKindX86_64
};

const struct DNBRegisterSetInfo *getRegisterSetInfoX86_64(nub_size_t *size);
enum RegisterSetKindX86_64 getRegisterSetKindX86_64(uint32_t setID);

bool getGPRValueX86_64(uint32_t registerID, const x86_thread_state64_t *state, uint8_t *destination, nub_size_t *size);
bool setGPRValueX86_64(uint32_t registerID, x86_thread_state64_t *state, const uint8_t *source, nub_size_t size);

bool getFPUValueX86_64(uint32_t registerID, const x86_float_state64_t *fpuState, const x86_avx_state64_t *avxState, uint8_t *destination, nub_size_t *size);
bool setFPUValueX86_64(uint32_t registerID, x86_float_state64_t *fpuState, x86_avx_state64_t *avxState, const uint8_t *source, nub_size_t size);

bool getEXCValueX86_64(uint32_t registerID, const x86_exception_state64_t *state, uint8_t *destination, nub_size_t *size);

void getRegisterContextX86_64(const x86_thread_state64_t *state, const x86_float_state64_t *fpuState, const x86_avx_state64_t *avxState, const x86_exception_state64_t *excState, uint8_t *destination, nub_size_t *size);
void setRegisterContextX86_64(x86_thread_state64_t *state, x86_float_state64_t *fpuState, x86_avx_state64_t *avxState, const uint8_t *source, nub_size_t size);
    
#ifdef __cplusplus
}
#endif

#endif

#endif
