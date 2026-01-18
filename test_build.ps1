$ErrorActionPreference = "Continue"
$XC16Path = "C:\Program Files\Microchip\xc16\v2.10\bin"
$MCU = "24FJ64GB002"
$ScriptDir = $PSScriptRoot
$BuildDir = Join-Path $ScriptDir "build\default\production"

$SrcDirs = @("src", "mcc_generated_files", "mcc_generated_files\memory", "mcc_generated_files\usb")

# Collect source files
$SourceFiles = @()
foreach ($dir in $SrcDirs) {
    $fullDir = Join-Path $ScriptDir $dir
    if (Test-Path $fullDir) {
        $cFiles = Get-ChildItem -Path $fullDir -Filter "*.c" -File
        $sFiles = Get-ChildItem -Path $fullDir -Filter "*.s" -File
        if ($cFiles) { $SourceFiles += $cFiles }
        if ($sFiles) { $SourceFiles += $sFiles }
    }
}

Write-Host "Found $($SourceFiles.Count) source files"

# Compile each
foreach ($src in $SourceFiles) {
    $relPath = $src.FullName.Replace($ScriptDir + "\", "")
    $objName = $src.BaseName + ".o"
    $objSubDir = Split-Path $relPath -Parent
    $objDir = Join-Path $BuildDir $objSubDir
    $objPath = Join-Path $objDir $objName

    if (-not (Test-Path $objDir)) {
        New-Item -ItemType Directory -Force -Path $objDir | Out-Null
    }

    if ($src.Extension -eq ".s") {
        Write-Host "ASM: $($src.FullName) -> $objPath"
        $null = & "$XC16Path\xc16-gcc.exe" -c -mcpu=$MCU -omf=elf -o "$objPath" "$($src.FullName)" 2>&1
    } else {
        Write-Host "C: $($src.Name)"
        $null = & "$XC16Path\xc16-gcc.exe" -c -mcpu=$MCU -omf=elf -legacy-libc -Os -DBOOTLOADER -Wall -I"$ScriptDir" -I"$ScriptDir\src" -I"$ScriptDir\mcc_generated_files" -o "$objPath" "$($src.FullName)" 2>&1
    }
    
    Start-Sleep -Milliseconds 50
    if (-not (Test-Path $objPath)) {
        Write-Host "  FAILED: $objPath not found"
    }
}
