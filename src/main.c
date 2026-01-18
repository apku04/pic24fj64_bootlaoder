/*
 * PIC24FJ64GB002 USB CDC Bootloader - Interrupt Mode
 * 
 * USB is handled by interrupt (USB_INTERRUPT mode defined in usb_device_config.h)
 * This matches the working com.X project configuration.
 */

#include "mcc_generated_files/mcc.h"
#include "mcc_generated_files/usb/usb.h"
#include "mcc_generated_files/tmr1.h"
#include "bootloader.h"
#include <string.h>

#define APP_START_ADDRESS       0x4000UL    // Application starts after bootloader
#define APP_RESET_ADDRESS       (APP_START_ADDRESS)

// Handoff + diagnostics: must survive RESET, but must NOT live in USB BDT RAM.
// We place these into a dedicated NOLOAD section mapped into normal data RAM.
volatile uint16_t blJumpMagic __attribute__((persistent, section(".bl_persist")));

// Diagnostics: track whether we attempted to jump and came back.
volatile uint16_t blJumpAttempted __attribute__((persistent, section(".bl_persist")));
volatile uint16_t blJumpReturnCount __attribute__((persistent, section(".bl_persist")));

// Last reset cause (RCON) captured at boot.
volatile uint16_t blLastRcon __attribute__((persistent, section(".bl_persist")));

// RCON snapshot captured at C entry before clearing RCON bits.
volatile uint16_t blRconAtEntry __attribute__((persistent, section(".bl_persist")));

// Set by reset stub on *any* reset; cleared by main() on entry.
// If the bootloader is (incorrectly) entered without a reset, this will remain 0.
volatile uint16_t blResetStubMagic __attribute__((persistent, section(".bl_persist")));
volatile uint16_t blSawResetStubMagic __attribute__((persistent, section(".bl_persist")));

volatile uint16_t blStubToAppCount __attribute__((persistent, section(".bl_persist")));

// Runtime flag used by the IVT trampoline:
// 0 = bootloader is active (handle bootloader USB/ISRs)
// 1 = application is running (forward vectors to relocated app IVT/AIVT)
volatile uint16_t blVectorToApp __attribute__((persistent, section(".bl_persist")));

// Application fault diagnostics (shared with app via fixed RAM address window).
volatile uint16_t appTrapCode __attribute__((persistent, section(".app_persist"), aligned(0x80)));
volatile uint16_t appTrapCount __attribute__((persistent, section(".app_persist")));
volatile uint16_t appTrapIntcon1 __attribute__((persistent, section(".app_persist")));
volatile uint16_t appTrapRcon __attribute__((persistent, section(".app_persist")));
volatile uint16_t appBootCount __attribute__((persistent, section(".app_persist")));
volatile uint16_t appStage __attribute__((persistent, section(".app_persist")));
volatile uint16_t appLastRcon __attribute__((persistent, section(".app_persist")));

// Time window after reset where the bootloader stays active so the host can
// connect and start an upload. If no USB CDC RX activity occurs, we jump to the app.
#define BOOTLOADER_ENTRY_WINDOW_MS  15000U

// TMR1 is configured by MCC to overflow every ~30ms (PR1=60000, FOSC/2=16MHz, prescale 1:8)
#define TMR1_OVERFLOW_MS            30U

typedef void (*APP_ENTRY_POINT)(void);

static bool IsValidApplication(void)
{
    uint32_t resetVector = FLASH_ReadWord24(APP_RESET_ADDRESS);
    return !(resetVector == 0xFFFFFF || resetVector == 0x000000);
}

static void JumpToApplication(void)
{
    __builtin_disi(0x3FFF);  // Disable interrupts
    USBDeviceDetach();
    
    // Wait for USB to detach
    volatile uint32_t i;
    for (i = 0; i < 100000; i++);
    
    // Disable peripherals
    T1CONbits.TON = 0;
    T2CONbits.TON = 0;
    SPI1STATbits.SPIEN = 0;
    
    // Clear all interrupt flags and disable all interrupts
    IFS0 = 0; IFS1 = 0; IFS2 = 0; IFS3 = 0; IFS4 = 0; IFS5 = 0;
    IEC0 = 0; IEC1 = 0; IEC2 = 0; IEC3 = 0; IEC4 = 0; IEC5 = 0;
    
    // Jump to application reset vector using assembly GOTO
    asm("goto 0x4000");
}

static void ResetToApplication(void)
{
    blJumpMagic = BL_JUMP_MAGIC_VALUE;
    asm("RESET");
}

// Simple delay (no USB polling needed in interrupt mode)
static void SimpleDelay(uint32_t count)
{
    volatile uint32_t d;
    for (d = 0; d < count; d++);
}

static void Bootloader_EntryWindow(uint16_t windowMs)
{
    uint16_t periods = (windowMs + (TMR1_OVERFLOW_MS - 1U)) / TMR1_OVERFLOW_MS;

    // Ensure TMR1 interrupt is off (bootloader does polling).
    IEC0bits.T1IE = 0;

    for (uint16_t i = 0; i < periods; i++)
    {
        IFS0bits.T1IF = 0;
        TMR1 = 0;

        while (!IFS0bits.T1IF)
        {
            USBDeviceTasks();

            if (USBGetDeviceState() >= CONFIGURED_STATE)
            {
                if (!USBIsDeviceSuspended())
                {
                    Bootloader_ProcessCommand();
                }
            }

            if (Bootloader_HadHostActivity())
            {
                return;
            }
        }
    }
}

int main(void)
{
    // Bootloader mode - IVT forwards to bootloader ISRs
    blVectorToApp = 0;
    
    // All pins digital first
    AD1PCFG = 0xFFFF;
    
    // LED setup
    TRISAbits.TRISA2 = 0;
    TRISBbits.TRISB14 = 0;
    LATAbits.LATA2 = 1;
    LATBbits.LATB14 = 0;
    
    // Initialize only what we need for USB CDC bootloader
    // Skip SPI1, TMR2, EXT_INT, TMR1 - they cause crashes with BOOTLOADER macro
    PIN_MANAGER_Initialize();
    CLOCK_Initialize();
    INTERRUPT_Initialize();
    USBDeviceInit();
    USBDeviceAttach();
    
    // Initialize bootloader
    Bootloader_Initialize();
    Bootloader_ClearHostActivity();
    
    LATBbits.LATB14 = 1;
    
    uint32_t counter = 0;
    uint8_t usbState = 0;
    
    while(1)
    {
        usbState = USBGetDeviceState();
        
        if (usbState >= CONFIGURED_STATE)
        {
            LATAbits.LATA2 = 1;
            LATBbits.LATB14 = 1;
            
            if (!USBIsDeviceSuspended())
            {
                Bootloader_ProcessCommand();
                CDCTxService();  // Ensure TX data is sent
            }
        }
        else
        {
            counter++;
            if (counter > 50000)
            {
                counter = 0;
                LATAbits.LATA2 = !LATAbits.LATA2;
            }
        }
        
        if (Bootloader_ShouldJumpToApp())
        {
            ResetToApplication();
        }
    }
    return 0;
}