$XC16Path = "C:\Program Files\Microchip\xc16\v2.10\bin"
$ScriptDir = $PSScriptRoot
$BuildDir = Join-Path $ScriptDir "build\default\production"

$src = Get-Item "$ScriptDir\mcc_generated_files\memory\flash.s"
$objDir = Join-Path $BuildDir "mcc_generated_files\memory"
$objPath = Join-Path $objDir "flash.o"

Write-Host "Source: $($src.FullName)"
Write-Host "Output: $objPath"

New-Item -ItemType Directory -Force -Path $objDir | Out-Null

$result = & "$XC16Path\xc16-gcc.exe" -c -mcpu=24FJ64GB002 -omf=elf -o "$objPath" "$($src.FullName)" 2>&1
Write-Host "Result: $result"
Write-Host "Exit: $LASTEXITCODE"
Write-Host "Exists: $(Test-Path $objPath)"
