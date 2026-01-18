/*
 * Reset stub for PIC24FJ64GB002 bootloader.
 *
 * Purpose:
 * - On a bootloader-requested reset-to-app handoff (BL_JUMP_MAGIC_VALUE),
 *   jump to the application reset vector from true reset context.
 *
 * Rationale:
 * - Jumping to the application's reset vector from C (after the bootloader CRT
 *   has run) can leave CPU state in a way the app startup code doesn't expect.
 */

    .section .text.reset_stub, code
    .global __reset_stub
__reset_stub:
    ; Capture reset cause as early as possible (before CRT can touch RCON).
    mov     RCON, w2
    mov     w2, _blLastRcon

    ; Mark that we entered through the reset stub (i.e., this was a true reset).
    mov     #0xCAFE, w0
    mov     w0, _blResetStubMagic

    ; If blJumpMagic is set, clear markers and jump to app reset @ 0x4000
    mov     _blJumpMagic, w0
    mov     #0xB007, w1
    cp      w0, w1
    bra     nz, __bootloader_reset

    ; Track that we took the stub handoff path.
    mov     _blStubToAppCount, w3
    inc     w3, w3
    mov     w3, _blStubToAppCount

    ; Tell the IVT trampoline to forward vectors to the application.
    mov     #1, w0
    mov     w0, _blVectorToApp

    clr     _blJumpMagic

    goto    0x4000

__bootloader_reset:
    ; Normal bootloader reset path
    goto    0x200

    .end
