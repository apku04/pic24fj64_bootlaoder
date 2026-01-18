/*
 * Bootloader Implementation
 * 
 * USB CDC Bootloader for PIC24FJ64GB002
 * Supports Intel HEX file format
 */

#include "bootloader.h"
#include "mcc_generated_files/mcc.h"
#include "mcc_generated_files/usb/usb.h"
#include "mcc_generated_files/usb/usb_device_cdc.h"
#include <string.h>
#include <stdio.h>

// Bootloader state
static BootloaderState_t blState = BL_STATE_IDLE;
static bool jumpToApp = false;
static uint32_t extendedAddress = 0;  // Extended address for Intel HEX
static volatile bool hostActivity = false;

// Receive buffer
static char rxBuffer[RX_BUFFER_SIZE];
static uint16_t rxIndex = 0;

// Flash write buffer (must be aligned for row writes)
static uint32_t flashBuffer[FLASH_WRITE_ROW_SIZE_IN_INSTRUCTIONS];
static uint32_t flashBufferAddress = 0xFFFFFFFF;
static uint16_t flashBufferIndex = 0;

// Statistics
static uint32_t bytesWritten = 0;
static uint32_t pagesErased = 0;

// Diagnostics (must survive RESET; placed in .bl_persist via bootloader linker script)
volatile uint16_t blLastCmd __attribute__((persistent, section(".bl_persist")));
volatile uint16_t blCmdCount __attribute__((persistent, section(".bl_persist")));

// Version string (single-line; host tools typically read only one line)
static const char VERSION_STRING[] = "BLv1.2";

// Forward declarations
static void ProcessLine(const char* line);
static void FlushFlashBuffer(void);
static bool IsAddressInAppArea(uint32_t address);
static void RequestResetToApplicationNow(void)
{
    // Mark that we are attempting a jump. If we ever come back to the
    // bootloader after this, blJumpReturnCount will increment on entry.
    blJumpAttempted = BL_JUMP_ATTEMPT_MAGIC;
    blJumpMagic = BL_JUMP_MAGIC_VALUE;

    // Best-effort USB detach so Windows sees a disconnect.
    __builtin_disi(0x3FFF);
    USBDeviceDetach();
    for (volatile uint32_t i = 0; i < 200000UL; i++) { ; }

    asm("RESET");
    while (1) { ; }
}

void Bootloader_Initialize(void)
{
    blState = BL_STATE_IDLE;
    jumpToApp = false;
    rxIndex = 0;
    extendedAddress = 0;
    flashBufferAddress = 0xFFFFFFFF;
    flashBufferIndex = 0;
    bytesWritten = 0;
    pagesErased = 0;
    
    // Unlock flash for programming
    FLASH_Unlock(FLASH_UNLOCK_KEY);
}

void Bootloader_ClearHostActivity(void)
{
    hostActivity = false;
}

bool Bootloader_HadHostActivity(void)
{
    return hostActivity;
}

void Bootloader_ProcessCommand(void)
{
    uint8_t numBytes;
    uint8_t readBuffer[64];
    
    // Check if data available from USB CDC
    numBytes = getsUSBUSART(readBuffer, sizeof(readBuffer));
    
    if (numBytes == 0)
    {
        return;
    }

    hostActivity = true;
    
    // Process received bytes
    for (uint8_t i = 0; i < numBytes; i++)
    {
        char c = (char)readBuffer[i];
        
        // Handle line endings
        if (c == '\r' || c == '\n')
        {
            if (rxIndex > 0)
            {
                rxBuffer[rxIndex] = '\0';
                ProcessLine(rxBuffer);
                rxIndex = 0;
            }
            continue;
        }
        
        // Store character in buffer
        if (rxIndex < RX_BUFFER_SIZE - 1)
        {
            rxBuffer[rxIndex++] = c;
        }
    }
    
    // Process USB CDC TX
    CDCTxService();
}

