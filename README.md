# NotchPrompter

[![NotchPrompter on apps.gauranshsharma.com](https://img.shields.io/badge/read%20more-apps.gauranshsharma.com-ffd43b?style=for-the-badge&labelColor=17130f)](https://apps.gauranshsharma.com/notchprompter/)
[![Platform: macOS 14 or later](https://img.shields.io/badge/platform-macOS%2014%2B-f4f4f7?style=for-the-badge&labelColor=17130f)](https://apps.gauranshsharma.com/notchprompter/)
[![Built with Swift + SwiftUI](https://img.shields.io/badge/built%20with-Swift%20%2B%20SwiftUI-f4f4f7?style=for-the-badge&labelColor=17130f)](https://apps.gauranshsharma.com/notchprompter/)

A teleprompter that lives in your Mac's notch. Your script floats above the menu bar, right under the camera, so you read and look into the lens at the same time.

Menu-bar app, no Dock icon, native SwiftUI + AppKit. Built for macOS 14 and later.

## What it does

**Prompter panel**
- Borderless floating panel pinned over the menu bar / notch, above full-screen apps
- Left, center, right or free-dragged placement, on any connected display
- Adjustable width, height and top offset; fades at the top and bottom edges
- Mirror mode for teleprompter glass
- Drag the text to scrub, or turn on click-through so the panel ignores the mouse entirely

**Hidden from recordings**
- One toggle keeps the panel out of screen recordings and screen shares (`NSWindow.sharingType = .none`), so it is visible to you and invisible to your audience

**Scrolling**
- Steady auto-scroll at a speed you set, with countdown, loop and auto-start
- Progress bar along the bottom edge, per-frame smooth via `CADisplayLink`

**Voice follow**
- On-device speech recognition tracks where you are in the script and scrolls to match
- Survives pauses, ad-libs and skipped paragraphs: a fuzzy matcher scores the last few spoken words against every position within a look-ahead window
- Lines in brackets — `[Pause]`, `(beat)` — render as dimmed stage directions and are skipped by the matcher
- Recognition sessions rotate automatically so the ~1 minute task limit never interrupts a take

**Everything else**
- Script editor with word count, read time, scroll time, plain-text and RTF import, export
- Font style (Default / Serif / Round / Mono / Dyslexic-friendly), size, line spacing, alignment
- Text, background and spoken-line colors; background opacity; corner radius
- Global shortcuts for play/pause, show/hide, restart, speed, nudge and voice — they work while you are recording in another app
- Launch at login

## Build and run

```bash
xcodebuild -project NotchPrompter.xcodeproj -scheme NotchPrompter -configuration Debug build
```

Or open `NotchPrompter.xcodeproj` in Xcode and hit Run.

The app signs ad-hoc (`CODE_SIGN_IDENTITY = "-"`) so it builds with no team configured. Set `DEVELOPMENT_TEAM` and switch `CODE_SIGN_STYLE` to `Automatic` before distributing.

Regenerate the app icon after editing `Tools/make-icon.swift`:

```bash
swift Tools/make-icon.swift
```

## Permissions

Voice follow asks for Microphone and Speech Recognition the first time you enable it. Recognition stays on-device by default — no audio leaves the Mac. Everything else needs no permissions; the global shortcuts use Carbon hot keys, so there is no Accessibility prompt.

## Default shortcuts

| Action | Shortcut |
| --- | --- |
| Play / Pause | ⌥⌘P |
| Show / Hide prompter | ⌥⌘N |
| Back to start | ⌥⌘R |
| Scroll faster / slower | ⌥⌘↑ / ⌥⌘↓ |
| Nudge down / up | ⌥⌘→ / ⌥⌘← |
| Toggle voice follow | ⌥⌘V |

All rebindable in Settings › Shortcuts.

## Layout

```
NotchPrompter/
  NotchPrompterApp.swift    menu bar extra, app delegate
  Models/                   settings store, script parsing
  Prompter/                 panel, scroll engine, display link, notch geometry
  Voice/                    speech recognition, fuzzy script matcher
  Shortcuts/                Carbon hot keys, key recorder
  UI/                       settings window and its panes
  Support/                  login item, color helpers
Tools/make-icon.swift       app icon generator
```

The Xcode target uses a synchronized folder group, so new files under `NotchPrompter/` are picked up without editing the project file.
