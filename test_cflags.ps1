$XC16Path = "C:\Program Files\Microchip\xc16\v2.10\bin"
$MCU = "24FJ64GB002"
$ScriptDir = $PSScriptRoot
$BuildDir = Join-Path $ScriptDir "build\default\production\src"
$objPath = Join-Path $BuildDir "test.o"
$srcPath = Join-Path $ScriptDir "src\bootloader.c"

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

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

Write-Host "CFLAGS: $CFLAGS"
Write-Host "Compiling: $srcPath -> $objPath"

$null = & "$XC16Path\xc16-gcc.exe" $CFLAGS -o "$objPath" "$srcPath" 2>&1

Write-Host "Exists: $(Test-Path $objPath)"