static void ProcessLine(const char* line)
{
    if (line[0] == '\0')
    {
        return;
    }
    
    char cmd = line[0];

    blLastCmd = (uint16_t)(uint8_t)cmd;
    blCmdCount++;
    
    switch (cmd)
    {
        case CMD_READ_VERSION:
            Bootloader_SendVersion();
            break;
            
        case CMD_ERASE_FLASH:
            // Erase application area
            if (Bootloader_EraseAppArea())
            {
                Bootloader_SendResponse(RSP_OK, "Erased\r\n");
                blState = BL_STATE_RECEIVING_HEX;
            }
            else
            {
                Bootloader_SendResponse(RSP_ERROR, "Erase failed\r\n");
                blState = BL_STATE_ERROR;
            }
            break;
            
        case CMD_HEX_RECORD:
            // Intel HEX record
            if (blState == BL_STATE_RECEIVING_HEX || blState == BL_STATE_IDLE)
            {
                blState = BL_STATE_RECEIVING_HEX;
                if (Bootloader_ParseHexLine(line))
                {
                    Bootloader_SendResponse(RSP_OK, "");
                }
                else
                {
                    Bootloader_SendResponse(RSP_ERROR, "HEX error\r\n");
                }
            }
            break;
            
        case CMD_VERIFY:
            // Flush any remaining data and verify
            FlushFlashBuffer();
            blState = BL_STATE_COMPLETE;
            {
                char msg[64];
                sprintf(msg, "OK: %lu bytes, %lu pages\r\n", bytesWritten, pagesErased);
                Bootloader_SendResponse(RSP_OK, msg);
            }
            break;
            
        case CMD_JUMP_APP:
            // Jump to application
            FlushFlashBuffer();
            Bootloader_SendResponse(RSP_OK, "Jumping...\r\n");
            Bootloader_DelayMs(100);  // Allow response to be sent
            RequestResetToApplicationNow();
            break;
            
        case CMD_RESET:
            // Reset device
            Bootloader_SendResponse(RSP_OK, "Resetting...\r\n");
            Bootloader_DelayMs(100);
            asm("RESET");
            break;
            
        default:
            Bootloader_SendResponse(RSP_UNKNOWN, "Unknown command\r\n");
            break;
    }
}

bool Bootloader_ShouldJumpToApp(void)
{
    return jumpToApp;
}

void Bootloader_SendResponse(char code, const char* message)
{
    char response[80];
    
    if (message[0] != '\0')
    {
        sprintf(response, "%c%s", code, message);
    }
    else
    {
        sprintf(response, "%c\r\n", code);
    }
    
    // Wait for USB to be ready
    while (!USBUSARTIsTxTrfReady())
    {
        CDCTxService();
    }
    
    putsUSBUSART(response);
    CDCTxService();
}

void Bootloader_SendVersion(void)
{
    char msg[128];
    // Single-line response so readline() gets all diagnostics.
    sprintf(
        msg,
        "%s SJ=%u JR=%u SR=%u BR=%04X AL=%04X AT=%u AS=%u\r\n",
        VERSION_STRING,
        (unsigned)blStubToAppCount,
        (unsigned)blJumpReturnCount,
        (unsigned)blSawResetStubMagic,
        (unsigned)blLastRcon,
        (unsigned)appLastRcon,
        (unsigned)appTrapCode,
        (unsigned)appStage
    );

    while (!USBUSARTIsTxTrfReady())
    {
        CDCTxService();
    }
    putsUSBUSART(msg);
    CDCTxService();
}

