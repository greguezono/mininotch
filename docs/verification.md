# Native app verification

Status: PARTIAL VERIFICATION. Native app built, signed, launched; UI verification awaits a visible panel. No overall latency or full acceptance claim.

## Environment

- macOS 26.6.2 (25G83); Apple Swift 6.2.4.
- MacBook Pro Mac16,7, M4 Pro, 14 CPU cores, 24 GB memory.
- Built-in Liquid Retina XDR display, 3456 × 2234; no external display attached.
- Instruments available: Activity Monitor, Logging, SwiftUI, Animation Hitches, Time Profiler, System Trace, Power Profiler.
- Existing power assertions from powerd, sharingd, management software, and a separate temporary caffeinate process are unrelated to this app. Verify ownership when checking sleep behavior.

## Finder feasibility

Historical PASS for the former current-idle-confirmation/restart probe. The user superseded that design on 2026-09-16 with direct Command-Shift-period behavior. See the shortcut amendment below; earlier probe results do not verify the replacement.

## Acceptance

| Criterion | Status | Evidence |
|---|---|---|
| Native build, launch, signing | PASS | Release build, plist lint, strict codesign; launched process 69303 |
| Layout, notch geometry, pointer behavior, keyboard, accessibility, Spaces | OUTSTANDING | Actual app checks pending |
| Idle-system sleep assertion and release | PARTIAL | 102 actual IOKit toggles passed and ended off; app UI/pmset/quit observation pending |
| App hidden-file integration | OUTSTANDING | Direct shortcut replacement pending actual-app verification |
| Trash confirmation/cancel/denial/duplicates | PARTIAL | Injected cancellation, duplicate suppression and failure checks pass; native dialog check pending |
| Actual Trash deletion in isolated account | OUTSTANDING | No isolated disposable account available; real user Trash will not be emptied |
| Focused state/action regression tests | PASS | 7 tests with opt-in real sleep enabled; normal runs skip that one system-state test |
| Warm input/feedback/dispatch timing | OUTSTANDING | At least 100 samples per action required; injected results must be distinguished |
| Actual render timing | OUTSTANDING | Instrumented native UI recording pending |
| Idle CPU, memory, wakeups | OUTSTANDING | Historical 64.13-second recording predates pointer-monitor revision; statistics below |

## Limits

No extra account, global security change, or destructive real-Trash test is authorized. Mocked timing cannot establish real Finder dispatch latency. Do not infer pixels-on-screen latency from feedback-state timestamps.

## Build and source review

Task 2 commit `b2277ba`, following Finder probe commit `38477d0`. Root call-path trace and fresh independent review returned GO for controlled app verification. Actual release build in a temporary path with spaces passed; missing-input and symlink-output guards rejected unsafe inputs with outside directory unchanged. No third-party dependency or background helper.

The current CUA app surface exposes the transparent two-point activation window only. A coordinate click returned AXError.notImplemented. User asked to reveal the panel manually; geometry, hover transitions, keyboard/VoiceOver, Spaces/full screen, display removal, native confirmation dialogs and actual frame rendering remain unverified. No permission/security settings were changed.

## Timing observations

Monotonic `ProcessInfo.systemUptime`; nearest-rank quantiles. Debug test executable on the actual Mac during development load. Discarded one initial sample per injected Finder action and one on/off warmup pair for actual sleep, leaving 100 samples per action. These samples begin at the action method, not physical input or rendered feedback. Finder samples inject successful handlers and do not dispatch real Finder operations. Sleep samples use real IOKit create/release calls. They cannot satisfy the complete native interaction latency criterion.

