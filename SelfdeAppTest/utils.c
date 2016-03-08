//
//  utils.c
//  Selfde
//

#include "utils.h"
#include <stdio.h>

void *getTestFunctionAddress() {
    void (*ptr)() = &testFunction;
    return (void *)ptr;
}

void testFunction() {
    printf("Inner test code!\n");
}