bool Bootloader_EraseAppArea(void)
{
    uint32_t address;
    
    pagesErased = 0;
    
    // Erase IVT/AIVT area first (for app's interrupt vectors)
    // Page containing 0x0000-0x01FF (but skip address 0 - reset vector points to bootloader)
    // Actually we need to be careful - don't erase the reset vector at 0x0000
    // The IVT starts at 0x0004, which is in the same page as reset
    // For safety, we'll erase starting from the page containing 0x0200
    // The IVT will be written directly without erasing (flash allows 1->0 writes)
    
    // Erase all pages in application area
    for (address = APP_START_ADDRESS; address < APP_END_ADDRESS; 
         address += FLASH_ERASE_PAGE_SIZE_IN_PC_UNITS)
    {
        if (!FLASH_ErasePage(address))
        {
            return false;
        }
        pagesErased++;
        
        // Keep USB alive during erase
        USBDeviceTasks();
    }
    
    return true;
}

static bool IsAddressInAppArea(uint32_t address)
{
    // Only allow writes to application code area (0x4000+)
    // Do NOT allow writes to IVT at 0x0004 - bootloader handles that via remapping
    return (address >= APP_START_ADDRESS && address <= APP_END_ADDRESS);
}

static void FlushFlashBuffer(void)
{
    if (flashBufferIndex > 0 && flashBufferAddress != 0xFFFFFFFF)
    {
        // Pad remaining buffer with 0xFF
        while (flashBufferIndex < FLASH_WRITE_ROW_SIZE_IN_INSTRUCTIONS)
        {
            flashBuffer[flashBufferIndex++] = 0x00FFFFFF;
        }
        
        // Write the row
        if (IsAddressInAppArea(flashBufferAddress))
        {
            FLASH_WriteRow24(flashBufferAddress, flashBuffer);
        }
        
        flashBufferIndex = 0;
        flashBufferAddress = 0xFFFFFFFF;
    }
}

uint8_t Bootloader_HexToByte(const char* hex)
{
    uint8_t value = 0;
    
    for (int i = 0; i < 2; i++)
    {
        value <<= 4;
        char c = hex[i];
        
        if (c >= '0' && c <= '9')
        {
            value |= (c - '0');
        }
        else if (c >= 'A' && c <= 'F')
        {
            value |= (c - 'A' + 10);
        }
        else if (c >= 'a' && c <= 'f')
        {
            value |= (c - 'a' + 10);
        }
    }
    
    return value;
}