| Action / measurement (ms) | p50 | p95 | Maximum |
|---|---:|---:|---:|
| Injected hidden / feedback state | 0.00233 | 0.00471 | 0.00671 |
| Injected hidden / enqueue mark | 0.00350 | 0.00662 | 0.00937 |
| Injected hidden / completion | 0.02667 | 0.04038 | 0.05604 |
| Injected Trash / feedback state | 0.00242 | 0.00446 | 0.02142 |
| Injected Trash / enqueue mark | 0.00354 | 0.00554 | 0.02246 |
| Injected Trash / completion | 0.02600 | 0.03725 | 0.07521 |
| Actual sleep / feedback state | 0.00204 | 0.00354 | 0.00633 |
| Actual sleep / enqueue mark | 0.00308 | 0.00550 | 0.00771 |
| Actual sleep / IOKit completion | 0.03308 | 0.05375 | 0.10058 |

Raw local samples and summaries: `build/injected-finder-timing.json`, `build/injected-finder-summary.json`, `build/actual-sleep-timing.json`, `build/actual-sleep-summary.json`. Repeat via explicit test-only environment variables `MINIMAL_NOTCH_TIMING_OUTPUT`, `MINIMAL_NOTCH_TEST_SLEEP=1`, and `MINIMAL_NOTCH_SLEEP_TIMING_OUTPUT`. Normal tests do not change system sleep state.

## Idle observation

Instruments Activity Monitor attached to the launched release app for 64.129909 seconds. Exported 11 process samples spanning 56.962887 seconds (the final sample continues through the recording end). Over sampled endpoints CPU time increased by 0.000073167 seconds, approximately 0.000128% of one core; idle wakeup count increased by 1, approximately 0.0176/second. Physical footprint ranged 15.735–15.782 MiB. This is one idle observation with panel hidden, not a guarantee under interaction or other loads.

Local evidence: `build/idle.trace`, `build/idle-process.xml`, `build/idle-summary.json`. Raw Instruments traces embed process-environment metadata and remain ignored local artifacts; only the filtered statistics belong in review/publication.

## Full-notch and compact-panel revision

User supplied screenshot confirmed previous native panel rendering, then requested whole-notch activation and reduced size. Updated normal panel to 150×70 points with 36×34 controls, 18-point symbols and 10-point label; errors expand to 320×280. Removed the two-point overlay and use event-driven local/global mouse observation with aggregate full-notch/panel hit testing. Geometry regression covers notch top/edges, bridge and panel, outside/menu regions and absent notch. Eight tests discovered; one real-sleep opt-in skip, zero failures. Release rebuilt/signed and reloaded via normal quit. New live hover, compact appearance and render timing remain unverified; CUA hidden-window inspection times out. Prior idle measurements predate new global mouse monitor and must be repeated for final acceptance.

## Live compact-panel observation

After the user reported the panel open, CUA exposed Show hidden files (Off), Allow sleep (On), Empty Trash, and the contextual Empty Trash label. `pmset -g assertions` independently showed process 77710 (MinimalNotch) owning `PreventUserIdleSystemSleep` named MinimalNotch Keep Awake, with no app-owned display-sleep assertion. This confirms the running UI's enabled sleep state matches the OS. The user's enabled assertion was left unchanged. The panel collapsed before screenshot capture (noWindowsAvailable); user asked to open through the menu-bar Show / Hide Quick Actions entry for persistent keyboard inspection. Full geometry, mouse-transition behavior, cancellation dialogs, and rendered latency remain pending.

## Direct hidden-files shortcut amendment — 2026-09-16

User requested no restart confirmation and behavior matching Finder’s Command-Shift-period shortcut. Root reproduced the shortcut through CUA in the existing disposable fixture: visible.txt only → .hidden.txt plus visible.txt → visible.txt only. The saved AppleShowAllFiles value remained 0 even while the hidden file was visible. This establishes native shortcut behavior and restoration, but does not verify the app’s process-directed event delivery.

The replacement uses a stateless “Toggle hidden files” control, public process-directed keyboard events, and a permission preflight. No preference write, Finder restart, hidden-action confirmation, global key fallback, rollback, or optimistic On/Off state. Missing event-posting access is an inline error; OS permission is not granted automatically. Trash confirmation remains required. Native delivery with Finder inactive and current keyboard layout remains to be verified after build.

