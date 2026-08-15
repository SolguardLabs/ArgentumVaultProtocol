$ErrorActionPreference = "Stop"
Set-Location (Resolve-Path "$PSScriptRoot\..")

$python = ".\.venv\Scripts\python.exe"
if (-not (Test-Path $python)) {
    py -3.12 -m venv .venv
}

& $python -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Get-ChildItem src -Recurse -Filter *.vy | ForEach-Object {
    Write-Host "compiling $($_.FullName)"
    & $python -m vyper -f abi $_.FullName *> $null
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

& $python -m pytest -q
exit $LASTEXITCODE
