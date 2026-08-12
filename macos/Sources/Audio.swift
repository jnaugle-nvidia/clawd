import CoreAudio
import Foundation

// Whether the default output device currently has audio running through it.
//
// Windows can read the endpoint's peak meter, which gives a loudness envelope and with it
// a real tempo. macOS has no equivalent: the only ways to see the signal are audio taps
// and ScreenCaptureKit, both of which genuinely capture the audio and both of which ask
// the user for permission. So this asks the HAL a single yes/no question instead — is
// anything playing — and the pet dances to its own 128 bpm. Nothing is captured, recorded
// or tapped, and nothing needs permission.
public final class MusicMeter
{
    public var MusicActive = false
    public var BeatNow = false               // never fires here: see ProvidesBeats
    public var ProvidesBeats = false         // no envelope, so the pet keeps its own time
    public var BeatInterval = 0.469          // 128 bpm
    public var Env = 0.0, Avg = 0.0          // for the debug dump
    public var MeterState = "new"

    private var pollT = 0.0
    private var loudT = 0.0, quietT = 0.0
    private var running = false

    public init() { }

    public func Poll(_ dt: Double)
    {
        BeatNow = false

        // The HAL call crosses into coreaudiod; five times a second is plenty to notice
        // a track starting, and costs nothing next to doing it every frame.
        pollT -= dt
        if pollT <= 0
        {
            pollT = 0.2
            running = IsOutputRunning()
        }

        Env = running ? 1.0 : 0.0
        Avg += (Env - Avg) * min(1, dt / 1.1)

        // Same hysteresis as the Windows build: a moment of sound before he commits to a
        // dance, and a longer silence before he gives up on it.
        if running { loudT += dt; quietT = 0 }
        else { quietT += dt; loudT = 0 }

        if !MusicActive && loudT > 1.5 { MusicActive = true }
        if MusicActive && quietT > 3.0 { MusicActive = false }
    }

    private func IsOutputRunning() -> Bool
    {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var st = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        if st != noErr || device == 0 { MeterState = "no endpoint (\(st))"; return false }

        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var flag = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        st = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &flag)
        if st != noErr { MeterState = "no running flag (\(st))"; return false }

        MeterState = "connected"
        return flag != 0
    }
}
