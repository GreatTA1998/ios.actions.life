# actions.life iOS

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
