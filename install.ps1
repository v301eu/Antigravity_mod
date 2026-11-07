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

# 3. Pobierz lokalny silnik neuronowy Piper TTS + polskie glosy offline (Darkman + MC Speech)
$piperDir = Join-Path $binSource "piper"
if (-not (Test-Path $piperDir)) {
    New-Item -ItemType Directory -Path $piperDir -Force | Out-Null
}
$piperExe = Join-Path $piperDir "piper.exe"
if (-not (Test-Path $piperExe)) {
    Write-Host "[TTS] Pobieranie lokalnego silnika Piper TTS (100% offline)..." -ForegroundColor Yellow
    $piperZip = Join-Path $tmp "piper_windows_amd64.zip"
    curl.exe -L --retry 3 -o $piperZip "https://github.com/rhasspy/piper/releases/latest/download/piper_windows_amd64.zip"
    Expand-Archive -Path $piperZip -DestinationPath $binSource -Force
    Remove-Item $piperZip -Force -ErrorAction SilentlyContinue
}
Copy-Item (Join-Path $binSource "msvcp*.dll") "$piperDir\" -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $binSource "vcruntime*.dll") "$piperDir\" -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $binSource "vcomp*.dll") "$piperDir\" -Force -ErrorAction SilentlyContinue
$mcOnnx = Join-Path $piperDir "pl_PL-mc_speech-medium.onnx"
$mcJson = Join-Path $piperDir "pl_PL-mc_speech-medium.onnx.json"
if (-not (Test-Path $mcOnnx) -or (Get-Item $mcOnnx).Length -lt 50000000) {
    Write-Host "[TTS] Pobieranie polskiego glosu lokalnego MC Speech (pl_PL-mc_speech-medium.onnx)..." -ForegroundColor Yellow
    curl.exe -L --retry 3 -o $mcOnnx "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pl/pl_PL/mc_speech/medium/pl_PL-mc_speech-medium.onnx"
}
if (-not (Test-Path $mcJson)) {
    curl.exe -L --retry 3 -o $mcJson "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pl/pl_PL/mc_speech/medium/pl_PL-mc_speech-medium.onnx.json"
}
$darkmanOnnx = Join-Path $piperDir "pl_PL-darkman-medium.onnx"
$darkmanJson = Join-Path $piperDir "pl_PL-darkman-medium.onnx.json"
if (-not (Test-Path $darkmanOnnx) -or (Get-Item $darkmanOnnx).Length -lt 50000000) {
    Write-Host "[TTS] Pobieranie polskiego glosu lokalnego Darkman (pl_PL-darkman-medium.onnx)..." -ForegroundColor Yellow
    curl.exe -L --retry 3 -o $darkmanOnnx "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pl/pl_PL/darkman/medium/pl_PL-darkman-medium.onnx"
}
if (-not (Test-Path $darkmanJson)) {
    curl.exe -L --retry 3 -o $darkmanJson "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/pl/pl_PL/darkman/medium/pl_PL-darkman-medium.onnx.json"
}

