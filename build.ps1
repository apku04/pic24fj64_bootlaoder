# PIC24 Bootloader Build Script
# Builds the USB CDC bootloader for PIC24FJ64GB002

param(
    [switch]$Clean,
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"

# Configuration
$ProjectName = "bootloader"
$XC16Path = "C:\Program Files\Microchip\xc16\v2.10\bin"
$MCU = "24FJ64GB002"
$OptLevel = "-Os"

# Paths
$ScriptDir = $PSScriptRoot
$BuildDir = Join-Path $ScriptDir "build\default\production"
$DistDir = Join-Path $ScriptDir "dist\default\production"

# Source directories
$SrcDirs = @("src", "mcc_generated_files", "mcc_generated_files\memory", "mcc_generated_files\usb")

# Compiler flags
$CFLAGS = @(
    "-mcpu=$MCU",
    "-c",
    "-omf=elf",
    "-legacy-libc",
    $OptLevel,
    "-DBOOTLOADER",
    "-Wall",
    "-I`"$ScriptDir`"",
    "-I`"$ScriptDir\src`"",
    "-I`"$ScriptDir\mcc_generated_files`"",
    "-I`"$ScriptDir\mcc_generated_files\memory`""
)

# Ensure XC16 is available
if (-not (Test-Path "$XC16Path\xc16-gcc.exe")) {
    Write-Error "XC16 compiler not found at: $XC16Path"
    exit 1
}

# Clean if requested
if ($Clean) {
    Write-Host "Cleaning build directories..." -ForegroundColor Yellow
    if (Test-Path $BuildDir) { Remove-Item -Recurse -Force $BuildDir }
    if (Test-Path $DistDir) { Remove-Item -Recurse -Force $DistDir }
    Write-Host "Clean complete." -ForegroundColor Green
    exit 0
}

# Create directories
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Building PIC24 USB Bootloader" -ForegroundColor Cyan
Write-Host " MCU: $MCU" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Collect source files
$SourceFiles = @()
foreach ($dir in $SrcDirs) {
    $fullDir = Join-Path $ScriptDir $dir
    if (Test-Path $fullDir) {
        $found = Get-ChildItem -Path $fullDir -Filter "*.c" -File
        if ($found) { $SourceFiles += $found }
        $found = Get-ChildItem -Path $fullDir -Filter "*.s" -File
        if ($found) { $SourceFiles += $found }
    }
}

if ($SourceFiles.Count -eq 0) {
    Write-Error "No source files found!"
    exit 1
}

Write-Host "`nCompiling $($SourceFiles.Count) source files..." -ForegroundColor Yellow

# Compile each source file
$ObjectFiles = @()
$CompileErrors = 0

foreach ($src in $SourceFiles) {
    $relPath = $src.FullName.Replace($ScriptDir + "\", "")
    $objSubDir = Split-Path $relPath -Parent
    $objDir = Join-Path $BuildDir $objSubDir
    $objPath = Join-Path $objDir ($src.BaseName + ".o")

    if (-not (Test-Path $objDir)) {
        New-Item -ItemType Directory -Force -Path $objDir | Out-Null
    }

    if ($Verbose) {
        Write-Host "  $relPath" -ForegroundColor Gray
    }

    if ($src.Extension -eq ".s") {
        $null = & "$XC16Path\xc16-gcc.exe" -c "-mcpu=$MCU" -omf=elf -o "$objPath" "$($src.FullName)" 2>&1
    } else {
        $null = & "$XC16Path\xc16-gcc.exe" $CFLAGS -o "$objPath" "$($src.FullName)" 2>&1
    }
    
    Start-Sleep -Milliseconds 50
    
    if (Test-Path $objPath) {
        $ObjectFiles += $objPath
    } else {
        Write-Host "  ERROR: $relPath" -ForegroundColor Red
        $CompileErrors++
    }
}

if ($CompileErrors -gt 0) {
    Write-Error "Compilation failed with $CompileErrors errors"
    exit 1
}

Write-Host "Compiled $($ObjectFiles.Count) objects" -ForegroundColor Green

# Link
Write-Host "`nLinking..." -ForegroundColor Yellow
$OutputElf = Join-Path $DistDir "$ProjectName.X.elf"
$OutputHex = Join-Path $DistDir "$ProjectName.X.hex"

# Use STANDARD linker script (same as com.X uses)
$LinkerScript = "C:\Program Files\Microchip\xc16\v2.10\support\PIC24F\gld\p24FJ64GB002.gld"
$linkArgs = @("-mcpu=$MCU", "-omf=elf", "-legacy-libc", "-o", $OutputElf)
$linkArgs += "-Wl,--script=`"$LinkerScript`",--heap=256,--stack=1024,--report-mem,--check-sections,--data-init,--pack-data,--handles,--no-gc-sections,--fill-upper=0,--stackguard=16,--no-force-link,--smart-io,-L`"$ScriptDir\linker`""
$linkArgs += $ObjectFiles

$linkResult = & "$XC16Path\xc16-gcc.exe" @linkArgs 2>&1

$linkResult | Select-String -Pattern "Total.*memory" | ForEach-Object {
    Write-Host "  $_" -ForegroundColor Gray
}

Start-Sleep -Milliseconds 100

if (-not (Test-Path $OutputElf)) {
    Write-Host "Link failed!" -ForegroundColor Red
    $linkResult | ForEach-Object { Write-Host $_ }
    exit 1
}

Write-Host "Link successful" -ForegroundColor Green

# Generate HEX file
Write-Host "`nGenerating HEX file..." -ForegroundColor Yellow
$null = & "$XC16Path\xc16-bin2hex.exe" $OutputElf -a -omf=elf 2>&1

Start-Sleep -Milliseconds 100

if (Test-Path $OutputHex) {
    $hexSize = (Get-Item $OutputHex).Length
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host " BUILD SUCCESSFUL" -ForegroundColor Green
    Write-Host " Output: $OutputHex" -ForegroundColor Green
    Write-Host " Size: $hexSize bytes" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Error "HEX file not generated"
    exit 1
}
