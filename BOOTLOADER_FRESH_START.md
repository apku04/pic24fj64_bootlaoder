# PIC24FJ64GB002 USB Bootloader - Fresh Start Plan

## Current Problem
- USB enumeration stuck at **ADDRESS_STATE** (state 5)
- Device gets USB address but fails SET_CONFIGURATION
- Working com.X project proves hardware is OK

## Root Cause Analysis
The issue is likely:
1. **Something different in our build** vs MPLAB X build
2. **Memory/linker issue** - USB buffers not properly aligned
3. **Compiler flags** difference between our build.ps1 and MPLAB X

## Fresh Start Approach

### Option 1: Use MPLAB X to Build Bootloader (Recommended)
Instead of custom build.ps1, create proper MPLAB X project:

1. **Create New Project in MPLAB X v5.50**
   - File → New Project → Microchip Embedded → Standalone Project
   - Device: PIC24FJ64GB002
   - Tool: Real ICE
   - Compiler: XC16 v2.10
   - Project Name: bootloader.X
   - Location: `E:\work\lorapic24_alpha\`

2. **Add MCC Generated Files**
   - Copy `mcc_generated_files` folder from com.X
   - Add all files to project

3. **Create Minimal Bootloader Source**
   - Single `main.c` with just USB CDC echo test first
   - No flash programming, no Intel HEX - just USB echo

4. **Build with MPLAB X**
   - This ensures correct linker script, memory allocation, compiler flags

### Option 2: Copy Working com.X Project
1. Copy entire com.X to bootloader.X
2. Strip out everything except USB CDC
3. Modify main.c to be bootloader
4. Build with MPLAB X

### Option 3: Debug Current Build
Compare our build output with MPLAB X build:
```powershell
# Build com.X with MPLAB X, get the build log
# Compare compiler flags, linker script, memory map
```

## Minimal Test Code (for fresh start)

```c
// Absolute minimal USB CDC test - just echo back data
#include "mcc_generated_files/mcc.h"
#include "mcc_generated_files/usb/usb.h"

int main(void)
{
    SYSTEM_Initialize();
    
    while(1)
    {
        USBDeviceTasks();  // If using polling mode
        
        if (USBGetDeviceState() >= CONFIGURED_STATE)
        {
            if (!USBIsDeviceSuspended())
            {
                uint8_t buf[64];
                uint8_t n = getsUSBUSART(buf, sizeof(buf));
                if (n > 0)
                {
                    // Echo back
                    if (USBUSARTIsTxTrfReady())
                    {
                        putUSBUSART(buf, n);
                    }
                }
                CDCTxService();
            }
        }
    }
}
```

## Key Differences to Check

### 1. Linker Script
- com.X uses: `p24FJ64GB002.gld` (standard)
- Our build uses: Same? Need to verify memory sections

### 2. Compiler Flags
com.X MPLAB X build likely uses:
```
-mcpu=24FJ64GB002 -omf=elf -legacy-libc -O1 -msmart-io=1 -msfr-warn=off
```

Our build.ps1 uses:
```
-mcpu=24FJ64GB002 -omf=elf -legacy-libc -Os -Wall
```

**Difference: -O1 vs -Os optimization!**

### 3. USB Buffer Alignment
USB buffers need special alignment. MPLAB X handles this via linker script sections.
Our custom build might not align buffers correctly.

### 4. Check usb_device.c for __attribute__ sections
```c
// These MUST be in correct memory sections
volatile BDT_ENTRY BDT[BDT_NUM_ENTRIES] __attribute__ ((aligned (512)));
```

## Recommended Fresh Start Steps

1. **Stop using custom build.ps1**
2. **Create MPLAB X project properly**
3. **Use MPLAB X to compile and verify USB works**
4. **Once USB works, then optimize build process if needed**

## Files to Keep
- `src/bootloader.c` - Bootloader logic (Intel HEX parser, flash programming)
- `src/bootloader.h` - Bootloader definitions
- `tools/bootloader_upload.py` - Python upload tool

## Files to Regenerate
- All `mcc_generated_files/` - Copy fresh from com.X
- `main.c` - Start minimal, add features one at a time

## Quick Test: Verify com.X Still Works
Before fresh start, confirm com.X USB still works:
```powershell
# Program com.X
cd E:\work\lorapic24_alpha\com.X
# Build with MPLAB X, then program
# Verify COM port appears
```

If com.X works → Hardware is fine, our bootloader build is the problem.
