using System;
using System.Runtime.InteropServices;

namespace Clawd
{
    // Core Audio: the endpoint's peak meter. This reads a single loudness number per
    // tick from whatever is playing - it never captures or records any audio.
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorCom { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams,
                                   [MarshalAs(UnmanagedType.IUnknown)] out object ppv);
    }

    [ComImport, Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioMeterInformation
    {
        [PreserveSig] int GetPeakValue(out float peak);
    }

    // Watches the default output's loudness and turns it into "music is playing" plus
    // beat events with an estimated tempo.
    public class MusicMeter
    {
        public bool MusicActive;
        public bool BeatNow;             // true only on the tick a beat fired
        public double BeatInterval = 0.5;
        public double Env, Avg;          // for the debug dump
        public string MeterState = "new";

        static readonly Guid IID_Meter = new Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064");
        const int ERender = 0, EMultimedia = 1, ClsCtxAll = 0x17;

        IAudioMeterInformation meter;
        object enumObj, devObj;
        double retryT, refreshT;
        double env, avg, sinceBeat = 10, loudT, quietT;

        void Connect()
        {
            Release();
            try
            {
                MMDeviceEnumeratorCom com = new MMDeviceEnumeratorCom();
                enumObj = com;
                IMMDeviceEnumerator en = (IMMDeviceEnumerator)com;
                IMMDevice dev;
                int hr = en.GetDefaultAudioEndpoint(ERender, EMultimedia, out dev);
                if (hr != 0 || dev == null) { MeterState = "endpoint hr=" + hr; return; }
                devObj = dev;
                Guid iid = IID_Meter;
                object o;
                hr = dev.Activate(ref iid, ClsCtxAll, IntPtr.Zero, out o);
                if (hr != 0) { MeterState = "activate hr=" + hr; return; }
                meter = o as IAudioMeterInformation;
                MeterState = meter != null ? "connected" : "cast failed";
            }
            catch (Exception ex) { meter = null; MeterState = "ex: " + ex.GetType().Name; }
        }

        void Release()
        {
            try { if (meter != null) Marshal.ReleaseComObject(meter); } catch { }
            try { if (devObj != null) Marshal.ReleaseComObject(devObj); } catch { }
            try { if (enumObj != null) Marshal.ReleaseComObject(enumObj); } catch { }
            meter = null; devObj = null; enumObj = null;
        }

        public void Poll(double dt)
        {
            BeatNow = false;
            sinceBeat += dt;

            if (meter == null)
            {
                retryT -= dt;
                if (retryT <= 0) { retryT = 4; Connect(); }
                if (meter == null) { GoQuiet(dt); return; }
            }

            // Re-resolve occasionally so a changed default device gets picked up.
            refreshT -= dt;
            if (refreshT <= 0)
            {
                refreshT = 20;
                Connect();
                if (meter == null) { GoQuiet(dt); return; }
            }

            float peak = 0f;
            try
            {
                if (meter.GetPeakValue(out peak) != 0) { meter = null; GoQuiet(dt); return; }
            }
            catch { meter = null; GoQuiet(dt); return; }

            // Fast-attack, slow-release envelope over a rolling average. A beat is the
            // envelope popping clear of the average.
            env = peak > env ? peak : env + (peak - env) * Math.Min(1, dt * 7);
            avg += (env - avg) * Math.Min(1, dt / 1.1);
            Env = env; Avg = avg;

            if (env > avg * 1.32 + 0.006 && env > 0.012 && sinceBeat > 0.22)
            {
                if (sinceBeat < 2.0)
                {
                    double iv = sinceBeat < 0.25 ? 0.25 : (sinceBeat > 1.2 ? 1.2 : sinceBeat);
                    BeatInterval += (iv - BeatInterval) * 0.35;
                }
                sinceBeat = 0;
                BeatNow = true;
            }

            if (avg > 0.006) { loudT += dt; quietT = 0; }
            else { quietT += dt; if (quietT > 1.2) loudT = 0; }

            if (!MusicActive && loudT > 1.5) MusicActive = true;
            if (MusicActive && quietT > 3.0) MusicActive = false;
        }

        void GoQuiet(double dt)
        {
            env += (0 - env) * Math.Min(1, dt * 4);
            avg += (0 - avg) * Math.Min(1, dt * 4);
            quietT += dt; loudT = 0;
            if (MusicActive && quietT > 3.0) MusicActive = false;
        }
    }
}
