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

# Get a FileInfo object
$src = Get-Item "$ScriptDir\src\bootloader.c"

$relPath = $src.FullName.Replace($ScriptDir + "\", "")
$objSubDir = Split-Path $relPath -Parent
$objDir = Join-Path $BuildDir $objSubDir
$objPath = Join-Path $objDir ($src.BaseName + ".o")

New-Item -ItemType Directory -Force -Path $objDir | Out-Null

Write-Host "Source FullName: $($src.FullName)"
Write-Host "objPath: $objPath"
Write-Host "CFLAGS: $CFLAGS"

# Try with $src.FullName
$null = & "$XC16Path\xc16-gcc.exe" $CFLAGS -o "$objPath" "$($src.FullName)" 2>&1

Write-Host "Exists: $(Test-Path $objPath)"
