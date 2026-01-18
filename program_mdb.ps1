# PIC24 Bootloader Programming Script using MDB
# More reliable with Real ICE than ipecmd

param(
    [string]$HexFile = "dist\default\production\bootloader.X.hex"
)

$ErrorActionPreference = "Stop"

# Check if MPLAB X IDE is running - it will block the Real ICE
$mplabProcess = Get-Process -Name "mplab_ide64" -ErrorAction SilentlyContinue
if ($mplabProcess) {
    Write-Host "ERROR: MPLAB X IDE is running (PID: $($mplabProcess.Id))" -ForegroundColor Red
    Write-Host "Close MPLAB X IDE first, or use it directly to program." -ForegroundColor Yellow
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FullHexPath = Join-Path $ScriptDir $HexFile

if (-not (Test-Path $FullHexPath)) {
    Write-Error "HEX file not found: $FullHexPath`nRun build.ps1 first."
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Programming PIC24 Bootloader (MDB)" -ForegroundColor Cyan  
Write-Host " HEX: $FullHexPath" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Find MDB
$mdbPath = "C:\Program Files\Microchip\MPLABX\v5.50\mplab_platform\bin\mdb.bat"
if (-not (Test-Path $mdbPath)) {
    Write-Error "MDB not found at: $mdbPath"
    exit 1
}

# Create MDB script - Older Real ICE cannot power target!
# Target board MUST be powered via USB or external supply BEFORE running this script
$mdbScript = @"
device PIC24FJ64GB002
hwtool RealICE
program "$FullHexPath"
quit
"@

$scriptFile = Join-Path $env:TEMP "mdb_program.txt"
$mdbScript | Out-File -FilePath $scriptFile -Encoding ASCII

Write-Host "`nRunning MDB..." -ForegroundColor Yellow
Write-Host "Script contents:" -ForegroundColor Gray
Get-Content $scriptFile | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
Write-Host ""

# Run MDB with script
try {
    $process = Start-Process -FilePath $mdbPath -ArgumentList $scriptFile -NoNewWindow -Wait -PassThru
    
    if ($process.ExitCode -eq 0) {
        Write-Host "`n========================================" -ForegroundColor Green
        Write-Host " PROGRAMMING SUCCESSFUL" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
    } else {
        Write-Host "`nProgramming may have failed (exit code: $($process.ExitCode))" -ForegroundColor Yellow
    }
} catch {
    Write-Host "`nError: $_" -ForegroundColor Red
}

# Cleanup
Remove-Item $scriptFile -ErrorAction SilentlyContinue
