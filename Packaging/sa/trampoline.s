// SkyRose scripting addition: the code the loader copies into the Dock (arm64e).
//
// It starts as a bare Mach thread (no pthread, no TSD), so it only does two things:
//   1. pthread_create_from_mach_thread(&t, NULL, start, data), with `start` signed here, inside
//      the Dock, so libpthread's authenticated call (blraaz) accepts it;
//   2. sets `done` and spins until the loader terminates it.
// The pthread then dlopen()s the payload and calls its `skyrose_sa_start` (an authenticated
// pointer from dlsym, called with blraaz).
//
// x0 on entry = the data block (a separate read-write page) written by the loader:
//   +0  pthread_create_from_mach_thread   +8  dlopen   +16 dlsym
//   +24 pthread_t storage                 +32 done flag (set to 1)
//   +40 symbol name (40 bytes)            +80 payload path (NUL-terminated)

    .text
    .p2align 2
    .globl _skyrose_sa_trampoline_start
    .globl _skyrose_sa_trampoline_end

_skyrose_sa_trampoline_start:
    mov     x20, x0
    add     x0, x20, #24
    mov     x1, #0
    adr     x2, Lpthread_start
    paciza  x2
    mov     x3, x20
    ldr     x9, [x20, #0]
    blr     x9
    mov     w9, #1
    str     w9, [x20, #32]
Lspin:
    b       Lspin

Lpthread_start:
    pacibsp
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]
    mov     x29, sp
    mov     x20, x0
    add     x0, x20, #80
    mov     x1, #2                  // RTLD_NOW
    ldr     x9, [x20, #8]
    blr     x9
    cbz     x0, Ldone
    add     x1, x20, #40
    ldr     x9, [x20, #16]
    blr     x9
    cbz     x0, Ldone
    blraaz  x0
Ldone:
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    retab

_skyrose_sa_trampoline_end:
    nop