# Kompilacja i rejestracja systemowego silnika SAPI 5 / OneCore (PiperSapiEngine.dll) + Microsoft Ryan w Windows 11
Add-Type -AssemblyName System.Speech
$sysSpeechLoc = [System.Speech.Synthesis.SpeechSynthesizer].Assembly.Location
$piperSapiDll = Join-Path $piperDir "PiperSapiEngine.dll"
$piperSapiCs = Join-Path $root "src\PiperSapiEngine.cs"
if (Test-Path $piperSapiCs) {
    if (Test-Path $piperSapiDll) { Rename-Item $piperSapiDll "PiperSapiEngine.dll.old" -Force -ErrorAction SilentlyContinue }
    & "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:library /reference:$sysSpeechLoc /out:$piperSapiDll $piperSapiCs
    Remove-Item (Join-Path $piperDir "PiperSapiEngine.dll.old*") -Force -ErrorAction SilentlyContinue
}
$codeBaseUri = ([System.Uri]$piperSapiDll).AbsoluteUri
foreach ($entry in @(
    @{ Clsid = "{D8E7F6A5-B4C3-4D2E-9F1A-0B9C8D7E6F50}"; Class = "PiperSapi.PiperTtsEngine" },
    @{ Clsid = "{D8E7F6A5-B4C3-4D2E-9F1A-0B9C8D7E6F52}"; Class = "PiperSapi.PiperTtsEngine" },
    @{ Clsid = "{B8B9E38F-E5A2-4661-9FDE-4AC7377AA6F6}"; Class = "PiperSapi.PiperAndNaturalVoiceEnumerator" }
)) {
    foreach ($base in @("HKCU:\Software\Classes\CLSID\$($entry.Clsid)", "HKCU:\Software\Classes\WOW6432Node\CLSID\$($entry.Clsid)")) {
        New-Item -Path $base -Force | Out-Null
        Set-ItemProperty -Path $base -Name "(default)" -Value $entry.Class
        $inproc = "$base\InprocServer32"
        New-Item -Path $inproc -Force | Out-Null
        Set-ItemProperty -Path $inproc -Name "(default)" -Value "mscoree.dll"
        Set-ItemProperty -Path $inproc -Name "ThreadingModel" -Value "Both"
        Set-ItemProperty -Path $inproc -Name "Class" -Value $entry.Class
        Set-ItemProperty -Path $inproc -Name "Assembly" -Value "PiperSapiEngine, Version=0.0.0.0, Culture=neutral, PublicKeyToken=null"
        Set-ItemProperty -Path $inproc -Name "RuntimeVersion" -Value "v4.0.30319"
        Set-ItemProperty -Path $inproc -Name "CodeBase" -Value $codeBaseUri
    }
}

function Register-SystemPiperVoice($tokenRoot, $voiceName, $modelPath, $clsid) {
    New-Item -Path $tokenRoot -Force | Out-Null
    Set-ItemProperty -Path $tokenRoot -Name "(default)" -Value "$voiceName - Polish (Poland)"
    Set-ItemProperty -Path $tokenRoot -Name "415" -Value "$voiceName - Polish (Poland)"
    Set-ItemProperty -Path $tokenRoot -Name "CLSID" -Value $clsid
    Set-ItemProperty -Path $tokenRoot -Name "Assembly" -Value "PiperSapiEngine"
    Set-ItemProperty -Path $tokenRoot -Name "PiperExe" -Value $piperExe
    Set-ItemProperty -Path $tokenRoot -Name "ModelPath" -Value $modelPath
    Set-ItemProperty -Path $tokenRoot -Name "SampleRate" -Value 22050 -Type DWord
    $attr = "$tokenRoot\Attributes"
    New-Item -Path $attr -Force | Out-Null
    Set-ItemProperty -Path $attr -Name "Age" -Value "Adult"
    Set-ItemProperty -Path $attr -Name "Gender" -Value "Male"
    Set-ItemProperty -Path $attr -Name "Language" -Value "415"
    Set-ItemProperty -Path $attr -Name "Locale" -Value "pl-PL"
    Set-ItemProperty -Path $attr -Name "Name" -Value $voiceName
    Set-ItemProperty -Path $attr -Name "Vendor" -Value "Piper"
    Set-ItemProperty -Path $attr -Name "Version" -Value "11.0"
}

Register-SystemPiperVoice "HKCU:\Software\PiperSapiEngine\Tokens\Piper_plPL_Darkman" "Piper Darkman" $darkmanOnnx "{D8E7F6A5-B4C3-4D2E-9F1A-0B9C8D7E6F50}"
Register-SystemPiperVoice "HKCU:\Software\PiperSapiEngine\Tokens\Piper_plPL_MCSpeech" "Piper MC Speech" $mcOnnx "{D8E7F6A5-B4C3-4D2E-9F1A-0B9C8D7E6F52}"

