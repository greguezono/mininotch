# Native app verification

Status: PARTIAL VERIFICATION. Native app built, signed, launched; UI verification awaits a visible panel. No overall latency or full acceptance claim.

## Environment

- macOS 26.6.2 (25G83); Apple Swift 6.2.4.
- MacBook Pro Mac16,7, M4 Pro, 14 CPU cores, 24 GB memory.
- Built-in Liquid Retina XDR display, 3456 × 2234; no external display attached.
- Instruments available: Activity Monitor, Logging, SwiftUI, Animation Hitches, Time Profiler, System Trace, Power Profiler.
- Existing power assertions from powerd, sharingd, management software, and a separate temporary caffeinate process are unrelated to this app. Verify ownership when checking sleep behavior.

## Finder feasibility

PASS for the explicit current-idle-confirmation protocol. See `finder-feasibility.md` for true/false/restoration observations, limits, and recovery. This verifies the probe; the shipped app integration remains to be checked.

## Acceptance

| Criterion | Status | Evidence |
|---|---|---|
| Native build, launch, signing | PASS | Release build, plist lint, strict codesign; launched process 69303 |
| Layout, notch geometry, pointer behavior, keyboard, accessibility, Spaces | OUTSTANDING | Actual app checks pending |
| Idle-system sleep assertion and release | PARTIAL | 102 actual IOKit toggles passed and ended off; app UI/pmset/quit observation pending |
| App hidden-file integration | OUTSTANDING | Probe passed; app pending |
| Trash confirmation/cancel/denial/duplicates | PARTIAL | Injected cancellation, duplicate suppression and failure checks pass; native dialog check pending |
| Actual Trash deletion in isolated account | OUTSTANDING | No isolated disposable account available; real user Trash will not be emptied |
| Focused state/action regression tests | PASS | 7 tests with opt-in real sleep enabled; normal runs skip that one system-state test |
| Warm input/feedback/dispatch timing | OUTSTANDING | At least 100 samples per action required; injected results must be distinguished |
| Actual render timing | OUTSTANDING | Instrumented native UI recording pending |
| Idle CPU, memory, wakeups | PASS | 64.13-second Instruments Activity Monitor recording; statistics below |

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
