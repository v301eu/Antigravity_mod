param(
    [int]$WhisperPort = 18971,
    [switch]$CompileOnly
)

# whisper_saver: Pure-RAM Audio, Microsoft 3rd-Gen Natural TTS (48kHz 16-bit 2ch Stereo),
# Strict Headphone-Only Output (Bluetooth A2DP Stereo / Wired AUX - Speakers & Hands-Free Blocked),
# Stationary Array/USB Microphone Input, and Chat Input Daemon.

$ErrorActionPreference = "Continue"
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

# 1. Ensure ONLY Local Offline Voices are enabled in NaturalVoiceSAPIAdapter (Online/Edge Voices STRICTLY BLOCKED)
try {
    $enumKey = "HKCU:\Software\NaturalVoiceSAPIAdapter\Enumerator"
    if (Test-Path $enumKey) {
        Set-ItemProperty -Path $enumKey -Name "NoNarratorVoices" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $enumKey -Name "NoEdgeVoices" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $enumKey -Name "NoAzureVoices" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $enumKey -Name "EdgeVoiceAllLanguages" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
} catch {}

$script:binRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "bin"
$script:piperDir = Join-Path $script:binRoot "piper"
if (-not (Test-Path (Join-Path $script:piperDir "piper.exe"))) {
    $altPiper = Join-Path $env:USERPROFILE "projects\whisper_saver\bin\piper"
    if (Test-Path (Join-Path $altPiper "piper.exe")) {
        $script:piperDir = $altPiper
    }
}
$script:piperExe = Join-Path $script:piperDir "piper.exe"
$script:piperPlModel = Join-Path $script:piperDir "pl_PL-mc_speech-medium.onnx"

Add-Type -AssemblyName System.Speech
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$null = [Windows.Media.Playback.MediaPlayer, Windows.Media, ContentType = WindowsRuntime]
$null = [Windows.Media.Core.MediaSource, Windows.Media, ContentType = WindowsRuntime]
$null = [Windows.Media.MediaPlaybackType, Windows.Media, ContentType = WindowsRuntime]
$null = [Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
$null = [Windows.Media.Devices.MediaDevice, Windows.Media.Devices, ContentType = WindowsRuntime]

Add-Type -ReferencedAssemblies @(
    "System.dll",
    "System.Windows.Forms.dll",
    "System.Drawing.dll",
    "System.Net.Http.dll"
) -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

public static class WhisperNative {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    public static extern uint GetClipboardSequenceNumber();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    public const uint INPUT_KEYBOARD = 1;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const ushort VK_CONTROL = 0x11;
    public const ushort VK_RETURN = 0x0D;
    public const ushort VK_A = 0x41;
    public const ushort VK_C = 0x43;
    public const ushort VK_V = 0x56;

    public static void SendKeyCombo(ushort modVk, ushort keyVk) {
        INPUT[] inputs = new INPUT[4];
        inputs[0].type = INPUT_KEYBOARD; inputs[0].U.ki.wVk = modVk;
        inputs[1].type = INPUT_KEYBOARD; inputs[1].U.ki.wVk = keyVk;
        inputs[2].type = INPUT_KEYBOARD; inputs[2].U.ki.wVk = keyVk; inputs[2].U.ki.dwFlags = KEYEVENTF_KEYUP;
        inputs[3].type = INPUT_KEYBOARD; inputs[3].U.ki.wVk = modVk; inputs[3].U.ki.dwFlags = KEYEVENTF_KEYUP;
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    public static void SendSingleKey(ushort keyVk) {
        INPUT[] inputs = new INPUT[2];
        inputs[0].type = INPUT_KEYBOARD; inputs[0].U.ki.wVk = keyVk;
        inputs[1].type = INPUT_KEYBOARD; inputs[1].U.ki.wVk = keyVk; inputs[1].U.ki.dwFlags = KEYEVENTF_KEYUP;
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
    }

    public static void InjectTextOnSta(string text, bool replaceExisting, bool submitEnter) {
        Thread t = new Thread(() => {
            Image savedImage = null;
            string savedText = null;
            bool hadImage = false;
            bool hadText = false;
            try {
                if (Clipboard.ContainsImage()) {
                    Image tmp = Clipboard.GetImage();
                    if (tmp != null) {
                        savedImage = new Bitmap(tmp);
                        hadImage = true;
                        tmp.Dispose();
                    }
                } else if (Clipboard.ContainsText()) {
                    savedText = Clipboard.GetText(TextDataFormat.UnicodeText);
                    hadText = true;
                }
            } catch {}

            try {
                string toPaste = replaceExisting ? text : (text.Trim() + " ");
                Clipboard.SetText(toPaste, TextDataFormat.UnicodeText);
                Thread.Sleep(55);

                if (replaceExisting) {
                    SendKeyCombo(VK_CONTROL, VK_A);
                    Thread.Sleep(45);
                }

                SendKeyCombo(VK_CONTROL, VK_V);

                if (submitEnter) {
                    Thread.Sleep(180);
                    SendSingleKey(VK_RETURN);
                }

                Thread.Sleep(220);
            } catch {}

            try {
                if (hadImage && savedImage != null) {
                    Clipboard.SetImage(savedImage);
                    savedImage.Dispose();
                } else if (hadText && savedText != null) {
                    Clipboard.SetText(savedText, TextDataFormat.UnicodeText);
                }
            } catch {}
        });
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
        t.Join(4000);
    }

    public static bool PasteImageOnSta() {
        bool pasted = false;
        Thread t = new Thread(() => {
            try {
                if (Clipboard.ContainsImage()) {
                    Thread.Sleep(40);
                    SendKeyCombo(VK_CONTROL, VK_V);
                    pasted = true;
                    Thread.Sleep(120);
                }
            } catch {}
        });
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
        t.Join(2500);
        return pasted;
    }

    public static bool CheckClipboardHasImage() {
        bool hasImg = false;
        Thread t = new Thread(() => {
            try { hasImg = Clipboard.ContainsImage(); } catch {}
        });
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
        t.Join(800);
        return hasImg;
    }

    public static string CaptureFocusedInputTextOnSta() {
        string captured = "";
        Thread t = new Thread(() => {
            Image savedImage = null;
            string savedText = null;
            bool hadImage = false;
            bool hadText = false;
            try {
                if (Clipboard.ContainsImage()) {
                    Image tmp = Clipboard.GetImage();
                    if (tmp != null) { savedImage = new Bitmap(tmp); hadImage = true; tmp.Dispose(); }
                } else if (Clipboard.ContainsText()) {
                    savedText = Clipboard.GetText(TextDataFormat.UnicodeText);
                    hadText = true;
                }
                Clipboard.Clear();
                Thread.Sleep(25);
                SendKeyCombo(VK_CONTROL, VK_A);
                Thread.Sleep(35);
                SendKeyCombo(VK_CONTROL, VK_C);
                Thread.Sleep(60);
                if (Clipboard.ContainsText()) {
                    captured = Clipboard.GetText(TextDataFormat.UnicodeText) ?? "";
                }
            } catch {}
            try {
                if (hadImage && savedImage != null) {
                    Clipboard.SetImage(savedImage);
                    savedImage.Dispose();
                } else if (hadText && savedText != null) {
                    Clipboard.SetText(savedText, TextDataFormat.UnicodeText);
                }
            } catch {}
        });
        t.SetApartmentState(ApartmentState.STA);
        t.IsBackground = true;
        t.Start();
        t.Join(2500);
        return captured;
    }
}

public class RamWaveRecorder : IDisposable {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WAVEINCAPS {
        public ushort wMid;
        public ushort wPid;
        public uint vDriverVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szPname;
        public uint dwFormats;
        public ushort wChannels;
        public ushort wReserved1;
    }

    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    private static extern int waveInGetNumDevs();

    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    private static extern int waveInGetDevCaps(IntPtr uDeviceID, out WAVEINCAPS pwic, uint cbwic);

    [DllImport("winmm.dll")]
    private static extern int waveInOpen(out IntPtr hWaveIn, int uDeviceID, ref WAVEFORMATEX lpFormat, WaveInProc dwCallback, IntPtr dwInstance, int dwFlags);
    [DllImport("winmm.dll")]
    private static extern int waveInPrepareHeader(IntPtr hWaveIn, IntPtr lpWaveInHdr, int uSize);
    [DllImport("winmm.dll")]
    private static extern int waveInUnprepareHeader(IntPtr hWaveIn, IntPtr lpWaveInHdr, int uSize);
    [DllImport("winmm.dll")]
    private static extern int waveInAddBuffer(IntPtr hWaveIn, IntPtr lpWaveInHdr, int uSize);
    [DllImport("winmm.dll")]
    private static extern int waveInStart(IntPtr hWaveIn);
    [DllImport("winmm.dll")]
    private static extern int waveInReset(IntPtr hWaveIn);
    [DllImport("winmm.dll")]
    private static extern int waveInClose(IntPtr hWaveIn);

    private delegate void WaveInProc(IntPtr hwi, uint uMsg, IntPtr dwInstance, IntPtr dwParam1, IntPtr dwParam2);

    [StructLayout(LayoutKind.Sequential)]
    private struct WAVEFORMATEX {
        public ushort wFormatTag;
        public ushort nChannels;
        public uint nSamplesPerSec;
        public uint nAvgBytesPerSec;
        public ushort nBlockAlign;
        public ushort wBitsPerSample;
        public ushort cbSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WAVEHDR {
        public IntPtr lpData;
        public uint dwBufferLength;
        public uint dwBytesRecorded;
        public IntPtr dwUser;
        public uint dwFlags;
        public uint dwLoops;
        public IntPtr lpNext;
        public IntPtr reserved;
    }

    private const int CALLBACK_FUNCTION = 0x00030000;
    private const uint WIM_DATA = 0x3C0;
    private const int SAMPLE_RATE = 16000;
    private const int BUFFER_BYTES = 3200; // 100ms of 16kHz 16-bit Mono PCM for Whisper
    private const int NUM_BUFFERS = 8;
    // Quiet room + Windows noise suppression: silence is ~0 RMS, so a very low threshold catches even whispering.
    private const double VAD_RMS_THRESHOLD = 5.0;

    private static readonly HttpClient _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };

    private IntPtr _hWaveIn = IntPtr.Zero;
    private WaveInProc _callback;
    private IntPtr[] _hdrPtrs = new IntPtr[NUM_BUFFERS];
    private IntPtr[] _bufPtrs = new IntPtr[NUM_BUFFERS];
    private volatile bool _isOpen = false;
    private readonly object _sync = new object();

    public string ActiveMicName { get; private set; }
    public int WhisperPort { get; set; }
    public object ConsoleOutLock { get; set; }

    public bool IsManualRecording { get; private set; }
    public bool AutoVadEnabled { get; set; }
    private Queue<byte[]> _preRoll = new Queue<byte[]>();
    private MemoryStream _vadPcm = null;
    private bool _vadInSpeech = false;
    private int _vadSilenceChunks = 0;
    private int _vadSpeechChunks = 0;

    public RamWaveRecorder() {
        _callback = new WaveInProc(OnWaveData);
        ActiveMicName = "";
        WhisperPort = 18971;
        ConsoleOutLock = new object();
    }

    private void WriteJsonEvent(string jsonLine) {
        object lk = ConsoleOutLock ?? _sync;
        Monitor.Enter(lk);
        try {
            Console.Out.WriteLine(jsonLine);
            Console.Out.Flush();
        } catch {} finally {
            Monitor.Exit(lk);
        }
    }

    private static string EscapeJson(string s) {
        if (string.IsNullOrEmpty(s)) return "";
        StringBuilder sb = new StringBuilder(s.Length + 8);
        foreach (char c in s) {
            switch (c) {
                case '\\': sb.Append("\\\\"); break;
                case '"': sb.Append("\\\""); break;
                case '\r': sb.Append("\\r"); break;
                case '\n': sb.Append("\\n"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20) sb.AppendFormat("\\u{0:x4}", (int)c);
                    else sb.Append(c);
                    break;
            }
        }
        return sb.ToString();
    }

    // Strictly select ONLY stationary Microphone Array / USB microphone.
    // Categorically forbid Bluetooth / Hands-Free / Headset capture devices so Bluetooth headphones NEVER drop from 48kHz Stereo A2DP!
    public int FindStationaryArrayOrUsbMicId() {
        int count = waveInGetNumDevs();
        int fallbackStationary = -999;
        string fallbackName = "";

        for (int i = 0; i < count; i++) {
            WAVEINCAPS caps;
            if (waveInGetDevCaps((IntPtr)i, out caps, (uint)Marshal.SizeOf(typeof(WAVEINCAPS))) == 0) {
                string name = (caps.szPname ?? "").Trim();
                string low = name.ToLowerInvariant();

                // Block Bluetooth / Hands-Free / Headset microphones unconditionally
                if (low.Contains("hands-free") || low.Contains("handsfree") || low.Contains("headset") ||
                    low.Contains("bluetooth") || low.Contains("bth") || low.Contains("ag audio") ||
                    low.Contains("baseus") || low.Contains("airpods") || low.Contains("buds") || low.Contains("wireless")) {
                    continue;
                }

                // Prefer stationary Microphone Array or USB microphone
                if (low.Contains("array") || low.Contains("uk\u0142ad") || low.Contains("usb") || low.Contains("stacjonar") || low.Contains("desktop")) {
                    ActiveMicName = name;
                    return i;
                }

                if (fallbackStationary == -999) {
                    fallbackStationary = i;
                    fallbackName = name;
                }
            }
        }

        if (fallbackStationary >= 0) {
            ActiveMicName = fallbackName;
            return fallbackStationary;
        }
        return -999;
    }

    public bool EnsureOpen() {
        lock (_sync) {
            if (_isOpen) return true;

            int devId = FindStationaryArrayOrUsbMicId();
            if (devId < 0) return false;

            WAVEFORMATEX fmt = new WAVEFORMATEX {
                wFormatTag = 1,
                nChannels = 1,
                nSamplesPerSec = SAMPLE_RATE,
                wBitsPerSample = 16,
                nBlockAlign = 2,
                nAvgBytesPerSec = SAMPLE_RATE * 2,
                cbSize = 0
            };

            int rc = waveInOpen(out _hWaveIn, devId, ref fmt, _callback, IntPtr.Zero, CALLBACK_FUNCTION);
            if (rc != 0 || _hWaveIn == IntPtr.Zero) return false;

            int hdrSize = Marshal.SizeOf(typeof(WAVEHDR));
            for (int i = 0; i < NUM_BUFFERS; i++) {
                _bufPtrs[i] = Marshal.AllocHGlobal(BUFFER_BYTES);
                _hdrPtrs[i] = Marshal.AllocHGlobal(hdrSize);
                WAVEHDR hdr = new WAVEHDR {
                    lpData = _bufPtrs[i],
                    dwBufferLength = BUFFER_BYTES
                };
                Marshal.StructureToPtr(hdr, _hdrPtrs[i], false);
                waveInPrepareHeader(_hWaveIn, _hdrPtrs[i], hdrSize);
                waveInAddBuffer(_hWaveIn, _hdrPtrs[i], hdrSize);
            }

            waveInStart(_hWaveIn);
            _isOpen = true;
            return true;
        }
    }

    public bool StartManual() {
        if (!EnsureOpen()) return false;
        lock (_sync) {
            IsManualRecording = true;
            _vadInSpeech = false;
            _vadPcm = null;
            _vadSpeechChunks = 0;
            _vadSilenceChunks = 0;
            _preRoll.Clear();
        }
        return true;
    }

    public byte[] StopManualAndGetWav() {
        byte[] pcm = null;
        int speechChunks = 0;
        lock (_sync) {
            IsManualRecording = false;
            if (_vadInSpeech && _vadPcm != null) {
                pcm = _vadPcm.ToArray();
                speechChunks = _vadSpeechChunks;
                _vadPcm.Dispose();
                _vadPcm = null;
                _vadInSpeech = false;
            }
        }
        if (!AutoVadEnabled) {
            CloseDevice();
        }
        if (pcm == null || speechChunks < 2 || pcm.Length < 3200) return null;
        return WrapPcmMono16kAsWav(pcm);
    }

    public void SetAutoVad(bool enabled) {
        lock (_sync) {
            AutoVadEnabled = enabled;
            if (!IsManualRecording) {
                _vadInSpeech = false;
                _vadPcm = null;
                _preRoll.Clear();
            }
        }
        if (enabled) {
            EnsureOpen();
        } else if (!IsManualRecording) {
            CloseDevice();
        }
    }

    private void OnWaveData(IntPtr hwi, uint uMsg, IntPtr dwInstance, IntPtr dwParam1, IntPtr dwParam2) {
        if (uMsg != WIM_DATA || !_isOpen) return;

        try {
            WAVEHDR hdr = (WAVEHDR)Marshal.PtrToStructure(dwParam1, typeof(WAVEHDR));
            int recorded = (int)hdr.dwBytesRecorded;
            byte[] chunk = null;
            if (recorded > 0) {
                chunk = new byte[recorded];
                Marshal.Copy(hdr.lpData, chunk, 0, recorded);
            }

            if (_isOpen && _hWaveIn != IntPtr.Zero) {
                waveInAddBuffer(_hWaveIn, dwParam1, Marshal.SizeOf(typeof(WAVEHDR)));
            }

            if (chunk == null || chunk.Length == 0) return;

            byte[] finishedVadWav = null;
            bool triggerVadStart = false;
            string currentMode = "live";

            lock (_sync) {
                if (!IsManualRecording && !AutoVadEnabled) {
                    _vadInSpeech = false;
                    _vadPcm = null;
                    _preRoll.Clear();
                    return;
                }

                currentMode = IsManualRecording ? "live" : "auto";
                double rms = ComputeRms(chunk);
                bool isVoice = rms > VAD_RMS_THRESHOLD;

                if (!_vadInSpeech) {
                    _preRoll.Enqueue(chunk);
                    while (_preRoll.Count > 4) _preRoll.Dequeue();

                    if (isVoice) {
                        _vadSpeechChunks = 1;
                        _vadSilenceChunks = 0;
                        _vadInSpeech = true;
                        _vadPcm = new MemoryStream(SAMPLE_RATE * 2 * 10);
                        foreach (byte[] pre in _preRoll) {
                            _vadPcm.Write(pre, 0, pre.Length);
                        }
                        _preRoll.Clear();
                        triggerVadStart = true;
                    }
                } else {
                    _vadPcm.Write(chunk, 0, chunk.Length);
                    if (isVoice) {
                        _vadSpeechChunks++;
                        _vadSilenceChunks = 0;
                    } else {
                        _vadSilenceChunks++;
                    }

                    // Slice phrase on 400ms natural pause (4 chunks) or after 4.5s of continuous speech for bilingual real-time streaming
                    if (_vadSilenceChunks >= 4 || _vadPcm.Length >= SAMPLE_RATE * 2 * 9 / 2) {
                        byte[] rawVad = _vadPcm.ToArray();
                        int spChunks = _vadSpeechChunks;
                        _vadPcm.Dispose();
                        _vadPcm = null;
                        _vadInSpeech = false;
                        _vadSpeechChunks = 0;
                        _vadSilenceChunks = 0;
                        if (spChunks >= 2 && rawVad.Length >= 3200) {
                            finishedVadWav = WrapPcmMono16kAsWav(rawVad);
                        }
                    }
                }
            }

            if (triggerVadStart && currentMode == "auto") {
                ThreadPool.QueueUserWorkItem(_ => {
                    WriteJsonEvent("{\"event\":\"vadSpeechStart\"}");
                });
            }
            if (finishedVadWav != null) {
                byte[] payload = finishedVadWav;
                string m = currentMode;
                TranscribeWavAsync(payload, m);
            }
        } catch {}
    }

    public void TranscribeWavAsync(byte[] wavBytes, string mode) {
        if (wavBytes == null || wavBytes.Length < 1600) {
            if (mode == "manual") {
                WriteJsonEvent("{\"event\":\"micIdle\",\"reason\":\"too_short\"}");
            }
            return;
        }
        ThreadPool.QueueUserWorkItem(_ => {
            try {
                if (mode == "auto") {
                    WriteJsonEvent("{\"event\":\"vadProcessing\"}");
                }
                List<byte[]> subWavs = SplitWavOnMicroPauses(wavBytes);
                StringBuilder fullText = new StringBuilder();
                string lastLang = "pl";
                foreach (byte[] sw in subWavs) {
                    string rawJson = PostWavToWhisperRam(WhisperPort, sw);
                    string partText = ExtractWhisperText(rawJson);
                    if (!string.IsNullOrWhiteSpace(partText)) {
                        if (fullText.Length > 0) fullText.Append(" ");
                        fullText.Append(partText);
                        lastLang = DetectIsoLang(rawJson, partText);
                    }
                }
                string text = fullText.ToString().Trim();
                if (!string.IsNullOrWhiteSpace(text)) {
                    WriteJsonEvent("{\"event\":\"transcription\",\"text\":\"" + EscapeJson(text) + "\",\"lang\":\"" + lastLang + "\",\"mode\":\"" + EscapeJson(mode) + "\"}");
                } else if (mode == "manual") {
                    WriteJsonEvent("{\"event\":\"micIdle\",\"reason\":\"empty\"}");
                }
            } catch (Exception ex) {
                WriteJsonEvent("{\"event\":\"error\",\"source\":\"whisper\",\"message\":\"" + EscapeJson(ex.Message) + "\"}");
            }
        });
    }

    public static List<byte[]> SplitWavOnMicroPauses(byte[] wavBytes) {
        List<byte[]> result = new List<byte[]>();
        if (wavBytes == null || wavBytes.Length <= 44 + SAMPLE_RATE * 2 * 2) {
            if (wavBytes != null) result.Add(wavBytes);
            return result;
        }
        int pcmLen = wavBytes.Length - 44;
        byte[] pcm = new byte[pcmLen];
        Buffer.BlockCopy(wavBytes, 44, pcm, 0, pcmLen);

        // Compute adaptive silence threshold from 20ms frames (640 bytes)
        int frameBytes = 640; // 20ms at 16kHz 16-bit mono
        int totalFrames = pcmLen / frameBytes;
        if (totalFrames < 60) {
            result.Add(wavBytes);
            return result;
        }
        double[] frameRms = new double[totalFrames];
        double maxRms = 0;
        for (int f = 0; f < totalFrames; f++) {
            double sumSq = 0;
            int baseIdx = f * frameBytes;
            for (int i = 0; i < frameBytes; i += 2) {
                short s = (short)(pcm[baseIdx + i] | (pcm[baseIdx + i + 1] << 8));
                sumSq += (double)s * s;
            }
            frameRms[f] = Math.Sqrt(sumSq / (frameBytes / 2));
            if (frameRms[f] > maxRms) maxRms = frameRms[f];
        }
        double silenceThresh = Math.Max(15.0, maxRms * 0.08);
        int segStartFrame = 0;
        int quietFrames = 0;
        int voicedFrames = 0;

        for (int f = 0; f < totalFrames; f++) {
            if (frameRms[f] > silenceThresh) {
                voicedFrames++;
                quietFrames = 0;
            } else {
                quietFrames++;
                // Split if we have at least 0.8s (40 frames) of voiced speech followed by >= 180ms (9 frames) of pause
                if (voicedFrames >= 25 && quietFrames >= 9 && (f - segStartFrame) >= 40) {
                    int byteStart = segStartFrame * frameBytes;
                    int byteCount = (f - segStartFrame + 1) * frameBytes;
                    byte[] segPcm = new byte[byteCount];
                    Buffer.BlockCopy(pcm, byteStart, segPcm, 0, byteCount);
                    result.Add(WrapPcmMono16kAsWav(segPcm));
                    segStartFrame = f + 1;
                    voicedFrames = 0;
                    quietFrames = 0;
                }
            }
        }
        if (segStartFrame < totalFrames && voicedFrames >= 8) {
            int byteStart = segStartFrame * frameBytes;
            int byteCount = pcmLen - byteStart;
            if (byteCount >= 3200) {
                byte[] segPcm = new byte[byteCount];
                Buffer.BlockCopy(pcm, byteStart, segPcm, 0, byteCount);
                result.Add(WrapPcmMono16kAsWav(segPcm));
            }
        }
        if (result.Count == 0) result.Add(wavBytes);
        return result;
    }

    private static string ExtractWhisperText(string rawJson) {
        if (string.IsNullOrWhiteSpace(rawJson)) return "";
        int idx = rawJson.IndexOf("\"text\"", StringComparison.OrdinalIgnoreCase);
        if (idx < 0) return "";
        int colon = rawJson.IndexOf(':', idx + 6);
        if (colon < 0) return "";
        int qStart = rawJson.IndexOf('"', colon + 1);
        if (qStart < 0) return "";
        StringBuilder sb = new StringBuilder();
        for (int i = qStart + 1; i < rawJson.Length; i++) {
            char c = rawJson[i];
            if (c == '\\' && i + 1 < rawJson.Length) {
                char next = rawJson[++i];
                switch (next) {
                    case 'n': sb.Append(' '); break;
                    case 'r': break;
                    case 't': sb.Append(' '); break;
                    case '"': sb.Append('"'); break;
                    case '\\': sb.Append('\\'); break;
                    case 'u':
                        if (i + 4 < rawJson.Length) {
                            string hex = rawJson.Substring(i + 1, 4);
                            int code;
                            if (int.TryParse(hex, System.Globalization.NumberStyles.HexNumber, null, out code)) {
                                sb.Append((char)code);
                                i += 4;
                            }
                        }
                        break;
                    default: sb.Append(next); break;
                }
            } else if (c == '"') {
                break;
            } else {
                sb.Append(c);
            }
        }
        string t = System.Text.RegularExpressions.Regex.Replace(sb.ToString(), @"\[[^\]]*\]|\([^\)]*\)", "").Trim();
        // Filter common Whisper silence hallucinations
        if (System.Text.RegularExpressions.Regex.IsMatch(t, @"^(Dzi\u0119kuj\u0119 za uwag\u0119|Napisy stworzone przez|Subskrybuj|Thank you for watching|Thanks for watching|You)[\.\!\s]*$", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) {
            return "";
        }
        return t;
    }

    private static string DetectIsoLang(string rawJson, string sampleText) {
        if (!string.IsNullOrWhiteSpace(sampleText)) {
            if (System.Text.RegularExpressions.Regex.IsMatch(sampleText, @"[\u0105\u0107\u0119\u0142\u0144\u00F3\u015B\u017A\u017C\u0104\u0106\u0118\u0141\u0143\u00D3\u015A\u0179\u017B]|\b(jest|nie|dla|czy|tak|jak|oraz|kod|teraz|po\s+polsku|wiadomo\u015Bci)\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) {
                return "pl";
            }
            if (System.Text.RegularExpressions.Regex.IsMatch(sampleText, @"\b(the|and|is|in|to|of|for|with|that|this|english|message|second|half)\b", System.Text.RegularExpressions.RegexOptions.IgnoreCase)) {
                return "en";
            }
        }
        if (!string.IsNullOrWhiteSpace(rawJson)) {
            if (rawJson.IndexOf("\"english\"", StringComparison.OrdinalIgnoreCase) >= 0 || rawJson.IndexOf("\"en\"", StringComparison.OrdinalIgnoreCase) >= 0) return "en";
            if (rawJson.IndexOf("\"polish\"", StringComparison.OrdinalIgnoreCase) >= 0 || rawJson.IndexOf("\"pl\"", StringComparison.OrdinalIgnoreCase) >= 0) return "pl";
            if (rawJson.IndexOf("\"german\"", StringComparison.OrdinalIgnoreCase) >= 0 || rawJson.IndexOf("\"de\"", StringComparison.OrdinalIgnoreCase) >= 0) return "de";
        }
        return "pl";
    }

    private static double ComputeRms(byte[] pcm16) {
        int samples = pcm16.Length / 2;
        if (samples == 0) return 0;
        double sumSq = 0;
        for (int i = 0; i < samples * 2; i += 2) {
            short s = (short)(pcm16[i] | (pcm16[i + 1] << 8));
            sumSq += (double)s * s;
        }
        return Math.Sqrt(sumSq / samples);
    }

    // 16kHz 16-bit Mono WAV wrapper for Whisper AI input in RAM
    // Boost quiet recordings so the peak reaches ~70% of full scale (max 20x gain) before Whisper.
    public static byte[] NormalizePcm16(byte[] pcm) {
        int samples = pcm.Length / 2;
        int peak = 0;
        for (int i = 0; i < samples; i++) {
            int v = Math.Abs((int)(short)(pcm[2 * i] | (pcm[2 * i + 1] << 8)));
            if (v > peak) peak = v;
        }
        if (peak < 50 || peak >= 22000) return pcm;
        double gain = Math.Min(20.0, 23000.0 / peak);
        byte[] outPcm = new byte[samples * 2];
        for (int i = 0; i < samples; i++) {
            int v = (int)Math.Round((short)(pcm[2 * i] | (pcm[2 * i + 1] << 8)) * gain);
            if (v > 32767) v = 32767; else if (v < -32768) v = -32768;
            outPcm[2 * i] = (byte)(v & 0xFF);
            outPcm[2 * i + 1] = (byte)((v >> 8) & 0xFF);
        }
        return outPcm;
    }

    public static byte[] WrapPcmMono16kAsWav(byte[] pcm) {
        pcm = NormalizePcm16(pcm);
        using (MemoryStream ms = new MemoryStream(44 + pcm.Length))
        using (BinaryWriter bw = new BinaryWriter(ms)) {
            bw.Write(new char[] { 'R', 'I', 'F', 'F' });
            bw.Write(36 + pcm.Length);
            bw.Write(new char[] { 'W', 'A', 'V', 'E' });
            bw.Write(new char[] { 'f', 'm', 't', ' ' });
            bw.Write(16);
            bw.Write((ushort)1); // PCM
            bw.Write((ushort)1); // 1 channel
            bw.Write(SAMPLE_RATE);
            bw.Write(SAMPLE_RATE * 2);
            bw.Write((ushort)2);
            bw.Write((ushort)16);
            bw.Write(new char[] { 'd', 'a', 't', 'a' });
            bw.Write(pcm.Length);
            bw.Write(pcm);
            return ms.ToArray();
        }
    }

    // 48000Hz 16-bit 2-channel Stereo WAV wrapper for Bluetooth A2DP / Wired AUX Headphones in RAM
    public static byte[] WrapPcmStereo48kAsWav(byte[] pcm) {
        const int rate = 48000;
        const ushort channels = 2;
        const ushort bits = 16;
        const ushort blockAlign = 4; // 2 channels * 2 bytes
        const int byteRate = rate * blockAlign; // 192000 B/s

        using (MemoryStream ms = new MemoryStream(44 + pcm.Length))
        using (BinaryWriter bw = new BinaryWriter(ms)) {
            bw.Write(new char[] { 'R', 'I', 'F', 'F' });
            bw.Write(36 + pcm.Length);
            bw.Write(new char[] { 'W', 'A', 'V', 'E' });
            bw.Write(new char[] { 'f', 'm', 't', ' ' });
            bw.Write(16);
            bw.Write((ushort)1); // PCM
            bw.Write(channels);  // 2 channels (Stereo)
            bw.Write(rate);      // 48000 Hz
            bw.Write(byteRate);  // 192000
            bw.Write(blockAlign);
            bw.Write(bits);      // 16-bit
            bw.Write(new char[] { 'd', 'a', 't', 'a' });
            bw.Write(pcm.Length);
            bw.Write(pcm);
            return ms.ToArray();
        }
    }

    // 100% Local Offline Piper Neural TTS in pure RAM -> upsampled to 48000Hz 16-bit 2ch Stereo WAV
    public static byte[] SynthesizePiperStereo48kWav(string piperExe, string modelPath, string text, int srcRate = 22050) {
        if (string.IsNullOrWhiteSpace(text) || !File.Exists(piperExe) || !File.Exists(modelPath)) return null;

        byte[] rawMono = null;
        ProcessStartInfo psi = new ProcessStartInfo {
            FileName = piperExe,
            Arguments = "--model \"" + modelPath + "\" --output_raw",
            WorkingDirectory = Path.GetDirectoryName(piperExe),
            CreateNoWindow = true,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        using (Process proc = Process.Start(psi)) {
            byte[] utf8Text = Encoding.UTF8.GetBytes(text.Replace("\r", " ").Replace("\n", " ") + "\n");
            proc.StandardInput.BaseStream.Write(utf8Text, 0, utf8Text.Length);
            proc.StandardInput.BaseStream.Flush();
            proc.StandardInput.Close();

            using (MemoryStream msOut = new MemoryStream(srcRate * 2 * 15)) {
                proc.StandardOutput.BaseStream.CopyTo(msOut);
                rawMono = msOut.ToArray();
            }
            proc.WaitForExit(15000);
        }

        if (rawMono == null || rawMono.Length < 4) return null;

        int inSamples = rawMono.Length / 2;
        const int dstRate = 48000;
        int outSamples = (int)((long)inSamples * dstRate / srcRate);
        if (outSamples < 1) return null;

        byte[] stereo48k = new byte[outSamples * 4]; // 2 channels * 2 bytes per sample
        double ratio = (double)(inSamples - 1) / Math.Max(1, outSamples - 1);

        for (int i = 0; i < outSamples; i++) {
            double srcPos = i * ratio;
            int idx0 = (int)srcPos;
            int idx1 = idx0 + 1;
            if (idx1 >= inSamples) idx1 = inSamples - 1;
            double frac = srcPos - idx0;

            short s0 = (short)(rawMono[idx0 * 2] | (rawMono[idx0 * 2 + 1] << 8));
            short s1 = (short)(rawMono[idx1 * 2] | (rawMono[idx1 * 2 + 1] << 8));
            int interp = (int)Math.Round(s0 + (s1 - s0) * frac);
            if (interp > 32767) interp = 32767;
            else if (interp < -32768) interp = -32768;
            short outSample = (short)interp;

            byte lo = (byte)(outSample & 0xFF);
            byte hi = (byte)((outSample >> 8) & 0xFF);

            int byteOffset = i * 4;
            // Left channel
            stereo48k[byteOffset] = lo;
            stereo48k[byteOffset + 1] = hi;
            // Right channel
            stereo48k[byteOffset + 2] = lo;
            stereo48k[byteOffset + 3] = hi;
        }

        return WrapPcmStereo48kAsWav(stereo48k);
    }

    public static string PostWavToWhisperRam(int port, byte[] wavBytes) {
        using (MultipartFormDataContent mp = new MultipartFormDataContent()) {
            ByteArrayContent bc = new ByteArrayContent(wavBytes);
            bc.Headers.ContentType = MediaTypeHeaderValue.Parse("audio/wav");
            mp.Add(bc, "file", "speech.wav");
            mp.Add(new StringContent("verbose_json"), "response_format");
            mp.Add(new StringContent("auto"), "language");
            mp.Add(new StringContent("0.0"), "temperature");
            mp.Add(new StringContent("0.0"), "temperature_inc");
            HttpResponseMessage resp = _httpClient.PostAsync("http://127.0.0.1:" + port + "/inference", mp).GetAwaiter().GetResult();
            return resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        }
    }

    public void CloseDevice() {
        lock (_sync) {
            if (!_isOpen) return;
            _isOpen = false;
            IntPtr h = _hWaveIn;
            _hWaveIn = IntPtr.Zero;
            try {
                waveInReset(h);
                int hdrSize = Marshal.SizeOf(typeof(WAVEHDR));
                for (int i = 0; i < NUM_BUFFERS; i++) {
                    if (_hdrPtrs[i] != IntPtr.Zero) {
                        waveInUnprepareHeader(h, _hdrPtrs[i], hdrSize);
                        Marshal.FreeHGlobal(_hdrPtrs[i]);
                        _hdrPtrs[i] = IntPtr.Zero;
                    }
                    if (_bufPtrs[i] != IntPtr.Zero) {
                        Marshal.FreeHGlobal(_bufPtrs[i]);
                        _bufPtrs[i] = IntPtr.Zero;
                    }
                }
                waveInClose(h);
            } catch {}
        }
    }

    public void Dispose() {
        CloseDevice();
    }
}
"@

if ($CompileOnly) {
    Write-Output "DAEMON_COMPILED_OK"
    exit 0
}

$script:outLock = New-Object System.Object
function Emit-Event([hashtable]$payload) {
    [System.Threading.Monitor]::Enter($script:outLock)
    try {
        $json = $payload | ConvertTo-Json -Compress -Depth 5
        [Console]::Out.WriteLine($json)
        [Console]::Out.Flush()
    } catch {} finally {
        [System.Threading.Monitor]::Exit($script:outLock)
    }
}

function Resolve-IsoLang([string]$whisperLang, [string]$sampleText) {
    $wl = ($whisperLang -replace '\s+', '').ToLower()
    $map = @{
        "polish" = "pl"; "pl" = "pl"
        "english" = "en"; "en" = "en"
        "german" = "de"; "de" = "de"
        "french" = "fr"; "fr" = "fr"
        "spanish" = "es"; "es" = "es"
        "italian" = "it"; "it" = "it"
        "ukrainian" = "uk"; "uk" = "uk"
        "czech" = "cs"; "cs" = "cs"
        "portuguese" = "pt"; "pt" = "pt"
        "dutch" = "nl"; "nl" = "nl"
        "swedish" = "sv"; "sv" = "sv"
        "norwegian" = "nb"; "no" = "nb"
        "japanese" = "ja"; "ja" = "ja"
        "korean" = "ko"; "ko" = "ko"
        "chinese" = "zh"; "zh" = "zh"
    }
    if ($map.ContainsKey($wl)) { return $map[$wl] }
    $plChars = "[\u0105\u0107\u0119\u0142\u0144\u00F3\u015B\u017A\u017C\u0104\u0106\u0118\u0141\u0143\u00D3\u015A\u0179\u017B]"
    if ($sampleText -match $plChars -or $sampleText -match '\b(jest|nie|dla|czy|tak|jak|oraz|kod|teraz)\b') {
        return "pl"
    }
    if ($wl.Length -eq 2) { return $wl }
    return "en"
}

function Clean-TextForSpeech([string]$raw) {
    if ([string]::IsNullOrWhiteSpace($raw)) { return "" }
    $c = [regex]::Replace($raw, '(?s)```.*?```', ' ')
    $c = [regex]::Replace($c, '\[([^\]]+)\]\([^\)]+\)', '$1')
    $c = [regex]::Replace($c, 'https?://\S+|file:///\S+', ' ')
    $c = [regex]::Replace($c, '(?m)^\s*/(compact|summarize)\b.*$', ' ')
    $c = [regex]::Replace($c, '(?m)^\s*[-*_]{2,}\s*$', ' ')
    $c = [regex]::Replace($c, '[-20142013]{2,}|(?<=\s)[-20142013](?=\s)', ', ')
    $c = ($c -replace '[`#*~_>|]', ' ') -replace '\s+', ' '
    return $c.Trim()
}

$script:ttsSync = [hashtable]::Synchronized(@{
    Generation = 0
    Command = ""
    State = "Stopped"
    ActiveRequestId = ""
})

$script:recorder = New-Object RamWaveRecorder
$script:recorder.WhisperPort = $WhisperPort
$script:recorder.ConsoleOutLock = $script:outLock

function Start-RamTtsPlayback([string]$rawText, [string]$forceLang, [string]$requestId) {
    $clean = Clean-TextForSpeech $rawText
    if (-not $clean) {
        Emit-Event @{ event = "ttsState"; state = "Stopped"; requestId = $requestId }
        if ($requestId) { Emit-Event @{ event = "ttsFinished"; requestId = $requestId } }
        return
    }

    $myGen = ++$script:ttsSync.Generation
    $script:ttsSync.Command = ""
    $script:ttsSync.ActiveRequestId = $requestId

    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = "MTA"
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    $null = $ps.AddScript({
        param($cleanText, $langHint, $reqId, $myGeneration, $ttsSync, $outLock, $piperExe, $piperPlModel)

        function Send-Msg([hashtable]$h) {
            [System.Threading.Monitor]::Enter($outLock)
            try {
                $j = $h | ConvertTo-Json -Compress -Depth 4
                [Console]::Out.WriteLine($j)
                [Console]::Out.Flush()
            } catch {} finally {
                [System.Threading.Monitor]::Exit($outLock)
            }
        }

        Add-Type -AssemblyName System.Speech
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $null = [Windows.Media.Playback.MediaPlayer, Windows.Media, ContentType = WindowsRuntime]
        $null = [Windows.Media.Core.MediaSource, Windows.Media, ContentType = WindowsRuntime]
        $null = [Windows.Media.MediaPlaybackType, Windows.Media, ContentType = WindowsRuntime]
        $null = [Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
        $null = [Windows.Media.Devices.MediaDevice, Windows.Media.Devices, ContentType = WindowsRuntime]

        # 1. STRICT HEADPHONE ENFORCEMENT (Bluetooth A2DP Stereo OR Wired AUX Headphones ONLY; Speakers & Hands-Free BLOCKED)
        $targetAudioDevice = $null
        try {
            $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
                $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
            })[0]
            $renderSel = [Windows.Media.Devices.MediaDevice]::GetAudioRenderSelector()
            $winRtOp = [Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($renderSel)
            $netTask = $asTaskGeneric.MakeGenericMethod([Windows.Devices.Enumeration.DeviceInformationCollection]).Invoke($null, @($winRtOp))
            $netTask.Wait(3000) | Out-Null
            $renderDevices = $netTask.Result

            $btHeadphones = $null
            $auxHeadphones = $null

            foreach ($dev in $renderDevices) {
                if (-not $dev.IsEnabled) { continue }
                $dn = [string]$dev.Name
                $low = $dn.ToLowerInvariant()

                # Block all Hands-Free / HFP / Headset mono profiles
                if ($low -match 'hands-free|handsfree|headset|ag audio|bthhfenum|hf audio') {
                    continue
                }
                # Block all built-in / external Speakers & Monitor HDMI outputs
                if ($low -match 'speaker|g\u0142o\u015Bnik|loudspeaker|hdmi|displayport|monitor|digital audio|telewizor') {
                    continue
                }
                # Match Bluetooth Stereo A2DP or Wired AUX Headphones
                if ($low -match 'headphone|s\u0142uchawk|earphone|earbud|airpod|buds|baseus|sony|bose|jbl|sennheiser|marshall|anker') {
                    if ($low -match 'aux|jack|realtek|amd high definition|usb|wired|line') {
                        if (-not $auxHeadphones) { $auxHeadphones = $dev }
                    } else {
                        if (-not $btHeadphones) { $btHeadphones = $dev }
                    }
                } elseif ($low -match 'aux|line out') {
                    if (-not $auxHeadphones) { $auxHeadphones = $dev }
                }
            }

            if ($btHeadphones) {
                $targetAudioDevice = $btHeadphones
            } elseif ($auxHeadphones) {
                $targetAudioDevice = $auxHeadphones
            }
        } catch {}

        if (-not $targetAudioDevice) {
            if ($ttsSync.Generation -eq $myGeneration) {
                $ttsSync.State = "Stopped"
                Send-Msg @{ event = "ttsBlockedNoHeadphones"; requestId = $reqId }
                Send-Msg @{ event = "ttsState"; state = "Stopped"; requestId = $reqId }
                if ($reqId) { Send-Msg @{ event = "ttsFinished"; requestId = $reqId } }
            }
            return
        }

        $iso = $langHint
        if (-not $iso) {
            $plRegex = "[\u0105\u0107\u0119\u0142\u0144\u00F3\u015B\u017A\u017C\u0104\u0106\u0118\u0141\u0143\u00D3\u015A\u0179\u017B]"
            if ($cleanText -match $plRegex -or $cleanText -match '\b(jest|nie|dla|czy|tak|jak|oraz|plik|kod|teraz)\b') {
                $iso = "pl"
            } else {
                $iso = "en"
            }
        }

        $voiceName = $null
        $wavBytes = $null

        try {
            if ($iso -eq "pl" -and $piperExe -and $piperPlModel -and (Test-Path $piperExe) -and (Test-Path $piperPlModel)) {
                $voiceName = "MC Speech (Local PL)"
                $ttsSync.State = "Playing"
                Send-Msg @{
                    event = "ttsState"
                    state = "Playing"
                    voice = $voiceName
                    device = $targetAudioDevice.Name
                    lang = $iso
                    requestId = $reqId
                }
                $wavBytes = [RamWaveRecorder]::SynthesizePiperStereo48kWav($piperExe, $piperPlModel, $cleanText, 22050)
            } else {
                $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
                $localVoices = @($synth.GetInstalledVoices() | Where-Object {
                    $_.Enabled -and ($_.VoiceInfo.Name -notmatch 'Online')
                })

                if ($iso -eq "en") {
                    $v = $localVoices | Where-Object { $_.VoiceInfo.Name -eq "Microsoft Ryan" } | Select-Object -First 1
                    if (-not $v) { $v = $localVoices | Where-Object { $_.VoiceInfo.Name -match "Ryan" } | Select-Object -First 1 }
                    if ($v) { $voiceName = $v.VoiceInfo.Name }
                }

                if (-not $voiceName) {
                    $lv = @($localVoices | Where-Object { $_.VoiceInfo.Culture.TwoLetterISOLanguageName -eq $iso })
                    if ($lv.Count -gt 0) {
                        $m = $lv | Where-Object { $_.VoiceInfo.Gender -eq [System.Speech.Synthesis.VoiceGender]::Male } | Select-Object -First 1
                        $voiceName = if ($m) { $m.VoiceInfo.Name } else { $lv[0].VoiceInfo.Name }
                    }
                }
                if (-not $voiceName -and $localVoices.Count -gt 0) {
                    $ry = $localVoices | Where-Object { $_.VoiceInfo.Name -match "Ryan" } | Select-Object -First 1
                    $voiceName = if ($ry) { $ry.VoiceInfo.Name } else { $localVoices[0].VoiceInfo.Name }
                }

                if (-not $voiceName) {
                    $synth.Dispose()
                    throw "Brak zainstalowanego lokalnego glosu offline."
                }

                $synth.SelectVoice($voiceName)
                $synth.Rate = 0

                $ttsSync.State = "Playing"
                Send-Msg @{
                    event = "ttsState"
                    state = "Playing"
                    voice = $voiceName
                    device = $targetAudioDevice.Name
                    lang = $iso
                    requestId = $reqId
                }

                # 2. Synthesize strictly as Stereo, 16-bit, 48000 Hz, 2-channel PCM in pure RAM
                $pcmStream = New-Object System.IO.MemoryStream
                $fmt48kStereo = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(
                    48000,
                    [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
                    [System.Speech.AudioFormat.AudioChannel]::Stereo
                )
                $synth.SetOutputToAudioStream($pcmStream, $fmt48kStereo)
                $synth.Speak($cleanText)
                $rawPcm = $pcmStream.ToArray()
                $pcmStream.Dispose()
                $synth.Dispose()

                if ($rawPcm -and $rawPcm.Length -gt 0) {
                    $wavBytes = [RamWaveRecorder]::WrapPcmStereo48kAsWav($rawPcm)
                }
            }
        } catch {
            if ($ttsSync.Generation -eq $myGeneration) {
                $ttsSync.State = "Stopped"
                Send-Msg @{ event = "ttsState"; state = "Stopped"; requestId = $reqId }
                if ($reqId) { Send-Msg @{ event = "ttsFinished"; requestId = $reqId } }
            }
            return
        }

        if ($ttsSync.Generation -ne $myGeneration -or -not $wavBytes -or $wavBytes.Length -lt 200) {
            if ($ttsSync.Generation -eq $myGeneration) {
                $ttsSync.State = "Stopped"
                Send-Msg @{ event = "ttsState"; state = "Stopped"; requestId = $reqId }
                if ($reqId) { Send-Msg @{ event = "ttsFinished"; requestId = $reqId } }
            }
            return
        }

        $memForWinRt = New-Object System.IO.MemoryStream(,$wavBytes)
        $ras = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($memForWinRt)
        $mediaSource = [Windows.Media.Core.MediaSource]::CreateFromStream($ras, "audio/wav")

        $player = New-Object Windows.Media.Playback.MediaPlayer
        # Bind output directly to the verified Bluetooth Stereo / Wired AUX Headphone device!
        $player.AudioDevice = $targetAudioDevice
        $player.AutoPlay = $true
        $player.CommandManager.IsEnabled = $true
        $smtc = $player.SystemMediaTransportControls
        $smtc.IsEnabled = $true
        $smtc.IsPlayEnabled = $true
        $smtc.IsPauseEnabled = $true
        $smtc.IsStopEnabled = $true

        $updater = $smtc.DisplayUpdater
        $updater.Type = [Windows.Media.MediaPlaybackType]::Music
        $updater.MusicProperties.Title = "whisper_saver"
        $updater.MusicProperties.Artist = $voiceName
        $updater.Update()

        $player.Source = $mediaSource
        $player.Play()

        for ($w = 0; $w -lt 25; $w++) {
            if ($ttsSync.Generation -ne $myGeneration) { break }
            Start-Sleep -Milliseconds 60
            if ($player.PlaybackSession.PlaybackState.ToString() -eq "Playing") { break }
            if ($w -eq 6) { $player.Play() }
        }

        $wasKeyDown = $false
        $lastReported = "Playing"
        $lastChange = [DateTime]::UtcNow

        try {
            while ($ttsSync.Generation -eq $myGeneration) {
                $st = $player.PlaybackSession.PlaybackState.ToString()
                $pos = $player.PlaybackSession.Position.TotalSeconds
                $dur = $player.PlaybackSession.NaturalDuration.TotalSeconds

                if ($st -ne $lastReported -and ($st -eq "Playing" -or $st -eq "Paused")) {
                    $lastReported = $st
                    $ttsSync.State = $st
                    $lastChange = [DateTime]::UtcNow
                    Send-Msg @{ event = "ttsState"; state = $st; voice = $voiceName; device = $targetAudioDevice.Name; lang = $iso; requestId = $reqId }
                }

                $cmd = $ttsSync.Command
                if ($cmd) {
                    $ttsSync.Command = ""
                    if ($cmd -eq "stop") {
                        $player.Pause()
                        break
                    } elseif ($cmd -eq "toggle") {
                        if ($st -eq "Playing") {
                            $player.Pause()
                            $lastReported = "Paused"
                            $ttsSync.State = "Paused"
                            $lastChange = [DateTime]::UtcNow
                            Send-Msg @{ event = "ttsState"; state = "Paused"; voice = $voiceName; device = $targetAudioDevice.Name; lang = $iso; requestId = $reqId }
                        } else {
                            $player.Play()
                            $lastReported = "Playing"
                            $ttsSync.State = "Playing"
                            $lastChange = [DateTime]::UtcNow
                            Send-Msg @{ event = "ttsState"; state = "Playing"; voice = $voiceName; device = $targetAudioDevice.Name; lang = $iso; requestId = $reqId }
                        }
                    }
                }

                $keyDown = ([WhisperNative]::GetAsyncKeyState(0xB3) -band 0x8000) -ne 0
                if ($keyDown -and -not $wasKeyDown) {
                    Start-Sleep -Milliseconds 130
                    $newSt = $player.PlaybackSession.PlaybackState.ToString()
                    if ($newSt -ne $lastReported -and ($newSt -eq "Playing" -or $newSt -eq "Paused")) {
                        $lastReported = $newSt
                        $ttsSync.State = $newSt
                        $lastChange = [DateTime]::UtcNow
                        Send-Msg @{ event = "ttsState"; state = $newSt; voice = $voiceName; device = $targetAudioDevice.Name; lang = $iso; requestId = $reqId }
                    } elseif (([DateTime]::UtcNow - $lastChange).TotalMilliseconds -ge 350) {
                        if ($st -eq "Playing") {
                            $player.Pause()
                            $lastReported = "Paused"
                            $ttsSync.State = "Paused"
                            $lastChange = [DateTime]::UtcNow
                            Send-Msg @{ event = "ttsState"; state = "Paused"; voice = $voiceName; device = $targetAudioDevice.Name; lang = $iso; requestId = $reqId }
                        } else {
                            $player.Play()
                            $lastReported = "Playing"
                            $ttsSync.State = "Playing"
                            $lastChange = [DateTime]::UtcNow
                            Send-Msg @{ event = "ttsState"; state = "Playing"; voice = $voiceName; device = $targetAudioDevice.Name; lang = $iso; requestId = $reqId }
                        }
                    }
                }
                $wasKeyDown = $keyDown

                if ($dur -gt 0.15 -and $pos -ge ($dur - 0.10) -and $lastReported -eq "Playing") {
                    break
                }

                Start-Sleep -Milliseconds 65
            }
        } finally {
            try { $player.Dispose() } catch {}
            try { $mediaSource.Dispose() } catch {}
            try { $ras.Dispose() } catch {}
            try { $memForWinRt.Dispose() } catch {}

            if ($ttsSync.Generation -eq $myGeneration) {
                $ttsSync.State = "Stopped"
                Send-Msg @{ event = "ttsState"; state = "Stopped"; voice = $voiceName; lang = $iso; requestId = $reqId }
                if ($reqId) { Send-Msg @{ event = "ttsFinished"; requestId = $reqId } }
            }
        }
    }).AddArgument($clean).AddArgument($forceLang).AddArgument($requestId).AddArgument($myGen).AddArgument($script:ttsSync).AddArgument($script:outLock).AddArgument($script:piperExe).AddArgument($script:piperPlModel)

    $null = $ps.BeginInvoke()
}

# Background clipboard monitor in RAM (detects PrintScreen / Snipping / Image Copy for auto /compact)
$script:lastClipSeq = [WhisperNative]::GetClipboardSequenceNumber()
$clipTimer = New-Object System.Timers.Timer(900)
$clipTimer.AutoReset = $true
Register-ObjectEvent -InputObject $clipTimer -EventName Elapsed -Action {
    try {
        $seq = [WhisperNative]::GetClipboardSequenceNumber()
        if ($seq -ne $script:lastClipSeq) {
            $script:lastClipSeq = $seq
            if ([WhisperNative]::CheckClipboardHasImage()) {
                Emit-Event @{ event = "clipboardImageDetected"; seq = $seq }
            }
        }
    } catch {}
} | Out-Null
$clipTimer.Start()

# Ensure ultra-fast whisper-server.exe (ggml-small-q5_1.bin on AMD Radeon 780M Vulkan + CPU with -l auto) is running hidden in RAM
try {
    $binDir = Join-Path (Split-Path $PSScriptRoot -Parent) "bin"
    $serverExe = Join-Path $binDir "whisper-server.exe"
    $fastModel = Join-Path $binDir "ggml-small-q5_1.bin"
    if (-not (Test-Path $fastModel)) { $fastModel = Join-Path $binDir "ggml-base.bin" }
    if (Test-Path $serverExe) {
        $needStart = $true
        $existing = Get-CimInstance Win32_Process -Filter "Name = 'whisper-server.exe'" -ErrorAction SilentlyContinue
        foreach ($proc in $existing) {
            if ($proc.CommandLine -match "ggml-small-q5_1\.bin" -and $proc.CommandLine -match "-l auto") {
                $needStart = $false
            } else {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }
        if ($needStart -and (Test-Path $fastModel)) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $serverExe
            $psi.WorkingDirectory = $binDir
            $psi.Arguments = "-m `"$fastModel`" --host 127.0.0.1 --port $WhisperPort -l auto -nt -sns -nf -bo 1 -bs 1 -mc 0 -t 8"
            $psi.CreateNoWindow = $true
            $psi.UseShellExecute = $false
            [void][System.Diagnostics.Process]::Start($psi)
        }
    }
} catch {}

$initMicId = $script:recorder.FindStationaryArrayOrUsbMicId()
Emit-Event @{
    event = "ready"
    whisperPort = $WhisperPort
    micDeviceId = $initMicId
    micName = $script:recorder.ActiveMicName
}

while ($null -ne ($line = [Console]::In.ReadLine())) {
    $trimmed = $line.Trim()
    if (-not $trimmed) { continue }
    try {
        $msg = $trimmed | ConvertFrom-Json
        $cmd = [string]$msg.cmd

        switch ($cmd) {
            "startMic" {
                $ok = $script:recorder.StartManual()
                Emit-Event @{ event = "micState"; recording = $ok; micName = $script:recorder.ActiveMicName }
            }
            "stopMic" {
                $wav = $script:recorder.StopManualAndGetWav()
                Emit-Event @{ event = "micState"; recording = $false }
                if ($wav) {
                    $script:recorder.TranscribeWavAsync($wav, "manual")
                } else {
                    Emit-Event @{ event = "micIdle"; reason = "empty" }
                }
            }
            "setAutoVad" {
                $en = [bool]$msg.enabled
                $script:recorder.SetAutoVad($en)
                Emit-Event @{ event = "autoVadState"; enabled = $en }
            }
            "ttsSpeak" {
                $txt = [string]$msg.text
                $fl = if ($msg.lang) { [string]$msg.lang } else { "" }
                $rid = if ($msg.requestId) { [string]$msg.requestId } else { "" }
                Start-RamTtsPlayback $txt $fl $rid
            }
            "ttsToggle" {
                if ($script:ttsSync.State -eq "Playing" -or $script:ttsSync.State -eq "Paused") {
                    $script:ttsSync.Command = "toggle"
                } else {
                    Emit-Event @{ event = "ttsNeedsText" }
                }
            }
            "ttsStop" {
                $script:ttsSync.Generation++
                $script:ttsSync.Command = "stop"
                $script:ttsSync.State = "Stopped"
                Emit-Event @{ event = "ttsState"; state = "Stopped" }
            }
            "injectChat" {
                $txt = [string]$msg.text
                $rep = if ($null -ne $msg.replace) { [bool]$msg.replace } else { $true }
                $sub = if ($null -ne $msg.submit) { [bool]$msg.submit } else { $false }
                [WhisperNative]::InjectTextOnSta($txt, $rep, $sub)
                Emit-Event @{ event = "injected"; submitted = $sub }
            }
            "pasteImage" {
                $ok = [WhisperNative]::PasteImageOnSta()
                Emit-Event @{ event = "imagePasted"; ok = $ok }
            }
            "captureInput" {
                $cap = [WhisperNative]::CaptureFocusedInputTextOnSta()
                $rid = if ($msg.requestId) { [string]$msg.requestId } else { "" }
                Emit-Event @{ event = "inputCaptured"; text = $cap; requestId = $rid }
            }
            "shutdown" {
                break
            }
        }
    } catch {
        Emit-Event @{ event = "error"; source = "ipc"; message = $_.Exception.Message }
    }
}

$clipTimer.Stop()
$clipTimer.Dispose()
$script:recorder.Dispose()
