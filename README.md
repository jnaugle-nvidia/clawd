# Claude Pet

Clawd lives on your desktop. He drifts around the screen, notices when you switch
apps, flies over and perches on the window you're working in, rides along when you
drag that window, naps when you go idle, and can be picked up and thrown.

![Clawd](assets/claude-pet-256.png)

A single ~60 KB executable. **Nothing to install** — no runtime, no SDK, no packages.
It compiles against the C# compiler and WPF assemblies that already ship with Windows.

## Run it

```bash
C:\Users\jnaug\Documents\Toolz\claude-pet\bin\ClaudePet.exe
```

To start it with Windows, right-click Clawd → **Start with Windows**.

## Rebuild after changing the source

```bash
C:\Users\jnaug\Documents\Toolz\claude-pet\build.cmd
```

The icon is generated separately (only needed if you change the artwork):

```bash
node C:\Users\jnaug\Documents\Toolz\claude-pet\tools\make-icon.mjs
```

## Controls

| Action | What happens |
| --- | --- |
| Click him | He's pleased — hearts, a little hop |
| Drag him | Pick him up; let go to throw. He tumbles, bounces off the edges and the taskbar, lands dizzy |
| Right-click him | The menu |
| Hover over him | He waves his claws |
| Move the mouse fast right at him | Startled — he bolts |
| Double-click the tray icon | He comes to your cursor |

The menu (right-click him, or the tray icon):

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
- **Start with Windows**, **Quit**

Settings persist in `%APPDATA%\ClaudePet\settings.ini`.

## Dancing

When **Dance to music** is on and sound has been playing for a couple of seconds, he
finds a spot on the floor (or stays on his perch) and dances: hops and squashes on the
beat, claws alternating or both up, legs kicking, body swaying side to side, and every
sixteen beats a quarter-turn twirl. He follows the *actual* beat — the beat detector
watches the system output's loudness envelope and locks onto the tempo, so a 120 bpm
track gets 120 bpm hops. Music stopping sends him back to whatever he was doing.

Two honest notes:

- **He reads loudness, not audio.** The detector polls the endpoint's peak meter
  (`IAudioMeterInformation`) — one number per tick. Nothing is captured or recorded.
- **He can't tell podcasts from techno.** Any sustained sound counts as music, so a
  video call can start a dance party. That's what the toggle is for.

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

| File | Role |
| --- | --- |
| `src/Native.cs` | Win32: window enumeration, DWM frame bounds, cursor, idle time, DPI |
| `src/Audio.cs` | Core Audio peak meter + beat detection (loudness only, no capture) |
| `src/Desktop.cs` | Live picture of the desktop's top-level windows; foreground changes |
| `src/Pet.cs` | Physics and the behaviour state machine. No UI code |
| `src/Character.cs` | The artwork. A unit grid snapped to whole pixels |
| `src/Overlay.cs` | The transparent always-on-top window and mouse input |
| `src/Tray.cs` | Tray icon (drawn at runtime) and menu |
| `src/Settings.cs`, `src/App.cs` | Persistence, entry point, single-instance lock |

Some details that matter:

- The overlay window is only as big as Clawd and **moves with him** rather than being a
  full-screen overlay. A full-screen transparent window would have to recomposite the
  whole screen every frame.
- It carries `WS_EX_NOACTIVATE` and answers `WM_MOUSEACTIVATE` with `MA_NOACTIVATE`, so
  clicking him **never steals focus** from what you're typing in.
- Transparent pixels pass clicks through to the app underneath. That's why there's no
  soft glow around him — a faint halo would be an invisible click-blocker.
- Rendering is deliberately **not** driven by `CompositionTarget.Rendering`; subscribing
  to that pins WPF's render loop open at full frame rate forever. A timer plus a
  "has the pose actually changed" check keeps him at ~2.6% of one core and ~19 MB, and
  moving him costs only a `SetWindowPos`, no repaint.
- Everything is computed in physical pixels, so it behaves on a scaled display. It marks
  itself system-DPI-aware; on a multi-monitor setup with *mixed* scaling factors he may
  render slightly off-size on the secondary monitor.

## Notes

- Windows 11 files new tray icons into the overflow flyout (the `^` next to the clock).
  Drag it onto the taskbar to keep it visible. You can always right-click Clawd himself
  for the same menu.
- He stays on top of normal windows, but an exclusive-fullscreen game will cover him.
- If he ever misbehaves, `%APPDATA%\ClaudePet\error.log` holds the first exception.
- For live diagnostics, create an empty file `%APPDATA%\ClaudePet\debug.on` — he then
  writes a once-a-second status line (state, music meter, position) to `status.txt`
  in the same folder. Delete `debug.on` to stop.
