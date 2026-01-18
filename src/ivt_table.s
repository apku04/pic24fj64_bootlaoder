/*
 * IVT/AIVT trampoline for PIC24FJ64GB002 bootloader.
 *
 * PIC24 IVT/AIVT entries are 2 instruction words each (a 2-word GOTO). The
 * hardware indexes vectors assuming this 2-word stride.
 *
 * Strategy:
 * - Each IVT/AIVT slot contains a 32-bit vector entry (.long) pointing to
 *   either a mode-aware forward stub (for key vectors) or to a safe default ISR.
 * - The forward stubs check blVectorToApp:
 *     0 => bootloader active: dispatch to bootloader handlers
 *     1 => application active: jump into relocated app IVT/AIVT entry
 */

    .equ APP_IVT_BASE,   0x4004
    .equ APP_AIVT_BASE,  0x4104
    .equ NUM_VECTORS,    126

    .global __bl_fwd_ivt_1
    .global __bl_fwd_ivt_2
    .global __bl_fwd_ivt_3
    .global __bl_fwd_ivt_4
    .global __bl_fwd_ivt_11
    .global __bl_fwd_ivt_15
    .global __bl_fwd_ivt_28
    .global __bl_fwd_ivt_86

    .global __bl_fwd_aivt_1
    .global __bl_fwd_aivt_2
    .global __bl_fwd_aivt_3
    .global __bl_fwd_aivt_4
    .global __bl_fwd_aivt_11
    .global __bl_fwd_aivt_15
    .global __bl_fwd_aivt_28
    .global __bl_fwd_aivt_86

    .section .text
    __bl_fwd_ivt_1:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __bl_default_isr
    1:
        goto    APP_IVT_BASE + (1 * 2)

    __bl_fwd_ivt_2:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __bl_default_isr
    1:
        goto    APP_IVT_BASE + (2 * 2)

    __bl_fwd_ivt_3:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __bl_default_isr
    1:
        goto    APP_IVT_BASE + (3 * 2)

    __bl_fwd_ivt_4:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __bl_default_isr
    1:
        goto    APP_IVT_BASE + (4 * 2)

    __bl_fwd_ivt_11:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __T1Interrupt
    1:
        goto    APP_IVT_BASE + (11 * 2)

    __bl_fwd_ivt_15:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __bl_default_isr
    1:
        goto    APP_IVT_BASE + (15 * 2)

    __bl_fwd_ivt_28:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __bl_default_isr
    1:
        goto    APP_IVT_BASE + (28 * 2)

    __bl_fwd_ivt_86:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __USB1Interrupt
    1:
        goto    APP_IVT_BASE + (86 * 2)

    __bl_fwd_aivt_1:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __bl_default_isr
    1:
        goto    APP_AIVT_BASE + (1 * 2)

    __bl_fwd_aivt_2:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __bl_default_isr
    1:
        goto    APP_AIVT_BASE + (2 * 2)

    __bl_fwd_aivt_3:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __bl_default_isr
    1:
        goto    APP_AIVT_BASE + (3 * 2)

    __bl_fwd_aivt_4:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __bl_default_isr
    1:
        goto    APP_AIVT_BASE + (4 * 2)

    __bl_fwd_aivt_11:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __T1Interrupt
    1:
        goto    APP_AIVT_BASE + (11 * 2)

    __bl_fwd_aivt_15:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __bl_default_isr
    1:
        goto    APP_AIVT_BASE + (15 * 2)

    __bl_fwd_aivt_28:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __bl_default_isr
    1:
        goto    APP_AIVT_BASE + (28 * 2)

    __bl_fwd_aivt_86:
        mov     _blVectorToApp, w0
        cp      w0, #1
        bra     z, 1f
        goto    __USB1Interrupt
    1:
        goto    APP_AIVT_BASE + (86 * 2)

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

    .end
