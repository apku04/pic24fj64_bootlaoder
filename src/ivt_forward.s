/*
 * IVT Forwarder Stubs for PIC24FJ64GB002 bootloader.
 *
 * When blVectorToApp = 0 (bootloader mode): dispatch to bootloader handlers
 * When blVectorToApp = 1 (app mode): forward to application's IVT at 0x4004
 *
 * Application IVT is at 0x4004 (APP_IVT_BASE).
 * Each vector entry is 2 instruction words (4 bytes in program memory address space).
 * Vector n is at: APP_IVT_BASE + (n * 2) in PC address units.
 */

    .equ APP_IVT_BASE,   0x4004
    .equ APP_AIVT_BASE,  0x4204

    ; External references
    .extern _blVectorToApp
    .extern __USB1Interrupt

    .section .text

;------------------------------------------------------------------------------
; Default ISR for bootloader mode - clears all flags and returns
;------------------------------------------------------------------------------
    .global __bl_default_isr
    .weak   __bl_default_isr
__bl_default_isr:
    clr     IFS0
    clr     IFS1
    clr     IFS2
    clr     IFS3
    clr     IFS4
    clr     IFS5
    retfie

;------------------------------------------------------------------------------
; IVT Forwarders
;------------------------------------------------------------------------------

; Vector 1: OscillatorFail
    .global __bl_fwd_ivt_1
__bl_fwd_ivt_1:
    btsc    _blVectorToApp, #0
    goto    APP_IVT_BASE + (1 * 2)
    goto    __bl_default_isr

; Vector 2: AddressError
    .global __bl_fwd_ivt_2
__bl_fwd_ivt_2:
    btsc    _blVectorToApp, #0
    goto    APP_IVT_BASE + (2 * 2)
    goto    __bl_default_isr

; Vector 3: StackError
    .global __bl_fwd_ivt_3
__bl_fwd_ivt_3:
    btsc    _blVectorToApp, #0
    goto    APP_IVT_BASE + (3 * 2)
    goto    __bl_default_isr

; Vector 4: MathError
    .global __bl_fwd_ivt_4
__bl_fwd_ivt_4:
    btsc    _blVectorToApp, #0
    goto    APP_IVT_BASE + (4 * 2)
    goto    __bl_default_isr

; Vector 11: Timer1 (bootloader uses this for timeout)
    .global __bl_fwd_ivt_11
__bl_fwd_ivt_11:
    btsc    _blVectorToApp, #0
    goto    APP_IVT_BASE + (11 * 2)
    goto    __bl_default_isr           ; Bootloader polls T1IF, doesn't use ISR

; Vector 15: Timer2 (app uses this)
    .global __bl_fwd_ivt_15
__bl_fwd_ivt_15:
    btsc    _blVectorToApp, #0
    goto    APP_IVT_BASE + (15 * 2)
    goto    __bl_default_isr

; Vector 28: INT1 (app uses this for LoRa DIO0)
    .global __bl_fwd_ivt_28
__bl_fwd_ivt_28:
    btsc    _blVectorToApp, #0
    goto    APP_IVT_BASE + (28 * 2)
    goto    __bl_default_isr

; Vector 86: USB1 (bootloader and app both use this)
    .global __bl_fwd_ivt_86
__bl_fwd_ivt_86:
    btsc    _blVectorToApp, #0
    goto    APP_IVT_BASE + (86 * 2)
    goto    __USB1Interrupt            ; Bootloader mode: use bootloader's USB ISR

;------------------------------------------------------------------------------
; AIVT Forwarders (same logic, forward to APP_AIVT_BASE)
;------------------------------------------------------------------------------

; AIVT Vector 1
    .global __bl_fwd_aivt_1
__bl_fwd_aivt_1:
    btsc    _blVectorToApp, #0
    goto    APP_AIVT_BASE + (1 * 2)
    goto    __bl_default_isr

; AIVT Vector 2
    .global __bl_fwd_aivt_2
__bl_fwd_aivt_2:
    btsc    _blVectorToApp, #0
    goto    APP_AIVT_BASE + (2 * 2)
    goto    __bl_default_isr

; AIVT Vector 3
    .global __bl_fwd_aivt_3
__bl_fwd_aivt_3:
    btsc    _blVectorToApp, #0
    goto    APP_AIVT_BASE + (3 * 2)
    goto    __bl_default_isr

; AIVT Vector 4
    .global __bl_fwd_aivt_4
__bl_fwd_aivt_4:
    btsc    _blVectorToApp, #0
    goto    APP_AIVT_BASE + (4 * 2)
    goto    __bl_default_isr

; AIVT Vector 11
    .global __bl_fwd_aivt_11
__bl_fwd_aivt_11:
    btsc    _blVectorToApp, #0
    goto    APP_AIVT_BASE + (11 * 2)
    goto    __bl_default_isr

; AIVT Vector 15
    .global __bl_fwd_aivt_15
__bl_fwd_aivt_15:
    btsc    _blVectorToApp, #0
    goto    APP_AIVT_BASE + (15 * 2)
    goto    __bl_default_isr

; AIVT Vector 28
    .global __bl_fwd_aivt_28
__bl_fwd_aivt_28:
    btsc    _blVectorToApp, #0
    goto    APP_AIVT_BASE + (28 * 2)
    goto    __bl_default_isr

; AIVT Vector 86
    .global __bl_fwd_aivt_86
__bl_fwd_aivt_86:
    btsc    _blVectorToApp, #0
    goto    APP_AIVT_BASE + (86 * 2)
    goto    __USB1Interrupt

    .end
