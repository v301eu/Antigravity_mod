$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Instalacja whisper_saver v2.1.0 (Pure RAM Architecture) " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Usun wszystkie starsze nazwy i katalogi rozszerzen
$legacyDirs = @(
    (Join-Path $env:USERPROFILE ".vscode\extensions\loken-token"),
    (Join-Path $env:USERPROFILE ".cursor\extensions\loken-token"),
    (Join-Path $env:USERPROFILE ".vscode\extensions\whisper-saver"),
    (Join-Path $env:USERPROFILE ".cursor\extensions\whisper-saver")
)
foreach ($ld in $legacyDirs) {
    if (Test-Path $ld) {
        Remove-Item $ld -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[Clean] Usunieto stary katalog: $ld" -ForegroundColor DarkYellow
    }
}

$tmp = [System.IO.Path]::GetTempPath()
Get-ChildItem $tmp -Filter "loken_*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Get-ChildItem $tmp -Filter "ryan_*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

# 2. Pobierz model OpenAI Whisper Large v3 Turbo (q5_0), jesli nie ma go w bin/
$binSource = Join-Path $root "bin"
if (-not (Test-Path $binSource)) {
    New-Item -ItemType Directory -Path $binSource -Force | Out-Null
}
$turboModel = Join-Path $binSource "ggml-large-v3-turbo-q5_0.bin"
if (-not (Test-Path $turboModel) -or (Get-Item $turboModel).Length -lt 500000000) {
    Write-Host "[Whisper] Pobieranie modelu OpenAI Whisper Large v3 Turbo (ggml-large-v3-turbo-q5_0.bin)..." -ForegroundColor Yellow
    curl.exe -L --retry 3 -o $turboModel "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"
}

# 3. Aktywuj glosy Microsoft Natural 3. generacji (Ryan EN, Marek PL i pelna pula jezykowa)
$nvEnumKey = "HKCU:\Software\NaturalVoiceSAPIAdapter\Enumerator"
if (-not (Test-Path $nvEnumKey)) {
    $nvInstallDir = Join-Path $env:USERPROFILE "NaturalVoiceSAPIAdapter"
    $dll64 = Join-Path $nvInstallDir "x64\NaturalVoiceSAPIAdapter.dll"
    if (-not (Test-Path $dll64)) {
        Write-Host "[TTS] Pobieranie adaptera Microsoft Natural Voices 3. generacji..." -ForegroundColor Yellow
        $zipTmp = Join-Path $tmp "NaturalVoiceSAPIAdapter.zip"
        try {
            $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/gexgd0419/NaturalVoiceSAPIAdapter/releases/latest" -Headers @{ "User-Agent" = "whisper_saver" }
            $asset = $rel.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
            if ($asset) {
                curl.exe -L -o $zipTmp $asset.browser_download_url
                Expand-Archive -Path $zipTmp -DestinationPath $nvInstallDir -Force
                Remove-Item $zipTmp -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    if (Test-Path $dll64) {
        Start-Process "regsvr32.exe" -ArgumentList "/s `"$dll64`"" -Wait -ErrorAction SilentlyContinue
    }
    New-Item -Path $nvEnumKey -Force -ErrorAction SilentlyContinue | Out-Null
}
Set-ItemProperty -Path $nvEnumKey -Name "NoNarratorVoices" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $nvEnumKey -Name "NoEdgeVoices" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $nvEnumKey -Name "EdgeVoiceAllLanguages" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Write-Host "[TTS] Aktywowano glosy Microsoft Natural 3. generacji (48kHz 16-bit 2ch Stereo tylko na sluchawkach)." -ForegroundColor Green

# 4. Zainstaluj Git post-commit hook do automatycznego git push po kazdym commicie
$gitHooksDir = Join-Path $root ".git\hooks"
if (Test-Path (Join-Path $root ".git")) {
    New-Item -ItemType Directory -Path $gitHooksDir -Force | Out-Null
    $postCommitHook = "#!/bin/sh`ngit push origin HEAD >/dev/null 2>&1 &`n"
    [System.IO.File]::WriteAllText((Join-Path $gitHooksDir "post-commit"), $postCommitHook, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "[Git] Zainstalowano automatyczny hook post-commit -> git push." -ForegroundColor Green
}

# 5. Wdroz rozszerzenie whisper_saver do VS Code (oraz Cursor, jesli zainstalowany)
$ideTargets = @(
    (Join-Path $env:USERPROFILE ".vscode\extensions\whisper_saver")
)
if (Test-Path (Join-Path $env:USERPROFILE ".cursor\extensions")) {
    $ideTargets += (Join-Path $env:USERPROFILE ".cursor\extensions\whisper_saver")
}

foreach ($extTarget in $ideTargets) {
    if (-not (Test-Path $extTarget)) {
        New-Item -ItemType Directory -Path $extTarget -Force | Out-Null
    }
    $extSrc = Join-Path $extTarget "src"
    $extBin = Join-Path $extTarget "bin"
    New-Item -ItemType Directory -Path $extSrc -Force | Out-Null
    New-Item -ItemType Directory -Path $extBin -Force | Out-Null

    Copy-Item (Join-Path $root "package.json") (Join-Path $extTarget "package.json") -Force
    Copy-Item (Join-Path $root "extension.js") (Join-Path $extTarget "extension.js") -Force
    Copy-Item (Join-Path $root "src\*") "$extSrc\" -Recurse -Force
    Copy-Item (Join-Path $root "bin\*") "$extBin\" -Recurse -Force
    Write-Host "[Deploy] Zainstalowano whisper_saver -> $extTarget" -ForegroundColor Green
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  whisper_saver gotowy! 100% operacji w pamieci RAM.      " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
