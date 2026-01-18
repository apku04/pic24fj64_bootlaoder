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
 *
 * CRITICAL: On Power-On Reset (POR), RAM contents are UNDEFINED.
 * We MUST check RCON.POR and always go to bootloader on fresh power-up.
 */

    .equ    RCON, 0x0740        ; RCON register address
    .equ    POR_BIT, 0          ; POR is bit 0 of RCON
    .equ    AD1PCFG, 0x032C     ; Analog/Digital config
    .equ    TRISA, 0x02C0       ; TRISA register
    .equ    LATA, 0x02C4        ; LATA register

    .section .text.reset_stub, code
    .global __reset_stub
__reset_stub:
    ; *** DEBUG: Toggle LED immediately to prove we're executing ***
    setm    AD1PCFG             ; All pins digital
    bclr    TRISA, #2           ; RA2 = output
    bset    LATA, #2            ; RA2 = HIGH (LED ON)

    ; Capture reset cause as early as possible (before CRT can touch RCON).
    mov     RCON, w2
    mov     w2, _blLastRcon

    ; Mark that we entered through the reset stub (i.e., this was a true reset).
    mov     #0xCAFE, w0
    mov     w0, _blResetStubMagic

    ; **CRITICAL**: On Power-On Reset (POR), RAM is undefined!
    ; Always go to bootloader on POR regardless of blJumpMagic value.
    btsc    w2, #POR_BIT        ; Skip next instruction if POR bit is CLEAR
    bra     __bootloader_reset  ; POR bit SET = fresh power-up, go to bootloader

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
    ; CRITICAL: Clear blVectorToApp so IVT forwards to bootloader ISRs (not app)
    clr     _blVectorToApp
    ; Jump to the C Runtime startup (not hardcoded address)
    goto    __reset

    .end
