# Camera, Files and authentication runtime boundaries

Executed 14 October 2026 using Xcode 27, iPhone 17 Pro simulator / iOS 26.5, destination `6F9172CC-DF86-4F05-9EB3-42E8E287668F`. Every test explicitly launches `dev.peringer.limen.audit`, uses its synthetic Debug fixture and resets only that app's camera authorization when necessary. No production app or records are reset.

| Boundary | Observed result | Evidence |
|---|---|---|
| System Files picker cancellation | Passed, 56.478 s. A new address and pending document title remain, attachment count stays zero, cancellation produces no import error, and the address/count survive backgrounding and relaunch | [Initial log](evidence/runtime-boundaries.log); [picker](evidence/runtime-files-picker-before-cancel.png), [cancelled](evidence/runtime-files-picker-cancelled.png) |
| Device authentication cancellation | Passed, 86.797 s. The simulator offers authentication; cancelling its actual prompt leaves the preference off, shows a dismissible error, remains off after relaunch and leaves the saved library reachable | [Retry log](evidence/runtime-retry.log); [cancelled authentication](evidence/runtime-library-auth-cancelled.png) |
| Camera permission denial | Passed, 19.871 s. This simulator exposes a camera source. Denying its actual system prompt produces the Settings explanation and Cancel action; gallery access remains visible and an edited room survives backgrounding and relaunch | [Camera log](evidence/runtime-camera.log); [denial](evidence/runtime-camera-denied-simulator.png) |

The first run is retained with its failures. A broad room-label query selected the explanatory info button instead of the fixture room, and the original tests incorrectly assumed the simulator lacked camera and authentication capabilities. The room query now matches its exact accessible label. Tests inspect the actual app/system response: unavailable-camera and unavailable-authentication paths are distinct from denial/cancellation. The observed passes above are **denial/cancellation**, not proof of unavailable hardware or credentials. The camera-only retry exited successfully; earlier bundles include unrelated failed driver assumptions alongside their passing cases.

Result bundles are `/tmp/limen-runtime-boundaries.xcresult`, `/tmp/limen-runtime-retry.xcresult` and `/tmp/limen-runtime-camera.xcresult`. Complete invocation headers are preserved in their logs. The successful camera retry used:

```sh
xcodebuild -workspace Limen.xcworkspace -scheme AllTests \
  -destination 'platform=iOS Simulator,id=6F9172CC-DF86-4F05-9EB3-42E8E287668F' \
  -derivedDataPath ./DD-final -collect-test-diagnostics never \
  -resultBundlePath /tmp/limen-runtime-camera.xcresult \
  -only-testing:LimenUITests/RuntimeBoundaryTests/testSimulatorCameraRefusalPreservesDraft test
```

## Physical iPhone results

The physical run used iPhone 17 / iOS 26.6.2 (23G90), UDID `00008150-001074183A7B401C`, with the separate audit bundle. After the owner enabled XCTest automation, the blank-form tenant journey passed in **101.188 seconds**, including two drawn test signatures, finalization and an opened PDF. Its mixed bundle contains later failed interruption-driver checks, so only this named case is reported as passing: `/tmp/limen-physical-ui-retry.xcresult`, [original log](evidence/physical-journey-and-initial-runtime.log).

Both physical interruption checks subsequently passed in `/tmp/limen-physical-interruption.xcresult`, [final runtime log](evidence/physical-runtime.log):

| Check | Observed result |
|---|---|
| Actual camera consent denial | **17.154 seconds**, passed. Real system consent was denied, the app offered Settings and gallery alternatives, and the edited room name survived a system-app interruption, termination and relaunch |
| Actual Files picker cancellation | **61.966 seconds**, passed. Cancellation retained the entered document title and zero attachments; the edited address and attachment count survived interruption, termination and relaunch |

The initial physical driver assumed `XCUIDevice.press(.home)` would background the app. It was ignored on this runtime: the audit app remained foreground (`state = 4`), and a Home-screen icon never became hittable. The corrected test activates the system Settings app without changing any setting, waits for its navigation UI, and records audit background state **3**, Settings foreground state **4** before termination. Both edited values and nested navigation are then verified after relaunch. No application change was needed to repair these test-driver failures.

Original physical screenshots and attachment provenance are in [evidence/physical](evidence/physical/). The first runner's passcode timeout remains documented in [VERIFICATION.md](VERIFICATION.md). These denial/cancellation passes do not certify successful camera capture, provider read failure, successful biometric/passcode authentication or human assistive-technology operation. Library authentication cancellation was exercised on the simulator as recorded above.

## Asynchronous intake ownership

The full app suite subsequently passed **25 Swift Testing tests in 5 suites plus 4 bundle XCTest tests**. [final-app-intake.log](evidence/final-app-intake.log) records the exact command and result; bundle `/tmp/limen-final-app-intake.xcresult`.

The added `PhotoIntakeOwnershipTests` uses real PNG bytes and deterministic MainActor ordering, with no sleeps. Before awaiting the intake task it switches to another record or amendment containing the same room ID, removes the owner, or freezes the original record. Every rejected late result removes its newly copied evidence and leaves the current record unchanged. A separate capture test verifies that cleanup removes only the operation's own private capture, while another private capture remains byte-identical. Successful gallery intake preserves source bytes and SHA-256, records import time separately from unknown capture time, and survives a store save/load.

The sole production change for these tests makes the existing `intakePhoto` operation return its `Task<Void, Never>?` with `@discardableResult`, like document intake. Ownership checks themselves were not replaced by test-only behavior.
