$ErrorActionPreference = "SilentlyContinue"

Get-Process -Name "whisper-server" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$targets = @(
    (Join-Path $env:USERPROFILE ".vscode\extensions\whisper_saver"),
    (Join-Path $env:USERPROFILE ".cursor\extensions\whisper_saver"),
    (Join-Path $env:USERPROFILE ".vscode\extensions\whisper-saver"),
    (Join-Path $env:USERPROFILE ".cursor\extensions\whisper-saver"),
    (Join-Path $env:USERPROFILE ".vscode\extensions\loken-token"),
    (Join-Path $env:USERPROFILE ".cursor\extensions\loken-token")
)

foreach ($t in $targets) {
    if (Test-Path $t) {
        Remove-Item $t -Recurse -Force
        Write-Host "Usunieto: $t" -ForegroundColor Yellow
    }
}

Write-Host "whisper_saver zostal odinstalowany." -ForegroundColor Green
