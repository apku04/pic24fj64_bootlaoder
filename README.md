# PIC24FJ64GB002 USB CDC Bootloader

A USB CDC bootloader for PIC24FJ64GB002 microcontroller that allows firmware updates via virtual COM port.

## Features

- USB CDC (Virtual COM Port) interface - no special drivers needed
- Intel HEX file upload support
- Application area: 0x4000 - 0xA9FF (~27KB)
- Bootloader size: ~11KB
- IVT/AIVT trampoline forwarding to application
- Reset-based handoff to application
- 15-second entry window on power-up

## Quick Start

### Prerequisites

- **XC16 v2.10** compiler: `C:\Program Files\Microchip\xc16\v2.10`
- **MPLAB X v5.50+** (for building and programming)
- **Python 3.x** with pyserial: `pip install pyserial`
- **Microchip Real ICE** or compatible programmer

### Build Bootloader

**Using MPLAB X (Recommended):**
1. Open `bootloader.X` project in MPLAB X
2. Build → Make and Program Device Main Project
3. Or just Build (Production) then use program.ps1

**Command Line (Alternative):**
```powershell
cd bootloader.X
powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

### Program Bootloader

**Using MPLAB X:**
- Click "Make and Program Device Main Project" button

**Using Command Line (after MPLAB X build):**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\program.ps1 -HexFile "dist\default\production\bootloader.X.production.hex"
```

### Upload Application via USB

After bootloader is programmed, connect USB. Device enumerates as CDC COM port.

```powershell
python tools/upload_firmware.py --port COM10 path/to/your/app.hex
```

## Memory Map

```
Flash Memory (0x0000 - 0xABFF):
┌─────────────────────────────────────┐
│ 0x0000-0x0003  Reset Vector         │ → Bootloader reset stub
│ 0x0004-0x00FF  IVT (trampolines)    │ → Forwards to app IVT
│ 0x0104-0x01FF  AIVT (trampolines)   │ → Forwards to app AIVT
│ 0x0200-0x3FFF  Bootloader Code      │ ~15KB
├─────────────────────────────────────┤
│ 0x4000-0x4003  App Reset Vector     │
│ 0x4004-0x41FB  App IVT              │ 126 vectors × 4 bytes
│ 0x4204-0x43FB  App AIVT             │ 126 vectors × 4 bytes
│ 0x4400-0xA9FF  App Code             │ ~26KB
└─────────────────────────────────────┘

Data RAM (0x0800 - 0x27FF):
┌─────────────────────────────────────┐
│ 0x0800-0x0BFF  USB BDT + Buffers    │ 1KB
│ 0x0C00-0x11FF  General RAM          │
│ 0x1200-0x123F  Bootloader Persist   │ Survives reset
│ 0x1280-0x27FF  App RAM              │
└─────────────────────────────────────┘
```

## Bootloader Protocol

Commands (send via CDC, terminated with `\r\n`):

| Command | Description | Response |
|---------|-------------|----------|
| `V` | Get version | `PIC24 Bootloader v1.0` |
| `E` | Erase app area | `+Erased` |
| `:...` | Intel HEX record | `+` or `-error` |
| `C` | Verify/complete | `+OK: n bytes, n pages` |
| `J` | Jump to application | `+Jumping...` |
| `X` | Reset device | `+Resetting...` |

## Upload Tool Usage

```bash
# Basic upload with auto-jump
python tools/upload_firmware.py --port COM10 app.hex

# Upload without jumping to app
python tools/upload_firmware.py --port COM10 app.hex --no-jump

# Auto-detect COM port
python tools/upload_firmware.py app.hex
```

## LED Indicators

| State | LED_A (RA2) | LED_B (RB14) |
|-------|-------------|--------------|
| Bootloader starting | Blinking | Blinking |
| USB Configured | Solid ON | Solid ON |
| Waiting for USB | Blinking | Based on state |

## Building Compatible Applications

Applications must use a custom linker script with:
- Reset vector at **0x4000**
- IVT at **0x4004** (126 vectors × 4 bytes = 0x1F8)
- AIVT at **0x4204** (126 vectors × 4 bytes = 0x1F8)  
- Code starting at **0x4400**
- **No config bits** (bootloader owns them)

See the `com.X` project `bootloader_app` branch for a complete working example.

### Application Linker Script Key Points

```
MEMORY
{
  data    (a!xr) : ORIGIN = 0x800,  LENGTH = 0x2000
  reset          : ORIGIN = 0x4000, LENGTH = 0x4
  ivt            : ORIGIN = 0x4004, LENGTH = 0x1F8
  aivt           : ORIGIN = 0x4204, LENGTH = 0x1F8
  program (xr)   : ORIGIN = 0x4400, LENGTH = 0x65F8
}
```

### Application IVT Table

Use `.long` directive for each vector (4 bytes):
```asm
.section .ivt, code, keep
.rept 126
    .long __DefaultInterrupt
.endr
```

## Project Structure

```
bootloader.X/
├── src/
│   ├── bootloader.c/h    # Bootloader logic, HEX parsing
│   ├── main.c            # Entry point, USB handling  
│   ├── reset_stub.s      # Reset vector, app handoff
│   └── ivt_table.s       # IVT/AIVT trampolines
├── linker/
│   └── bootloader_p24FJ64GB002.gld
├── mcc_generated_files/
│   └── usb/              # MCC USB CDC stack
├── tools/
│   └── upload_firmware.py
├── build.ps1             # Command-line build
├── program.ps1           # Real ICE programming
└── README.md
```

## Troubleshooting

### No COM port after programming
- Check USB cable connection
- Verify 3.3V power to device
- Check oscillator config (FRC+PLL for 32MHz)

### Upload timeout errors
- Power cycle the device
- Close any other serial monitors
- Try a different USB port

### Application crashes after jump
- Verify IVT/AIVT addresses (0x4004/0x4204)
- Check that app doesn't define config bits
- Ensure reset vector is at 0x4000

## Hardware Requirements

- PIC24FJ64GB002 microcontroller
- USB connection (D+/D- to RB10/RB11)
- 3.3V power supply
- Optional: LEDs on RA2 and RB14 for status

## License

MIT License

## Changelog

### v1.0 (2026-01-18)
- Initial release
- USB CDC bootloader functional
- Intel HEX upload working  
- IVT/AIVT forwarding to app
- Reset-based application handoff
- Python upload tool included
