# MiniNotch

Three native controls below the camera notch: hidden files, idle sleep prevention, and Empty Trash. Hover below the housing to reveal; use the menu-bar Show / Hide entry for keyboard access. Escape dismisses. Requires macOS 26 or later and Xcode command-line tools.

```sh
rtk swift test
rtk bash scripts/build-app.sh
rtk open build/MiniNotch.app
```

Toggle hidden files sends Command–Shift–Period directly to Finder without a confirmation or restart. Open a Finder window to use it. On a hidden-files click, missing access triggers the native macOS permission request. If access is denied, the panel explains the fix and offers Open Settings: enable MiniNotch in System Settings → Privacy & Security → Accessibility, quit and reopen MiniNotch, then click Toggle hidden files again. The running process does not pick up a new Accessibility grant; the relaunch is required. Returning from Settings performs no action and no new request. The On/Off indicator tracks this session's successful shortcut dispatches, starting Off; it does not observe Finder's initial state or external shortcuts. Event delivery has no acknowledgment from Finder. The shortcut uses the ANSI period key position; other keyboard layouts may interpret it differently.

Keep awake prevents idle system sleep only; display sleep, manual sleep, and lid closure remain effective. Quitting releases this app's assertion. Quit waits for current actions to finish.

If Accessibility is enabled but access is denied after changing signing identities, inspect the macOS `tccd` log for “Failed to match existing code requirement.” This occurred locally: the saved permission still required the old ad-hoc hash after removing and re-adding the app through Settings. To clear that specific stale record, quit MiniNotch and run:

```sh
rtk tccutil reset Accessibility local.greguezono.MinimalNotch
rtk open /Applications/MiniNotch.app
```

Click hidden files to request permission from the running app, enable MiniNotch in Accessibility, then retry. The reset clears only this app's Accessibility approval; it does not grant permission. Do not run it for ordinary updates signed with the same certificate. The local reset and fresh native request were verified. Subsequent macOS logs show event-posting authorization allowed with the current certificate; the user confirmed the hidden-files action works. Permission retention across a changed build still awaits live confirmation.

Empty Trash does nothing when Trash is empty; otherwise it delegates to Finder immediately on click. Cancellation shows no message. If Finder Automation is denied, the panel offers Open Settings: enable Finder under MiniNotch in System Settings → Privacy & Security → Automation, then click Empty Trash again only when you want to empty it. A successful retry clears that action's message; other actions leave it in place. No login item is installed.

Local builds reuse the `MiniNotch Local Signing` certificate and private key in Greg's login Keychain, pinned by fingerprint in `scripts/build-app.sh`. Keep that identity and the bundle identifier unchanged across updates, and install at `/Applications/MiniNotch.app`. The build fails if the identity is missing; it never falls back to ad-hoc signing. Export the identity securely through Keychain Access before moving to another Mac; do not commit its private key. This self-signed identity is for local use, not public distribution. Moving from the old ad-hoc build can require one final Accessibility/Automation approval; subsequent builds retain the same signing identity. Actual permission retention must be checked after an approved build is updated.

Tests inject Finder and Trash operations: they never send keyboard events or empty your Trash. OSLog Points of Interest records input, feedback, enqueue, and completion separately. Injected timing measures scheduling overhead only; it does not prove rendered pixels or real Finder latency. See `docs/verification.md` for actual-machine evidence and outstanding checks. Real Trash deletion requires an isolated disposable environment.
