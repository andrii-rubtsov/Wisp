# Task: Wisp UI Improvements — Per-Model Shortcuts, Menu Bar Icon & Recording Indicator

## Repository
https://github.com/andrii-rubtsov/Wisp

## Context
Wisp is a macOS dictation app (Swift/SwiftUI) with two speech engines: Whisper and Parakeet. Currently there is ONE global shortcut that triggers recording with whichever engine is currently selected. The app lives in the macOS menu bar.

See the current UI screenshots for reference — the Settings window has 4 tabs: Shortcuts, Model, Transcription, Advanced.

---

## Feature 1: Per-Model Keyboard Shortcuts

### Current behavior
- One global shortcut (e.g. Left ⌘ as Single Modifier Key) triggers recording
- User must manually switch engine in Settings → Model tab before recording
- Shortcut is configured in Settings → Shortcuts tab

### Desired behavior
- Each engine/model combination gets its own shortcut
- Example: Left ⌘ → Parakeet TDT 0.6B v3, Right ⌥ → Whisper Turbo V3 Large
- User presses the shortcut → app automatically uses the corresponding engine, no need to switch in settings
- The first configured shortcut is the "primary/default" one

### Implementation guidance
- Modify Settings → Shortcuts tab to show a list of shortcut bindings
- Each binding has: Shortcut key/combo + Engine (Parakeet/Whisper) + Model (specific model within engine)
- Add/remove bindings with + / - buttons
- Store bindings in UserDefaults as an array of structs
- In `ShortcutManager.swift` (or wherever global hotkeys are registered), register ALL configured shortcuts
- When a shortcut fires, look up which engine+model it maps to, temporarily switch to that engine, then start recording
- After transcription completes, no need to switch back — just use whatever engine the shortcut specified

### UI mockup (Settings → Shortcuts tab)
```
Recording Shortcuts
┌─────────────────────────────────────────────────┐
│ ⌘ Left Command    │ Parakeet │ TDT 0.6B v3  │ ✕ │
│ ⌥ Right Option    │ Whisper  │ Turbo V3 Lg  │ ✕ │
│                              [+ Add Shortcut]    │
└─────────────────────────────────────────────────┘

Recording Behavior
┌─────────────────────────────────────────────────┐
│ Hold to Record                            [ON]  │
│ Play sound when recording starts          [OFF] │
└─────────────────────────────────────────────────┘
```

### Files likely affected
- `Wisp/ShortcutManager.swift` — register multiple hotkeys
- `Wisp/Settings.swift` — UI for shortcut list, data model for bindings
- `Wisp/TranscriptionService.swift` — accept engine+model parameter when starting recording
- `Wisp/ModifierKeyMonitor.swift` — may need to handle multiple modifier keys
- `Wisp/ContentView.swift` — shortcut display

---

## Feature 2: Custom Menu Bar Icon

### Current behavior
- Menu bar shows a generic icon (cat/default from original fork)
- Clicking shows menu: Wisp, Language >, Microphone >, Quit

### Desired behavior
- Custom menu bar icon that represents "voice/speech" — a small side-profile silhouette with sound waves
- The icon should be a proper macOS template image (monochrome, adapts to light/dark menu bar)
- Size: 18x18 pt (@1x) and 36x36 pt (@2x) — standard macOS menu bar icon sizes

### Implementation guidance
- Create `StatusBarIcon.pdf` or `StatusBarIcon@1x.png` + `StatusBarIcon@2x.png`
- The icon should be a simplified side profile of lips/mouth with 2-3 sound wave arcs
- Must be monochrome (black on transparent) — macOS will automatically invert for dark menu bar when using template images
- Place in `Assets.xcassets` as an Image Set with "Render As: Template Image"
- Reference in code wherever `NSStatusBar` icon is set (likely in `WispApp.swift` or `AppDelegate`)

### Design spec for the icon
- 18x18pt canvas
- Left side: simplified lips/mouth profile (just the lower face outline — nose tip, lips, chin)
- Right side: 2-3 concentric arcs emanating from the mouth area
- Line weight: 1.5pt stroke
- Style: SF Symbols-like, clean, geometric

---

## Feature 3: Animated Recording Indicator in Menu Bar

### Current behavior
- When recording, the main window shows "Recording..." with a red dot
- Menu bar icon doesn't change

### Desired behavior
- When recording starts, the menu bar icon animates to show "active recording"
- The sound wave arcs animate — they pulse/blink sequentially (wave 1 → wave 2 → wave 3 → repeat)
- When recording stops, icon returns to static state

### Implementation guidance

**Approach A — Frame Animation (simpler):**
- Create 3-4 frames of the icon with different wave states:
  - Frame 1: no waves (just lips)
  - Frame 2: first wave arc visible
  - Frame 3: first + second wave arcs visible
  - Frame 4: all three wave arcs visible
- Use `NSTimer` to cycle through frames every ~300ms
- Set `NSStatusBarButton.image` on each timer tick
- Stop timer when recording ends, reset to static icon

**Approach B — Red dot overlay (simplest):**
- Keep static icon but add a small red recording dot (like macOS camera indicator)
- Overlay a 6x6 red circle on the bottom-right of the icon when recording
- This is the simplest to implement and most "macOS native" feeling

**Approach C — Color tint (medium):**
- When recording, swap template image for a non-template colored version (e.g. the waves become red/orange)
- When idle, use template image (monochrome, adapts to menu bar)

**Recommendation:** Start with **Approach A** (frame animation) as it's the most visually distinctive and matches the user's request for "waves pulsing." Fall back to Approach B if animation proves janky.

### Files likely affected
- `Wisp/WispApp.swift` or wherever NSStatusItem is created
- `Assets.xcassets` — new image sets for menu bar icon frames
- `Wisp/AudioRecorder.swift` or `MicrophoneService.swift` — hook into recording start/stop to trigger animation

### macOS menu bar icon technical notes
- Use `NSStatusItem` with `NSStatusBarButton`
- For template images: set `isTemplate = true` on `NSImage`
- For animation: swap `button.image` on a timer
- Icon should be PDF vector or @2x PNG for Retina
- Test on both light and dark menu bar appearances

---

## Priority Order
1. **Menu bar icon** (static) — quick win, improves branding
2. **Recording indicator animation** — builds on #1
3. **Per-model shortcuts** — most complex, highest value

## Design Assets Available
- App icon (1024x1024) already exists at `docs/app-icon.png` — the speaking face with sound waves and computer
- Use a simplified version of this concept for the menu bar icon (just lips + waves, no computer, monochrome)