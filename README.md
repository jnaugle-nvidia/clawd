# Claude Pet

Clawd lives on your desktop. He drifts around the screen, notices when you switch
apps, flies over and perches on the window you're working in, rides along when you
drag that window, naps when you go idle, and can be picked up and thrown.

![Clawd](assets/claude-pet-256.png)

Runs on **Windows** and **macOS**. Either way it's a single small binary with
**nothing to install** — no runtime, no SDK, no packages. On Windows it compiles against
the C# compiler and WPF assemblies that already ship with the OS; on macOS it compiles
against the Swift compiler in the Xcode Command Line Tools.

## Run it

**Windows**

```bash
bin\ClaudePet.exe
```

To start it with Windows, right-click Clawd → **Start with Windows**.

**macOS**

```bash
open bin/ClaudePet.app
```

To start it at login, click the menu-bar crab → **Open at login**.

He needs **no permissions at all** on macOS: no Accessibility, no Screen Recording, no
microphone. See [Permissions](#permissions-macos) for why, and what he gives up for it.

## Rebuild after changing the source

**Windows**

```bash
build.cmd
```

**macOS**

```bash
./macos/build.sh
```

The macOS build needs the Xcode Command Line Tools. If `swiftc` isn't there yet:

```bash
xcode-select --install
```

It produces a universal (Apple silicon + Intel) `bin/ClaudePet.app`, ad-hoc signed.

The icon is generated separately (only needed if you change the artwork):

```bash
node tools/make-icon.mjs
```

## Controls

| Action | What happens |
| --- | --- |
| Click him | He's pleased — hearts, a little hop |
| Drag him | Pick him up; let go to throw. He tumbles, bounces off the edges and the taskbar, lands dizzy |
| Right-click him | The menu |
| Hover over him | He waves his claws |
| Move the mouse fast right at him | Startled — he bolts |
| Double-click the tray icon *(Windows)* | He comes to your cursor |
| Click the menu-bar crab *(macOS)* | The menu — **Come here** is the first item |

The menu (right-click him, or the tray / menu-bar icon):

- **Come here** / **Say something** / **Dance!** — Dance! forces a 12-second dance,
  synced to real music if any is playing, otherwise to his internal 128 bpm
- **Follow my cursor** — he orbits your pointer instead of wandering
- **Perch on windows** — on by default; turn it off and he ignores your windows
- **Dance to music** — on by default; when sound is playing he drops what he's doing
  and dances to it (see below)
- **Hologram glitch** — off by default; he flickers like a failing hologram
- **Chatty** — the occasional short remark
- **Click through pet** — he stops intercepting clicks entirely; purely decorative
- **Size** — Small / Medium / Large
- **Pause** — hide him without quitting
- **Start with Windows** / **Open at login**, **Quit**

Settings persist in `%APPDATA%\ClaudePet\settings.ini` on Windows and
`~/Library/Application Support/ClaudePet/settings.ini` on macOS. Same file format.

## Dancing

When **Dance to music** is on and sound has been playing for a couple of seconds, he
finds a spot on the floor (or stays on his perch) and dances: hops and squashes on the
beat, claws alternating or both up, legs kicking, body swaying side to side, and every
sixteen beats a quarter-turn twirl. Music stopping sends him back to whatever he was doing.

**On Windows he follows the *actual* beat.** The beat detector watches the system
output's loudness envelope and locks onto the tempo, so a 120 bpm track gets 120 bpm hops.

**On macOS he dances at his own 128 bpm.** macOS has no way to read output loudness
without genuinely capturing the audio — the only routes are audio taps and
ScreenCaptureKit, both of which record the signal and both of which prompt for
permission. So he asks the audio system a single yes/no question instead, and keeps his
own time. It's a fair trade for a pet that needs no permissions.

Three honest notes:

- **He reads loudness, not audio.** On Windows the detector polls the endpoint's peak
  meter (`IAudioMeterInformation`) — one number per tick. On macOS it polls the output
  device's `kAudioDevicePropertyDeviceIsRunningSomewhere` — one boolean per tick. Nothing
  is captured or recorded on either.
- **He can't tell podcasts from techno.** Any sustained sound counts as music, so a
  video call can start a dance party. That's what the toggle is for.
- **On macOS he can't tell playing from paused, either.** An app that holds the output
  device open while sitting silent still reads as "something is playing".

## Hologram glitch

With **Hologram glitch** on, every few seconds he degrades for a fraction of a second:
cyan and red ghost copies split off, the sprite slices into bands that jump sideways,
odd bands drop out entirely, and a scanline shimmer runs over the body. Then the signal
recovers. It combines with everything else — he can glitch mid-dance, mid-perch, or
in his sleep.

## What he does on his own

- **Perches.** Sits on a window's top edge and walks along it. On a maximised window
  he sits on the title bar. He re-reads the window's real bounds every frame, so he
  rides along when you move or resize it, and hops off startled if it closes or minimises.
- **Follows your attention.** When the foreground window changes he reacts and flies
  over to the new one (rate-limited, so alt-tabbing doesn't send him into a frenzy).
- **Watches the cursor.** His eyes track your pointer wherever it is on screen.
- **Sleeps.** After 3 minutes with no keyboard or mouse input he settles down, shuts his
  eyes and floats z's. Any input wakes him.
- **Blinks, bobs, squashes when he moves, tucks his legs in mid-air, and swings them
  when he walks.**

Moods show in his eyes: neutral squares, `^ ^` when happy, wide when startled, closed
bars when sleepy, and spirals when he's dizzy from a throw.

## How it works

The two builds are separate programs that behave the same way. Each file has a
counterpart on the other side, and the physics, the state machine and the artwork are
the same code translated.

| Role | Windows (`src/`, C# + WPF) | macOS (`macos/Sources/`, Swift + AppKit) |
| --- | --- | --- |
| Screens, cursor, idle time | `Native.cs` — Win32, DPI | `Native.swift` — NSScreen, CGEventSource |
| The desktop's windows | `Desktop.cs` — `EnumWindows`, DWM frame bounds | `Desktop.swift` — `CGWindowListCopyWindowInfo` |
| Sound detection | `Audio.cs` — Core Audio peak meter + beat detection | `Audio.swift` — Core Audio device state |
| Physics and behaviour | `Pet.cs` | `Pet.swift` |
| The artwork | `Character.cs` — `DrawingContext` | `Character.swift` — `CGContext` |
| The overlay window | `Overlay.cs` — layered `Window` | `Overlay.swift` — non-activating `NSPanel` |
| Icon and menu | `Tray.cs` — `NotifyIcon` | `Tray.swift` — `NSStatusItem` |
| Persistence, entry point | `Settings.cs`, `App.cs` | `Settings.swift`, `main.swift` |

Some details that matter:

- **One coordinate system.** Win32 and `CGWindowListCopyWindowInfo` both report positions
  with the origin at the top-left and y growing downward. The macOS port keeps that sense
  everywhere and converts only at the one place AppKit insists on its own — setting the
  overlay window's origin — so the behaviour code reads the same on both sides.
- The overlay window is only as big as Clawd and **moves with him** rather than being a
  full-screen overlay. A full-screen transparent window would have to recomposite the
  whole screen every frame.
- **Clicking him never steals focus** from what you're typing in. On Windows that's
  `WS_EX_NOACTIVATE` plus answering `WM_MOUSEACTIVATE` with `MA_NOACTIVATE`; on macOS
  it's a `.nonactivatingPanel` that refuses to become key, in an app that never leaves
  `.accessory` activation.
- **Clicks pass through to the app underneath.** On Windows transparent pixels do that by
  themselves, which is why there's no soft glow around him — a faint halo would be an
  invisible click-blocker. AppKit windows are plain rectangles as far as event routing is
  concerned, so the macOS build instead toggles `ignoresMouseEvents` every frame based on
  whether the cursor is actually on the crab.
- Rendering is deliberately **not** driven by a per-frame render callback
  (`CompositionTarget.Rendering`, or a `CVDisplayLink`); subscribing to one pins the
  render loop open at full frame rate forever. A timer plus a "has the pose actually
  changed" check keeps him cheap, and moving him costs only a window move, no repaint.
- Everything is computed in one unit — physical pixels on Windows, points on macOS — so
  he behaves on a scaled display. On Windows he marks himself system-DPI-aware, so on a
  multi-monitor setup with *mixed* scaling factors he may render slightly off-size on the
  secondary monitor; on macOS points already handle that case.

## Permissions (macOS)

Clawd asks for nothing, and macOS never prompts. Everything he does is unprivileged:

| What he needs | How he gets it | Permission |
| --- | --- | --- |
| Where your windows are | `CGWindowListCopyWindowInfo` bounds | none |
| Which app you're in | `kCGWindowOwnerName`, `NSWorkspace` | none |
| Whether you've gone idle | `CGEventSource.secondsSinceLastEventType` | none |
| Where the cursor is | `NSEvent.mouseLocation` | none |
| Whether sound is playing | Core Audio device state | none |

The one thing this costs him: **window titles are redacted** without Screen Recording,
so where the Windows build digs the app's name out of the title bar, the macOS build uses
the window's owning application name. He says "ooh, Visual Studio Code" either way, and
he never asks for the permission that would let him read what's *in* your windows.

## Notes

- Windows 11 files new tray icons into the overflow flyout (the `^` next to the clock).
  Drag it onto the taskbar to keep it visible. You can always right-click Clawd himself
  for the same menu.
- He stays on top of normal windows, but an exclusive-fullscreen game will cover him.
  On macOS he follows you between Spaces.
- macOS may warn that the app is from an unidentified developer the first time, since the
  build is only ad-hoc signed. Right-click the app → **Open**, or allow it in
  System Settings → Privacy & Security.
- If he ever misbehaves, `error.log` in the settings folder holds the first exception.
- For live diagnostics, create an empty file `debug.on` in the settings folder — he then
  writes a once-a-second status line (state, music meter, position) to `status.txt`
  in the same folder. Delete `debug.on` to stop.
