# Finder feasibility

Decision: GO — normal restart with explicit current-idle confirmation before each toggle

Checked 2026-09-15 on macOS 26.6.2 (25G83), Apple Swift 6.2.4.
The probe compiles and its read-only inspection and serialization check pass.
The user explicitly confirmed Finder idle, then the live exercise failed: writing true and issuing Finder update left the dotfile hidden. The original present value 0 was restored and Finder still displayed only visible.txt. The non-relaunch candidate does not pass the gate.

## Source evidence

- Installed `/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.sdef`, lines 133–137, documents `update` (`fndrfupd`) for updating an object's display from its disk representation. It does not promise preference reload.
- The installed dictionary's `preferences` class (line 408 onward) has no hidden-file toggle or rendered-visibility query. Application/window `visible` means the layer/window is visible, not that a dotfile is drawn. Item enumeration is not pixel verification. No file-operation-idle property was found.
- Apple's [archived porting guide](https://developer.apple.com/library/archive/documentation/Porting/Conceptual/PortingUnix/additionalfeatures/additionalfeatures.html) describes changing `AppleShowAllFiles` and restarting Finder. It is historical guidance, not proof of present behavior or a safe restart protocol.
- Current Apple documentation for [CFPreferencesSetValue](https://developer.apple.com/documentation/corefoundation/cfpreferencessetvalue(_:_:_:_:_:)) and [CFPreferencesSynchronize](https://developer.apple.com/documentation/corefoundation/cfpreferencessynchronize(_:_:_:)) supplies the native preference APIs. Synchronization does not prove Finder renders the new setting.
- [NSSavePanel.showsHiddenFiles](https://developer.apple.com/documentation/appkit/nssavepanel/showshiddenfiles) controls an application's save panel, not Finder; it does not solve this integration.

## Candidate sequence and safety

`Tools/FinderProbe.swift --inspect` synchronizes/reads only the exact current-user, any-host `com.apple.finder` preference domain. It sends no Apple Events and creates no files. Initial `AppleShowAllFiles` was present with value `0` (false); the recovery snapshot was absent.

`--exercise` first requires an explicit `IDLE` input after the operator establishes no active Finder file operation. It saves the exact original plist value, including absence, to `.build/finder-fixture/recovery.plist` using exclusive creation. Existing snapshots block reruns. It creates a UUID-named fixture with `visible.txt` and `.hidden.txt`, opens only that folder, then sets true and false using CFPreferences and asks Finder to `update` only that folder with application registration disabled. Apple Events have a 10-second timeout. Each stage requires a human pixel observation, `VISIBLE` or `HIDDEN`; any mismatch or input cancellation fails the gate.

Normal return, EOF, and thrown errors restore the exact saved preference and verify readback, then attempt the same non-disruptive fixture refresh. The snapshot and fixture remain for recovery and visual restoration inspection. No Trash, quit/relaunch, process termination, keyboard automation, Accessibility automation, private API, or Finder-window closure is implemented. Other preference keys are untouched. Do not change this preference externally during the exercise.

Repeatable observed integration can establish a refresh strategy without requiring a separate runtime pixel-query API. The current blocker is the observed failure of preference-plus-update. A graceful-relaunch alternative still needs verified visibility/restoration and a repeatable safe operating protocol; preference readback or event dispatch alone is insufficient.

## Recovery and outstanding checks

If interrupted by a signal, crash, or power loss, Swift `defer` is not guaranteed to run. Keep the snapshot; do not rerun the exercise or replace it. From the same worktree run:

```sh
rtk xcrun swift Tools/FinderProbe.swift --restore
rtk xcrun swift Tools/FinderProbe.swift --inspect
```

`--restore` uses the exact saved type/value or deletes the key when originally absent. It deliberately does not send Finder events or restart Finder. Readback proves preference restoration only. Visually inspect the retained fixture and re-establish agreement safely; if Finder has not refreshed, report that limitation rather than relaunching. Archive the recovery plist only after confirming restoration, then another exercise can create a fresh snapshot.

Automation denial, Apple Event timeout, or errors fail the exercise and enter restoration; real permission-denial testing remains outstanding. No denial or interrupted-run recovery has been simulated against the user's Finder. `--self-test` checks plist round trips for absent, true, false, string, and numeric preferences and AppleScript path escaping, without preference writes.

Recorded checks:

- `rtk xcrun swift Tools/FinderProbe.swift --self-test`: PASS.
- `rtk xcrun swift Tools/FinderProbe.swift --inspect`: PASS, read-only; actual initial preference above.
- `--exercise` with EOF before `IDLE`: PASS, exit 1; no fixture or snapshot created. No preference writes or Finder events.
- Invalid CLI: PASS, exit 1; no fixture or snapshot created.
- Confirmed-idle exercise: FAIL at true phase; visible restoration and preference restoration: PASS (see live evidence below).
- Internal trace and fresh independent review: GO for controlled probe testing after confirmed idle; BLOCKED for the integration gate until live observations pass. Both traced snapshot-before-write, recovery refusal, handled-error restoration, and absence of destructive/relaunch paths.
- Independent review limitation: readback compares values, not strict NSNumber boolean/integer type identity. Recovery writes the original saved property-list value; the diagnostic wording was narrowed accordingly.
- Optional trailing-argument rejection was deferred: the documented single-flag invocations are unambiguous and all live mutation remains behind the explicit idle checkpoint.
- Native implementation: blocked pending the approved feasibility gate.

## Live exercise evidence

- User confirmed “Finder is idle” before the root supplied IDLE.
- Fixture: `.build/finder-fixture/0001355B-67EE-4BE4-91F9-F2425635E1D8` contains `visible.txt` and `.hidden.txt`.
- Probe printed `Preference = true; update returned`. CUA screenshot and Finder accessibility tree showed only `visible.txt`, with status `1 item`. Root recorded HIDDEN; probe exited 1 with preference/visible-state mismatch.
- Deferred restoration reported saved preference restored. Subsequent `--inspect` returned present value 0; screenshot and tree again showed only `visible.txt`. Recovery snapshot remains preserved.
- False-phase was not run because the true-phase failed. No Finder relaunch, Trash operation, or shortcut occurred.

## Graceful relaunch live exercise (resumed session)

The user confirmed Finder idle and agreed to keep it idle through restoration. The prior recovery snapshot was preserved as `recovery-before-relaunch.plist` after restoring its saved preference. The reviewed `--exercise-relaunch` probe uses `NSRunningApplication.terminate()`, bounded termination observation, and `NSWorkspace.openApplication`; it never force terminates Finder. The operator supplied IDLE.

- Fixture: `.build/finder-fixture/F7F3852A-5C4D-4336-99B0-B53FD91B112B`.
- True phase: CUA screenshot and Finder accessibility tree showed `.hidden.txt` and `visible.txt`, status 2 items. Recorded VISIBLE.
- False phase: CUA screenshot and tree showed only `visible.txt`, status 1 item. Recorded HIDDEN.
- Probe exited 0 after deferred preference restoration and normal Finder restart.
- Final CUA screenshot/tree showed only `visible.txt`, status 1 item. `--inspect` returned original present value 0. Current recovery snapshot retained.
- Fresh independent safety review and root trace returned GO for this controlled experiment. Lifecycle wait and snapshot self-tests passed.

Result: graceful restart refresh is observed to work on this Mac; preference-plus-update alone failed. Production safety protocol is under review. Candidate protocol requires explicit current idle confirmation before every toggle and instructs the user to keep Finder idle through completion, with Cancel doing no mutation. No automatic idle detection or production pixel-query API is claimed. Native implementation remains gated pending this protocol review. Permission-denial and interrupted-process recovery live simulations remain outstanding; documented recovery retains the saved preference.

Production protocol review: GO from independent reviewer and root trace under approved behavior default 3. Require per-toggle idle confirmation, no mutation on Cancel, observed normal termination and successful launch before completion, preference readback, original-preference restoration on failure, unknown/error on unresolved state, and no additional quit while an earlier termination is unresolved. Human confirmation is a precondition, not automatic prevention of concurrent file operations. Task 2 must verify these paths. Historical BLOCKED statements above describe the earlier non-relaunch candidate.
