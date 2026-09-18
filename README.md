# ios.actions.life

Native SwiftUI app for [actions.life](https://github.com/GreatTA1998/actions.life). It lives in this repository, not in the web app’s `ios/` folder.

Bundle ID: `life.actions.ios`  
Firebase: `project-y-2a061` (named Firestore database `schema-compliant`)

## Run

```bash
git clone git@github.com:GreatTA1998/ios.actions.life.git
cd ios.actions.life
open ActionsLife.xcodeproj
```

In Xcode: scheme **ActionsLife**, destination your iPhone or Simulator, then ⌘R.

- **Continue as guest** works offline.
- **Continue with Google** uses the iOS OAuth client already registered on Firebase (`life.actions.ios`) plus the same web client ID as the website.
- Sign in with Apple is also on the sign-in screen.

## Layout

Home is a day calendar above an inbox. Nested subtasks can be created, completed, indented, opened, archived, and scheduled onto a day as all-day or timed blocks.

## Verify list ↔ calendar (web parity)

1. **Tap-create** — Tap the gap above/between inbox rows (24pt root / 16pt sub). An inline composer should open; submit to insert at that index. Expand a parent, then tap the trailing overhang under its children to add a subtask.
2. **List → calendar drag** — Hold a list task ~150ms, then drag onto the day canvas. Ghost follows the grab point; drop schedules at the ghost-top time. List nest zones must not steal the drop while your finger is in the calendar.
3. **Edge scroll** — While dragging, hold near the top/bottom of the list or the edges of the calendar; the pane should scroll continuously (44pt band / 16pt step).
4. **Split resize** — Drag the grip: list can go fullscreen (calendar collapses to 0); list floor stays 48pt. Release persists the fraction without flicker (visual-only while dragging).
