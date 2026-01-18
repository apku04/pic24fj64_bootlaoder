/*
 * Bootloader Header
 * 
 * USB CDC Bootloader for PIC24FJ64GB002
 */

#ifndef BOOTLOADER_H
#define BOOTLOADER_H

#include <stdint.h>
#include <stdbool.h>
#include "mcc_generated_files/memory/flash.h"

// Bootloader commands (received via USB CDC)
#define CMD_READ_VERSION    'V'     // Read bootloader version
#define CMD_READ_FLASH      'R'     // Read flash memory
#define CMD_WRITE_FLASH     'W'     // Write flash memory
#define CMD_ERASE_FLASH     'E'     // Erase flash page
#define CMD_VERIFY          'C'     // Verify checksum
#define CMD_JUMP_APP        'J'     // Jump to application
#define CMD_RESET           'X'     // Reset device
#define CMD_HEX_RECORD      ':'     // Intel HEX record

// Response codes
#define RSP_OK              '+'
#define RSP_ERROR           '-'
#define RSP_UNKNOWN         '?'

// Application memory boundaries
// IVT area (0x0004-0x01FF) is also writable for app's interrupt vectors
#define IVT_START_ADDRESS       0x0004UL    // Hardware IVT location
#define IVT_END_ADDRESS         0x01FFUL    // End of AIVT
#define APP_START_ADDRESS       0x4000UL    // Application code starts after bootloader
#define APP_END_ADDRESS         0xABFEUL    // Leave space for config
#define BOOTLOADER_END_ADDRESS  0x3FFFUL

// Buffer sizes
#define RX_BUFFER_SIZE      128
#define HEX_LINE_MAX        80

// Bootloader state
typedef enum {
    BL_STATE_IDLE,
    BL_STATE_RECEIVING_HEX,
    BL_STATE_PROGRAMMING,
    BL_STATE_VERIFYING,
    BL_STATE_COMPLETE,
    BL_STATE_ERROR
} BootloaderState_t;

// Jump diagnostics (persistent across RESET, cleared by bootloader on entry).
// If the bootloader sets blJumpAttempted and then returns after a reset, it
// implies the application crashed/reset shortly after the jump.
#define BL_JUMP_ATTEMPT_MAGIC  0xB00BU
extern volatile uint16_t blJumpAttempted;
extern volatile uint16_t blJumpReturnCount;

// Reset-to-app handoff marker. The bootloader sets this before issuing RESET,
// then early bootloader startup will honor it by jumping to the application.
#define BL_JUMP_MAGIC_VALUE 0xB007U
extern volatile uint16_t blJumpMagic;

// Captured RCON value from boot (persistent). Useful to see if we reset due to
// BOR/POR/WDTO/TRAPR/etc.
extern volatile uint16_t blLastRcon;

// Captured RCON value at C entry (before main() clears RCON bits).
extern volatile uint16_t blRconAtEntry;

// Reset-stub entry marker (see main.c/reset_stub.s).
extern volatile uint16_t blSawResetStubMagic;

// Counts how many times the reset stub actually took the jump-to-app path.
extern volatile uint16_t blStubToAppCount;

// Last received command (ASCII) + monotonic counter (both persistent).
extern volatile uint16_t blLastCmd;
extern volatile uint16_t blCmdCount;

// Shared app fault diagnostics (written by app, read by bootloader after reset)
extern volatile uint16_t appTrapCode;
extern volatile uint16_t appTrapCount;
extern volatile uint16_t appTrapIntcon1;
extern volatile uint16_t appTrapRcon;
extern volatile uint16_t appBootCount;
extern volatile uint16_t appStage;
extern volatile uint16_t appLastRcon;
// Intel HEX record types
typedef enum {
    HEX_DATA_RECORD = 0x00,
    HEX_EOF_RECORD = 0x01,
    HEX_EXT_SEG_ADDR = 0x02,
    HEX_START_SEG_ADDR = 0x03,
    HEX_EXT_LINEAR_ADDR = 0x04,
    HEX_START_LINEAR_ADDR = 0x05
} HexRecordType_t;

// Function prototypes
void Bootloader_Initialize(void);
void Bootloader_ProcessCommand(void);
bool Bootloader_ShouldJumpToApp(void);
void Bootloader_ClearHostActivity(void);
bool Bootloader_HadHostActivity(void);
void Bootloader_SendResponse(char code, const char* message);
void Bootloader_SendVersion(void);

// Flash programming functions
bool Bootloader_EraseAppArea(void);
bool Bootloader_WriteFlash(uint32_t address, uint8_t* data, uint16_t length);
bool Bootloader_VerifyFlash(uint32_t address, uint8_t* data, uint16_t length);

// Intel HEX parsing
bool Bootloader_ParseHexLine(const char* line);
uint8_t Bootloader_HexToByte(const char* hex);

// Simple busy-wait delay (approximate ms at 16 MIPS)
// Note: This is approximate and does not account for interrupt latency
static inline void Bootloader_DelayMs(uint16_t ms)
{
    // At 16 MIPS (32 MHz / 2), one instruction cycle = 62.5 ns
    // For 1 ms we need approximately 16000 instruction cycles
    // A simple loop iteration takes about 3 cycles, so ~5333 iterations per ms
    volatile uint32_t count;
    while (ms--)
    {
        count = 5333;
        while (count--);
    }
}

#endif // BOOTLOADER_H