Starting app sleep state was ON: pmset identified PID 77710 owning only the MinimalNotch idle-system-sleep assertion. No security settings or real Trash contents changed during the native shortcut experiment.

Replacement build checks: 7 tests discovered, one intentional actual-sleep skip, zero failures. Tests cover direct execution/duplicate suppression, Command-Shift-period event construction without posting, and injected failure/Trash cancellation. Release build, strict codesign and Info.plist lint pass. Root internal trace GO: events target Finder PID only after access preflight; no hidden confirmation or production restart/write/rollback remains; Trash requires confirmation. Actual app delivery remains outstanding: previous process is still running, and CUA cannot access its hidden panel for reload.

Fresh independent source review: GO, no findings. This approves the implementation for live validation; it does not establish visible Finder event handling.

## App icon — 2026-09-16

Added generated transparent charcoal notch/three-button artwork, source PNG and prompt in Resources, plus a native ICNS with 10 scale representations. Bundle metadata and packaging include the icon before signing. Installed updated bundle at /Applications/MinimalNotch.app; strict signature verification and icon-byte comparison passed. Root packaging trace and fresh independent review both GO. Actual temporary build in a path with spaces passed; missing-icon, symlinked Resources directory and symlinked icon destination were rejected, with outside directory unchanged. No action source changed for the icon request.


### Silent empty Trash and cancellation

Finder script now checks for items before emptying Trash. Finder cancellation (-128) completes silently; permission and timeout failures still surface. Regression test uses harmless injected AppleScripts to check successful no-op, cancellation, permission denial, and timeout through SystemActions. Native Finder script compilation checked without executing deletion.

### Hidden-files toggle indicator — 2026-09-16

Hidden-files now shares sleep's active tint, yellow dot, and accessible On/Off value. State flips only after successful shortcut dispatch; duplicate requests and failures do not flip it. This is session-local shortcut tracking, initially off; external Finder shortcuts and pre-existing visibility are not observed. Regression checks cover off/on/off, duplicates, failures, and unrelated Trash completion. `swift test`: 8 tests, 1 opt-in sleep skip, zero failures. Release build and installed bundle strict codesign verification passed; updated /Applications/MiniNotch.app and relaunched. Live visual verification remains outstanding.

### Stable local signing — 2026-09-16

Root cause: installed ad-hoc signature used a binary-specific cdhash as its designated requirement. Created a dedicated self-signed `MiniNotch Local Signing` identity in the login Keychain and pinned its certificate fingerprint in the build script. No TCC database changes, trust-store changes, or ad-hoc fallback. Temporary exported key material was removed after import. The certificate expires in 2036; replacement will change identity.

Internal trace GO: the unchanged bundle identifier plus certificate leaf now identifies successive builds. `python3 scripts/check-signing.py` passed changed-build identity matching, rejection of ad-hoc replacement, missing-identity build failure, missing-input and symlink-output guards using a real temporary build path containing spaces. `swift test`: 8 tests, 1 opt-in skip, zero failures. Fresh independent subagent review GO; independently ran the signing regression and Bash syntax check and inspected the requirement. Uses native macOS codesign/security and portable Bash constructs, with no GNU-only shell options added.

Installed at /Applications/MiniNotch.app and relaunched; installed strict signature verification against the pinned requirement passed. Live Accessibility retention remains pending: user must approve this new identity once before an actual subsequent update can establish TCC retention. Stable signature checks alone do not establish the live permission outcome.

### Accessibility recovery instructions — 2026-09-16

User reports Accessibility visibly enabled but denied after restart. Confirmed running /Applications/MiniNotch.app with the pinned certificate. An old permission entry is a possible cause, not yet confirmed. Updated inline error and README with explicit quit, remove row (−), re-add installed app (+), enable and reopen steps. Release build and installed strict certificate requirement verification passed. Left app quit for the user's permission-entry replacement. Recovery and permission retention remain unverified pending user retry.