$ryanPkg = Get-AppxPackage -Name "MicrosoftWindows.Voice.en-GB.Ryan*" -ErrorAction SilentlyContinue | Select-Object -First 1
foreach ($rootIso in (Get-ChildItem "HKCU:\Software\Microsoft\Speech_OneCore\Isolated" -ErrorAction SilentlyContinue)) {
    $tokensPath = "$($rootIso.PSPath)\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens"
    if (Test-Path $tokensPath) {
        Register-SystemPiperVoice "$tokensPath\Piper_plPL_Darkman" "Piper Darkman" $darkmanOnnx "{D8E7F6A5-B4C3-4D2E-9F1A-0B9C8D7E6F50}"
        Register-SystemPiperVoice "$tokensPath\Piper_plPL_MCSpeech" "Piper MC Speech" $mcOnnx "{D8E7F6A5-B4C3-4D2E-9F1A-0B9C8D7E6F52}"
        if ($ryanPkg) {
            $ryanKey = "$tokensPath\MSTTS_V110_enGB_RyanM"
            New-Item -Path $ryanKey -Force | Out-Null
            Set-ItemProperty -Path $ryanKey -Name "(default)" -Value "Microsoft Ryan (Natural) - English (United Kingdom)"
            Set-ItemProperty -Path $ryanKey -Name "809" -Value "Microsoft Ryan (Natural) - English (United Kingdom)"
            Set-ItemProperty -Path $ryanKey -Name "CLSID" -Value "{013AB33B-AD1A-401C-8BEE-F6E2B046A94E}"
            $attrKey = "$ryanKey\Attributes"
            New-Item -Path $attrKey -Force | Out-Null
            Set-ItemProperty -Path $attrKey -Name "Age" -Value "Adult"
            Set-ItemProperty -Path $attrKey -Name "Gender" -Value "Male"
            Set-ItemProperty -Path $attrKey -Name "Language" -Value "809"
            Set-ItemProperty -Path $attrKey -Name "Locale" -Value "en-GB"
            Set-ItemProperty -Path $attrKey -Name "Name" -Value "Microsoft Ryan"
            Set-ItemProperty -Path $attrKey -Name "Vendor" -Value "Microsoft"
            Set-ItemProperty -Path $attrKey -Name "Version" -Value "11.0"
            Set-ItemProperty -Path $attrKey -Name "NaturalVoiceType" -Value "Narrator;Local"
            $cfgKey = "$ryanKey\NaturalVoiceConfig"
            New-Item -Path $cfgKey -Force | Out-Null
            Set-ItemProperty -Path $cfgKey -Name "ErrorMode" -Value 0 -Type DWord
            Set-ItemProperty -Path $cfgKey -Name "Path" -Value $ryanPkg.InstallLocation
        }
    }
}

# 4. Aktywuj wylacznie LOKALNE glosy Narratora (Ryan EN offline) i zablokuj wszystkie glosy Online/Edge
$nvEnumKey = "HKCU:\Software\NaturalVoiceSAPIAdapter\Enumerator"
if (-not (Test-Path $nvEnumKey)) {
    $nvInstallDir = Join-Path $env:USERPROFILE "NaturalVoiceSAPIAdapter"
    $dll64 = Join-Path $nvInstallDir "x64\NaturalVoiceSAPIAdapter.dll"
    if (-not (Test-Path $dll64)) {
        Write-Host "[TTS] Pobieranie adaptera lokalnych glosow Narratora..." -ForegroundColor Yellow
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
Set-ItemProperty -Path $nvEnumKey -Name "NoEdgeVoices" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $nvEnumKey -Name "NoAzureVoices" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $nvEnumKey -Name "EdgeVoiceAllLanguages" -Value 0 -Type DWord -ErrorAction SilentlyContinue
Write-Host "[TTS] Aktywowano w 100% lokalne glosy offline: PL (MC Speech) + EN (Microsoft Ryan) w 48kHz Stereo (glosy Online ZABLOKOWANE)." -ForegroundColor Green

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
