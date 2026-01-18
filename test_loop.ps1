$ErrorActionPreference = "Continue"
$XC16Path = "C:\Program Files\Microchip\xc16\v2.10\bin"
$MCU = "24FJ64GB002"
$ScriptDir = $PSScriptRoot
$BuildDir = Join-Path $ScriptDir "build\default\production"

$CFLAGS = @(
    "-mcpu=$MCU",
    "-c",
    "-omf=elf",
    "-legacy-libc",
    "-Os",
    "-DBOOTLOADER",
    "-Wall",
    "-I`"$ScriptDir`"",
    "-I`"$ScriptDir\src`"",
    "-I`"$ScriptDir\mcc_generated_files`"",
    "-I`"$ScriptDir\mcc_generated_files\memory`""
)

$SrcDirs = @("src", "mcc_generated_files", "mcc_generated_files\memory", "mcc_generated_files\usb")

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

Write-Host "Found $($SourceFiles.Count) files"

$success = 0
$fail = 0

foreach ($src in $SourceFiles) {
    $relPath = $src.FullName.Replace($ScriptDir + "\", "")
    $objSubDir = Split-Path $relPath -Parent
    $objDir = Join-Path $BuildDir $objSubDir
    $objPath = Join-Path $objDir ($src.BaseName + ".o")

    if (-not (Test-Path $objDir)) {
        New-Item -ItemType Directory -Force -Path $objDir | Out-Null
    }

    if ($src.Extension -eq ".s") {
        $null = & "$XC16Path\xc16-gcc.exe" -c "-mcpu=$MCU" -omf=elf -o "$objPath" "$($src.FullName)" 2>&1
    } else {
        $null = & "$XC16Path\xc16-gcc.exe" $CFLAGS -o "$objPath" "$($src.FullName)" 2>&1
    }
    
    Start-Sleep -Milliseconds 50
    
    if (Test-Path $objPath) {
        $success++
    } else {
        Write-Host "FAIL: $relPath"
        $fail++
    }
}

Write-Host "Success: $success, Fail: $fail"
