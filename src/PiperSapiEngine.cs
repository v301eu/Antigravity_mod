using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;

namespace PiperSapi
{
    [ComImport, Guid("14056581-E16C-11D2-BB90-00C04F8EE6C0"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISpDataKey
    {
        [PreserveSig] int SetData([MarshalAs(UnmanagedType.LPWStr)] string valueName, uint cbData, IntPtr data);
        [PreserveSig] int GetData([MarshalAs(UnmanagedType.LPWStr)] string valueName, ref uint pcbData, IntPtr data);
        [PreserveSig] int SetStringValue([MarshalAs(UnmanagedType.LPWStr)] string valueName, [MarshalAs(UnmanagedType.LPWStr)] string value);
        [PreserveSig] int GetStringValue([MarshalAs(UnmanagedType.LPWStr)] string valueName, [MarshalAs(UnmanagedType.LPWStr)] out string value);
        [PreserveSig] int SetDWORD([MarshalAs(UnmanagedType.LPWStr)] string valueName, uint dwValue);
        [PreserveSig] int GetDWORD([MarshalAs(UnmanagedType.LPWStr)] string valueName, out uint pdwValue);
        [PreserveSig] int OpenKey([MarshalAs(UnmanagedType.LPWStr)] string subKeyName, out ISpDataKey ppSubKey);
        [PreserveSig] int CreateKey([MarshalAs(UnmanagedType.LPWStr)] string subKeyName, out ISpDataKey ppSubKey);
        [PreserveSig] int DeleteKey([MarshalAs(UnmanagedType.LPWStr)] string subKeyName);
        [PreserveSig] int DeleteValue([MarshalAs(UnmanagedType.LPWStr)] string valueName);
        [PreserveSig] int EnumKeys(uint index, [MarshalAs(UnmanagedType.LPWStr)] out string ppszSubKeyName);
        [PreserveSig] int EnumValues(uint index, [MarshalAs(UnmanagedType.LPWStr)] out string ppszValueName);
    }

    [ComImport, Guid("92A66E2B-C830-4149-83DF-6FC2BA1E7A5B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISpRegDataKey
    {
        [PreserveSig] int SetData([MarshalAs(UnmanagedType.LPWStr)] string valueName, uint cbData, IntPtr data);
        [PreserveSig] int GetData([MarshalAs(UnmanagedType.LPWStr)] string valueName, ref uint pcbData, IntPtr data);
        [PreserveSig] int SetStringValue([MarshalAs(UnmanagedType.LPWStr)] string valueName, [MarshalAs(UnmanagedType.LPWStr)] string value);
        [PreserveSig] int GetStringValue([MarshalAs(UnmanagedType.LPWStr)] string valueName, [MarshalAs(UnmanagedType.LPWStr)] out string value);
        [PreserveSig] int SetDWORD([MarshalAs(UnmanagedType.LPWStr)] string valueName, uint dwValue);
        [PreserveSig] int GetDWORD([MarshalAs(UnmanagedType.LPWStr)] string valueName, out uint pdwValue);
        [PreserveSig] int OpenKey([MarshalAs(UnmanagedType.LPWStr)] string subKeyName, out IntPtr ppSubKey);
        [PreserveSig] int CreateKey([MarshalAs(UnmanagedType.LPWStr)] string subKeyName, out IntPtr ppSubKey);
        [PreserveSig] int DeleteKey([MarshalAs(UnmanagedType.LPWStr)] string subKeyName);
        [PreserveSig] int DeleteValue([MarshalAs(UnmanagedType.LPWStr)] string valueName);
        [PreserveSig] int EnumKeys(uint index, [MarshalAs(UnmanagedType.LPWStr)] out string ppszSubKeyName);
        [PreserveSig] int EnumValues(uint index, [MarshalAs(UnmanagedType.LPWStr)] out string ppszValueName);
        [PreserveSig] int SetKey(IntPtr hkey, [MarshalAs(UnmanagedType.Bool)] bool fReadOnly);
    }

    [ComImport, Guid("14056589-E16C-11D2-BB90-00C04F8EE6C0"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISpObjectToken
    {
        [PreserveSig] int SetData([MarshalAs(UnmanagedType.LPWStr)] string valueName, uint cbData, IntPtr data);
        [PreserveSig] int GetData([MarshalAs(UnmanagedType.LPWStr)] string valueName, ref uint pcbData, IntPtr data);
        [PreserveSig] int SetStringValue([MarshalAs(UnmanagedType.LPWStr)] string valueName, [MarshalAs(UnmanagedType.LPWStr)] string value);
        [PreserveSig] int GetStringValue([MarshalAs(UnmanagedType.LPWStr)] string valueName, [MarshalAs(UnmanagedType.LPWStr)] out string value);
        [PreserveSig] int SetDWORD([MarshalAs(UnmanagedType.LPWStr)] string valueName, uint dwValue);
        [PreserveSig] int GetDWORD([MarshalAs(UnmanagedType.LPWStr)] string valueName, out uint pdwValue);
        [PreserveSig] int OpenKey([MarshalAs(UnmanagedType.LPWStr)] string subKeyName, out ISpDataKey ppSubKey);
        [PreserveSig] int CreateKey([MarshalAs(UnmanagedType.LPWStr)] string subKeyName, out ISpDataKey ppSubKey);
        [PreserveSig] int DeleteKey([MarshalAs(UnmanagedType.LPWStr)] string subKeyName);
        [PreserveSig] int DeleteValue([MarshalAs(UnmanagedType.LPWStr)] string valueName);
        [PreserveSig] int EnumKeys(uint index, [MarshalAs(UnmanagedType.LPWStr)] out string ppszSubKeyName);
        [PreserveSig] int EnumValues(uint index, [MarshalAs(UnmanagedType.LPWStr)] out string ppszValueName);
        [PreserveSig] int SetId([MarshalAs(UnmanagedType.LPWStr)] string pszCategoryId, [MarshalAs(UnmanagedType.LPWStr)] string pszTokenId, [MarshalAs(UnmanagedType.Bool)] bool fCreateIfNotExist);
        [PreserveSig] int GetId(out IntPtr ppszCoMemTokenId);
    }

    [ComImport, Guid("5B559F40-E952-11D2-BB91-00C04F8EE6C0"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISpObjectWithToken
    {
        [PreserveSig] int SetObjectToken([MarshalAs(UnmanagedType.Interface)] ISpObjectToken pToken);
        [PreserveSig] int GetObjectToken([MarshalAs(UnmanagedType.Interface)] out ISpObjectToken ppToken);
    }

    [ComImport, Guid("9880499B-CCE9-11D2-B503-00C04F797396"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISpTTSEngineSite
    {
        [PreserveSig] int AddEvents(IntPtr pEventArray, uint ulCount);
        [PreserveSig] int GetEventInterest(out ulong pullEventInterest);
        [PreserveSig] uint GetActions();
        [PreserveSig] int Write(IntPtr pBuff, uint cb, out uint pcbWritten);
        [PreserveSig] int GetRate(out int pRateAdjust);
        [PreserveSig] int GetVolume(out ushort pusVolume);
        [PreserveSig] int GetSkipInfo(out int peType, out int plNumItems);
        [PreserveSig] int CompleteSkip(int ulNumSkipped);
    }

    [ComImport, Guid("A74D7C8E-4CC5-4F2F-A6EB-804DEE18500E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISpTTSEngine
    {
        [PreserveSig] int Speak(uint dwSpeakFlags, ref Guid rguidFormatId, IntPtr pWaveFormatEx, IntPtr pTextFragList, [MarshalAs(UnmanagedType.Interface)] ISpTTSEngineSite pOutputSite);
        [PreserveSig] int GetOutputFormat(ref Guid pTargetFmtId, IntPtr pTargetWaveFormatEx, out Guid pOutputFormatId, out IntPtr ppCoMemOutputWaveFormatEx);
    }

    [ComImport, Guid("06B64F9E-7FDA-11D2-B4F2-00C04F797396"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IEnumSpObjectTokens
    {
        [PreserveSig] int Next(uint celt, IntPtr pelt, IntPtr pceltFetched);
        [PreserveSig] int Skip(uint celt);
        [PreserveSig] int Reset();
        [PreserveSig] int Clone(out IntPtr ppEnum);
        [PreserveSig] int Item(uint Index, out IntPtr ppToken);
        [PreserveSig] int GetCount(out uint pCount);
    }

    [ComImport, Guid("06B64F9F-7FDA-11D2-B4F2-00C04F797396"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface ISpObjectTokenEnumBuilder
    {
        [PreserveSig] int Next(uint celt, IntPtr pelt, IntPtr pceltFetched);
        [PreserveSig] int Skip(uint celt);
        [PreserveSig] int Reset();
        [PreserveSig] int Clone(out IntPtr ppEnum);
        [PreserveSig] int Item(uint Index, out IntPtr ppToken);
        [PreserveSig] int GetCount(out uint pCount);
        [PreserveSig] int SetAttribs([MarshalAs(UnmanagedType.LPWStr)] string pszReqAttribs, [MarshalAs(UnmanagedType.LPWStr)] string pszOptAttribs);
        [PreserveSig] int AddTokens(uint cTokens, ref IntPtr pToken);
        [PreserveSig] int AddTokensFromDataKey(IntPtr pDataKey, [MarshalAs(UnmanagedType.LPWStr)] string pszSubKey, [MarshalAs(UnmanagedType.LPWStr)] string pszCategoryId);
        [PreserveSig] int AddTokensFromTokenEnum(IntPtr pTokenEnum);
    }

    [ComImport, Guid("00000001-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IClassFactory
    {
        [PreserveSig] int CreateInstance(IntPtr pUnkOuter, ref Guid riid, out IntPtr ppvObject);
        [PreserveSig] int LockServer([MarshalAs(UnmanagedType.Bool)] bool fLock);
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SPVPITCH
    {
        public int MiddleAdj;
        public int RangeAdj;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SPVCONTEXT
    {
        public IntPtr pCategory;
        public IntPtr pBefore;
        public IntPtr pAfter;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SPVSTATE
    {
        public int eAction;
        public short LangID;
        public short wReserved;
        public int EmphAdj;
        public int RateAdj;
        public int Volume;
        public SPVPITCH PitchAdj;
        public int SilenceMSecs;
        public IntPtr pPhoneIds;
        public int ePartOfSpeech;
        public SPVCONTEXT Context;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct SPVTEXTFRAG
    {
        public IntPtr pNext;
        public SPVSTATE State;
        public IntPtr pTextStart;
        public int ulTextLen;
        public int ulTextSrcOffset;
    }

    [ComVisible(true)]
    [Guid("D8E7F6A5-B4C3-4D2E-9F1A-0B9C8D7E6F50")]
    [ClassInterface(ClassInterfaceType.None)]
    public class PiperTtsEngine : ISpObjectWithToken, ISpTTSEngine
    {
        private static readonly Guid SPDFID_WaveFormatEx = new Guid("C31ADBAE-527F-4FF5-A230-F62BB61FF70C");
        private ISpObjectToken _token;
        private string _piperExe = @"c:\Users\vr_me\projects\whisper_saver\bin\piper\piper.exe";
        private string _modelPath = @"c:\Users\vr_me\projects\whisper_saver\bin\piper\pl_PL-darkman-medium.onnx";
        private int _sampleRate = 22050;

        public int SetObjectToken(ISpObjectToken pToken)
        {
            _token = pToken;
            if (_token != null)
            {
                string exe;
                if (_token.GetStringValue("PiperExe", out exe) == 0 && !string.IsNullOrEmpty(exe))
                    _piperExe = exe;
                string model;
                if (_token.GetStringValue("ModelPath", out model) == 0 && !string.IsNullOrEmpty(model))
                    _modelPath = model;
                uint rate;
                if (_token.GetDWORD("SampleRate", out rate) == 0 && rate > 0)
                    _sampleRate = (int)rate;
            }
            return 0;
        }

        public int GetObjectToken(out ISpObjectToken ppToken)
        {
            ppToken = _token;
            return 0;
        }

        public int GetOutputFormat(ref Guid pTargetFmtId, IntPtr pTargetWaveFormatEx, out Guid pOutputFormatId, out IntPtr ppCoMemOutputWaveFormatEx)
        {
            pOutputFormatId = SPDFID_WaveFormatEx;
            ppCoMemOutputWaveFormatEx = Marshal.AllocCoTaskMem(18);
            short wFormatTag = 1; // WAVE_FORMAT_PCM
            short nChannels = 1;
            int nSamplesPerSec = _sampleRate;
            short wBitsPerSample = 16;
            short nBlockAlign = (short)(nChannels * (wBitsPerSample / 8));
            int nAvgBytesPerSec = nSamplesPerSec * nBlockAlign;
            short cbSize = 0;

            Marshal.WriteInt16(ppCoMemOutputWaveFormatEx, 0, wFormatTag);
            Marshal.WriteInt16(ppCoMemOutputWaveFormatEx, 2, nChannels);
            Marshal.WriteInt32(ppCoMemOutputWaveFormatEx, 4, nSamplesPerSec);
            Marshal.WriteInt32(ppCoMemOutputWaveFormatEx, 8, nAvgBytesPerSec);
            Marshal.WriteInt16(ppCoMemOutputWaveFormatEx, 12, nBlockAlign);
            Marshal.WriteInt16(ppCoMemOutputWaveFormatEx, 14, wBitsPerSample);
            Marshal.WriteInt16(ppCoMemOutputWaveFormatEx, 16, cbSize);
            return 0;
        }

        public int Speak(uint dwSpeakFlags, ref Guid rguidFormatId, IntPtr pWaveFormatEx, IntPtr pTextFragList, ISpTTSEngineSite pOutputSite)
        {
            if (pOutputSite == null || pTextFragList == IntPtr.Zero) return 0;

            StringBuilder sb = new StringBuilder();
            IntPtr cur = pTextFragList;
            while (cur != IntPtr.Zero)
            {
                SPVTEXTFRAG frag = (SPVTEXTFRAG)Marshal.PtrToStructure(cur, typeof(SPVTEXTFRAG));
                // SPVA_Speak = 0, SPVA_SpellOut = 4
                if ((frag.State.eAction == 0 || frag.State.eAction == 4) && frag.pTextStart != IntPtr.Zero && frag.ulTextLen > 0)
                {
                    string chunk = Marshal.PtrToStringUni(frag.pTextStart, frag.ulTextLen);
                    if (!string.IsNullOrEmpty(chunk))
                    {
                        if (sb.Length > 0) sb.Append(' ');
                        sb.Append(chunk);
                    }
                }
                cur = frag.pNext;
            }

            string fullText = sb.ToString().Trim();
            if (string.IsNullOrEmpty(fullText)) return 0;
            if (!File.Exists(_piperExe) || !File.Exists(_modelPath)) return 0;

            try
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = _piperExe;
                psi.Arguments = "--model \"" + _modelPath + "\" --output_raw";
                psi.WorkingDirectory = Path.GetDirectoryName(_piperExe);
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardInput = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;

                using (Process proc = Process.Start(psi))
                {
                    byte[] utf8 = Encoding.UTF8.GetBytes(fullText + "\n");
                    proc.StandardInput.BaseStream.Write(utf8, 0, utf8.Length);
                    proc.StandardInput.BaseStream.Flush();
                    proc.StandardInput.Close();

                    byte[] buf = new byte[8192];
                    IntPtr unmanagedBuf = Marshal.AllocHGlobal(buf.Length);
                    try
                    {
                        Stream stdout = proc.StandardOutput.BaseStream;
                        int read;
                        while ((read = stdout.Read(buf, 0, buf.Length)) > 0)
                        {
                            // Check SPVES_ABORT (2)
                            if ((pOutputSite.GetActions() & 2) != 0)
                            {
                                try { proc.Kill(); } catch { }
                                break;
                            }
                            Marshal.Copy(buf, 0, unmanagedBuf, read);
                            uint written;
                            pOutputSite.Write(unmanagedBuf, (uint)read, out written);
                        }
                    }
                    finally
                    {
                        Marshal.FreeHGlobal(unmanagedBuf);
                    }
                    proc.WaitForExit(3000);
                }
            }
            catch
            {
            }
            return 0;
        }
    }

    [ComVisible(true)]
    [Guid("B8B9E38F-E5A2-4661-9FDE-4AC7377AA6F6")]
    [ClassInterface(ClassInterfaceType.None)]
    public class PiperAndNaturalVoiceEnumerator : IEnumSpObjectTokens
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibrary(string lpFileName);

        [DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
        private static extern IntPtr GetProcAddress(IntPtr hModule, string lpProcName);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int DllGetClassObjectDelegate(ref Guid rclsid, ref Guid riid, out IntPtr ppv);

        private ISpObjectTokenEnumBuilder _builder;

        public PiperAndNaturalVoiceEnumerator()
        {
            Type tBuilder = Type.GetTypeFromCLSID(new Guid("3918D75F-0ACB-41F2-B733-92AA15BCECF6"));
            _builder = (ISpObjectTokenEnumBuilder)Activator.CreateInstance(tBuilder);
            _builder.SetAttribs(null, null);

            // 1. Add tokens from NaturalVoiceSAPIAdapter.dll (e.g., Microsoft Ryan)
            try
            {
                string arch = (IntPtr.Size == 8) ? "x64" : "x86";
                string dllPath = @"C:\Users\vr_me\Downloads\NaturalVoiceSAPIAdapter_v0.2.11_x86_x64\" + arch + @"\NaturalVoiceSAPIAdapter.dll";
                if (File.Exists(dllPath))
                {
                    IntPtr hMod = LoadLibrary(dllPath);
                    if (hMod != IntPtr.Zero)
                    {
                        IntPtr pProc = GetProcAddress(hMod, "DllGetClassObject");
                        if (pProc != IntPtr.Zero)
                        {
                            DllGetClassObjectDelegate getClassObj = (DllGetClassObjectDelegate)Marshal.GetDelegateForFunctionPointer(pProc, typeof(DllGetClassObjectDelegate));
                            Guid clsid = new Guid("B8B9E38F-E5A2-4661-9FDE-4AC7377AA6F6");
                            Guid iidCF = new Guid("00000001-0000-0000-C000-000000000046");
                            IntPtr pCF;
                            if (getClassObj(ref clsid, ref iidCF, out pCF) == 0 && pCF != IntPtr.Zero)
                            {
                                IClassFactory cf = (IClassFactory)Marshal.GetObjectForIUnknown(pCF);
                                Guid iidEnum = new Guid("06B64F9E-7FDA-11D2-B4F2-00C04F797396");
                                IntPtr pNatEnum;
                                if (cf.CreateInstance(IntPtr.Zero, ref iidEnum, out pNatEnum) == 0 && pNatEnum != IntPtr.Zero)
                                {
                                    _builder.AddTokensFromTokenEnum(pNatEnum);
                                    Marshal.Release(pNatEnum);
                                }
                                Marshal.Release(pCF);
                            }
                        }
                    }
                }
            }
            catch { }

            // 2. Add Piper TTS tokens from HKCU\Software\PiperSapiEngine\Tokens
            try
            {
                using (RegistryKey rk = Registry.CurrentUser.OpenSubKey(@"Software\PiperSapiEngine", false))
                {
                    if (rk != null)
                    {
                        Type tKey = Type.GetTypeFromCLSID(new Guid("D9F6EE60-58C9-458B-88E1-2F908FD7F87C"));
                        ISpRegDataKey regKey = (ISpRegDataKey)Activator.CreateInstance(tKey);
                        if (regKey.SetKey(rk.Handle.DangerousGetHandle(), true) == 0)
                        {
                            IntPtr pKeyUnk = Marshal.GetIUnknownForObject(regKey);
                            _builder.AddTokensFromDataKey(pKeyUnk, "Tokens", @"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech\Voices\TokenEnums\NaturalVoiceEnumerator");
                            Marshal.Release(pKeyUnk);
                        }
                    }
                }
            }
            catch { }
        }

        public int Next(uint celt, IntPtr pelt, IntPtr pceltFetched)
        {
            return _builder.Next(celt, pelt, pceltFetched);
        }

        public int Skip(uint celt)
        {
            return _builder.Skip(celt);
        }

        public int Reset()
        {
            return _builder.Reset();
        }

        public int Clone(out IntPtr ppEnum)
        {
            return _builder.Clone(out ppEnum);
        }

        public int Item(uint Index, out IntPtr ppToken)
        {
            return _builder.Item(Index, out ppToken);
        }

        public int GetCount(out uint pCount)
        {
            return _builder.GetCount(out pCount);
        }
    }
}
