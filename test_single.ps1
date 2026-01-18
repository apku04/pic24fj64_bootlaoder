$XC16Path = "C:\Program Files\Microchip\xc16\v2.10\bin"
$ScriptDir = $PSScriptRoot
$BuildDir = Join-Path $ScriptDir "build\default\production\src"
$objPath = Join-Path $BuildDir "test.o"
$srcPath = Join-Path $ScriptDir "src\bootloader.c"

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

Write-Host "Compiling $srcPath"
Write-Host "Output: $objPath"

$output = & "$XC16Path\xc16-gcc.exe" -c -mcpu=24FJ64GB002 -omf=elf -legacy-libc -Os -DBOOTLOADER -Wall "-I$ScriptDir" "-I$ScriptDir\src" "-I$ScriptDir\mcc_generated_files" -o $objPath $srcPath 2>&1

Write-Host "Output: $output"
Write-Host "ExitCode: $LASTEXITCODE"
Write-Host "Exists: $(Test-Path $objPath)"