### Confirmed stale Accessibility requirement — 2026-09-16

Removing and re-adding through Settings did not resolve the user's denial. A temporary same-process AX and event-posting probe produced tccd evidence at 18:07:59: “Failed to match existing code requirement” for MiniNotch Accessibility, comparing old cdhash `e0abb49d96109e1192a92d0042d6647c3d0a913c` with the installed identifier/certificate requirement. Both checks denied. This confirms the stale requirement, rather than assuming the switch was off.

Quit MiniNotch and ran `tccutil reset Accessibility local.greguezono.MinimalNotch` successfully. At 18:09:00 the newly launched app's native CGRequestPostEventAccess request was recorded by tccd without the prior mismatch. User approval is still required; the reset does not grant access. Production now requests event-posting access only on a hidden-files action when preflight denies, and still blocks posting if the request denies. Regression covers all four permission outcomes and request counts; 9 tests, 1 opt-in skip, no failures. Independent source review GO. Removed temporary startup diagnostics, rebuilt, installed, and verified the pinned requirement. No private entitlements, trust-store changes, or direct TCC database writes. Computer-use tool unavailable (CUA_REPL_ENABLED_SURFACES missing); live approval, Finder delivery, and retention across a later update remain pending. Do not present earlier remove/re-add instructions as verified recovery.

### Recovery follow-up — 2026-09-16 18:18

Read-only inspection found installed MiniNotch running as PID 29676 with the pinned certificate requirement; strict installed signature verification passed. At 18:14:37, tccd recorded PostEvent preflight requests 29676.2 (app) and 413.1307 (WindowServer checking the app). Both returned authValue=2, authReason=4, error=(null); certificate requirement matching returned status 0. This supports recovery of event-posting authorization for the current build. Visible Finder delivery and permission retention after a changed build remain unconfirmed pending the user's live result. No further consent reset or installation performed.

Fresh `swift test`: 9 tests, 1 intentional real-sleep skip, 0 failures. Computer-use MCP still fails with `CUA_REPL_ENABLED_SURFACES is required`; requested reconnection, with no alternate UI integration used.

### User-confirmed working checkpoint — 2026-09-16

Greg confirmed that the hidden-files button changes Finder visibility and that the app is in a working state. Together with the matching certificate requirement and allowed PostEvent checks above, this confirms local Accessibility recovery and live Finder delivery. Retention after an actual installed update remains a separate pending check. User requested committing this working state and integrating it into main.

### Permission recovery UX — 2026-09-18

Accessibility and Finder Automation denials now carry a structured recovery target from `NativeFinder` through `SystemActions.Failure` to the panel, which adds an Open Settings button beside Dismiss. Ordinary failures and Trash timeout carry no target; cancellation stays silent. A displayed failure clears only when its own action later succeeds; unrelated successes leave it in place. `NativeFinder.toggle` gained injectable Finder PID, access check, and post closures so tests observe that a denied check never posts events. Inline denial copy no longer suggests a consent reset; the README keeps the diagnosed stale-identity steps. Apple Events usage description now reads "MiniNotch asks Finder to check and empty Trash when you click Empty Trash." in source and in the built bundle; `plutil -lint` passed.

`swift test`: 13 tests, 1 opt-in sleep skip, 0 failures. Signed release build passed strict verification with the unchanged designated requirement (identifier plus pinned certificate leaf). On macOS 26.6.2, `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` and `?Privacy_Automation` each opened System Settings on the matching list, confirmed by screenshot. System Settings was quit afterward; no consent was changed and the installed /Applications/MiniNotch.app was not replaced.

Pending: Greg's native first-use/denial observation in a disposable environment, live layout and VoiceOver check of the two-button row, and the update-retention experiment described in the design spec.
