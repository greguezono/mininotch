# MinimalNotch

Three native controls below the camera notch: hidden files, idle sleep prevention, and Empty Trash. Hover below the housing to reveal; use the menu-bar Show / Hide entry for keyboard access. Escape dismisses. Requires macOS 14 or later and Xcode command-line tools.

```sh
rtk swift test
rtk bash scripts/build-app.sh
rtk open build/MinimalNotch.app
```

Hidden files restarts Finder normally, only after you confirm Finder is idle for each toggle. Keep it idle until completion. Failure restores the original preference and reports unknown state; reopen Finder manually when idle if needed. No force quit is used. External preference changes reconcile on reveal.

Keep awake prevents idle system sleep only; display sleep, manual sleep, and lid closure remain effective. Quitting releases this app's assertion. Quit waits for current actions to finish.

Empty Trash has a Cancel-first confirmation and delegates to Finder. Allow Finder Automation in System Settings → Privacy & Security → Automation if prompted. The local ad-hoc signature keeps a stable bundle identifier, but rebuilding can require permission again. No login item is installed.

Tests inject Finder and Trash operations: they never empty your Trash. OSLog Points of Interest records input, feedback, enqueue, and completion separately. Injected timing measures scheduling overhead only; it does not prove rendered pixels or real Finder latency. See `docs/verification.md` for actual-machine evidence and outstanding checks. Real Trash deletion requires an isolated disposable environment.