bool Bootloader_ParseHexLine(const char* line)
{
    // Intel HEX format: :LLAAAATT[DD...]CC
    // LL = byte count
    // AAAA = address
    // TT = record type
    // DD = data bytes
    // CC = checksum
    
    if (line[0] != ':')
    {
        return false;
    }
    
    uint8_t byteCount = Bootloader_HexToByte(&line[1]);
    uint16_t address = (Bootloader_HexToByte(&line[3]) << 8) | Bootloader_HexToByte(&line[5]);
    uint8_t recordType = Bootloader_HexToByte(&line[7]);
    
    // Calculate checksum
    uint8_t checksum = byteCount + (address >> 8) + (address & 0xFF) + recordType;
    
    // Parse data bytes
    uint8_t data[64];
    for (uint8_t i = 0; i < byteCount; i++)
    {
        data[i] = Bootloader_HexToByte(&line[9 + i * 2]);
        checksum += data[i];
    }
    
    // Get expected checksum
    uint8_t expectedChecksum = Bootloader_HexToByte(&line[9 + byteCount * 2]);
    checksum = (~checksum) + 1;  // Two's complement
    
    if (checksum != expectedChecksum)
    {
        return false;  // Checksum error
    }
    
    // Process record type
    switch (recordType)
    {
        case HEX_DATA_RECORD:
        {
            // Calculate full 24-bit address
            // For PIC24, the HEX file address is in bytes, but we program in words
            // HEX address needs to be converted to program counter units
            uint32_t fullAddress = extendedAddress + address;
            
            // PIC24 uses 2 bytes per instruction word in HEX file
            // Convert byte address to PC address
            uint32_t pcAddress = fullAddress / 2;
            
            // Only program if in application area
            if (!IsAddressInAppArea(pcAddress))
            {
                return true;  // Skip but don't error
            }
            
            // Process data - PIC24 instructions are 24-bit (3 bytes in HEX = phantom + instruction)
            // HEX file format for PIC24: each instruction is 4 bytes (little endian, upper byte = 0)
            for (uint8_t i = 0; i < byteCount; i += 4)
            {
                if (i + 3 < byteCount)
                {
                    // Build 24-bit instruction word from 4 HEX bytes (little endian)
                    uint32_t instruction = data[i] | 
                                          ((uint32_t)data[i + 1] << 8) | 
                                          ((uint32_t)data[i + 2] << 16);
                    // data[i + 3] is phantom byte, ignore
                    
                    // Calculate word address
                    uint32_t wordAddr = pcAddress + (i / 2);
                    
                    // Align to row boundary
                    uint32_t rowAddress = wordAddr & ~(FLASH_WRITE_ROW_SIZE_IN_PC_UNITS - 1);
                    
                    // Check if we need to flush and start new row
                    if (flashBufferAddress != rowAddress)
                    {
                        FlushFlashBuffer();
                        flashBufferAddress = rowAddress;
                        flashBufferIndex = 0;
                        
                        // Initialize buffer with 0xFF
                        for (int j = 0; j < FLASH_WRITE_ROW_SIZE_IN_INSTRUCTIONS; j++)
                        {
                            flashBuffer[j] = 0x00FFFFFF;
                        }
                    }
                    
                    // Calculate index within row
                    uint16_t rowIndex = (wordAddr - rowAddress) / 2;
                    if (rowIndex < FLASH_WRITE_ROW_SIZE_IN_INSTRUCTIONS)
                    {
                        flashBuffer[rowIndex] = instruction;
                        if (rowIndex >= flashBufferIndex)
                        {
                            flashBufferIndex = rowIndex + 1;
                        }
                        bytesWritten += 3;
                    }
                }
            }
            break;
        }
        
        case HEX_EOF_RECORD:
            // End of file - flush buffer
            FlushFlashBuffer();
            blState = BL_STATE_COMPLETE;
            break;
            
        case HEX_EXT_LINEAR_ADDR:
            // Extended linear address record
            if (byteCount == 2)
            {
                extendedAddress = ((uint32_t)data[0] << 24) | ((uint32_t)data[1] << 16);
            }
            break;
            
        case HEX_EXT_SEG_ADDR:
            // Extended segment address record
            if (byteCount == 2)
            {
                extendedAddress = ((uint32_t)data[0] << 12) | ((uint32_t)data[1] << 4);
            }
            break;
            
        case HEX_START_LINEAR_ADDR:
        case HEX_START_SEG_ADDR:
            // Start address records - ignore for PIC24
            break;
            
        default:
            return false;
    }
    
    return true;
}

bool Bootloader_WriteFlash(uint32_t address, uint8_t* data, uint16_t length)
{
    // This function writes raw data to flash
    // Used for direct programming without HEX parsing
    
    if (!IsAddressInAppArea(address))
    {
        return false;
    }
    
    // Write word by word
    for (uint16_t i = 0; i < length; i += 4)
    {
        uint32_t word = data[i] | 
                       ((uint32_t)data[i + 1] << 8) | 
                       ((uint32_t)data[i + 2] << 16);
        
        if (!FLASH_WriteWord24(address + i, word))
        {
            return false;
        }
    }
    
    return true;
}

bool Bootloader_VerifyFlash(uint32_t address, uint8_t* data, uint16_t length)
{
    for (uint16_t i = 0; i < length; i += 4)
    {
        uint32_t expected = data[i] | 
                           ((uint32_t)data[i + 1] << 8) | 
                           ((uint32_t)data[i + 2] << 16);
        
        uint32_t actual = FLASH_ReadWord24(address + i);
        
        if (actual != expected)
        {
            return false;
        }
    }
    
    return true;
}
