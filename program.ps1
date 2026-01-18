# PIC24 Bootloader Programming Script
# Programs the bootloader using REAL ICE (MPLAB X v5.50)

param(
    [switch]$Verify,
    [string]$HexFile = "dist\default\production\bootloader.X.hex"
)

$ErrorActionPreference = "Stop"

# Configuration
$MCU = "24FJ64GB002"  # Without PIC prefix
$Tool = "PRICE"       # Real ICE short name for ipecmd (use -TPRICE)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FullHexPath = Join-Path $ScriptDir $HexFile

if (-not (Test-Path $FullHexPath)) {
    Write-Error "HEX file not found: $FullHexPath`nRun build.ps1 first."
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Programming PIC24 Bootloader" -ForegroundColor Cyan
Write-Host " Device: $MCU" -ForegroundColor Cyan
Write-Host " HEX: $FullHexPath" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Find ipecmd (MPLAB X v5.50)
$ipecmd = "C:\Program Files\Microchip\MPLABX\v5.50\mplab_platform\mplab_ipe\ipecmd.exe"
if (-not (Test-Path $ipecmd)) {
    Write-Error "MPLAB IPE not found at: $ipecmd"
    exit 1
}

# Build args for ipecmd
$args = @(
    "-P$MCU",
    "-T$Tool",
    "-F$FullHexPath",
    "-M",
    "-OL"
)

if ($Verify) {
    # ipecmd v5.50 uses -Y for verify (optional memory region)
    $args += "-Y"
}

Write-Host "`nProgramming..." -ForegroundColor Yellow
$output = & $ipecmd @args 2>&1
$exitCode = $LASTEXITCODE

if ($output) {
    $output | ForEach-Object { Write-Host $_ }
}

if ($exitCode -eq 0) {
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host " PROGRAMMING SUCCESSFUL" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    exit 0
}

if (($output | Out-String) -match 'Target device was not found.*VDD') {
    Write-Host "`nERROR: No VDD detected on target." -ForegroundColor Red
    Write-Host "- Power the target board first" -ForegroundColor Red
    Write-Host "- Verify ICSP cable orientation (Pin 1/MCLR)" -ForegroundColor Red
    Write-Host "- Ensure VDD is routed to the ICSP header" -ForegroundColor Red
}

Write-Host "`nProgramming failed!" -ForegroundColor Red
exit 1
