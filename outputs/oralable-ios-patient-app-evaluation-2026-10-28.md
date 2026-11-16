# Oralable iOS Patient App Evaluation

**Review date:** 28 October 2026  
**Repository reviewed:** `oralable_swift`  
**Primary scope:** the patient-facing `OralableApp` scheme. The professional app was not independently exercised.

## Release decision

**No-go for public TestFlight or App Store submission.** The patient app is buildable and its clean first-run screen launches successfully on a current simulator, but there are unresolved issues in health-data consent/storage, automated-test compilation, and release operations. These need remediation and verification before a responsible release.

## What was verified

| Area | Result | Notes |
|---|---:|---|
| Normal Debug simulator build | Pass | `OralableApp` built successfully for an iPhone 17 Pro simulator using the project’s normal local signing path. |
| Release simulator build | Pass | Optimized Release build completed successfully, including Xcode’s simulator `-validate-for-store` bundle validation. This is **not** a signed device archive or an App Store upload validation. |
| Fresh install / initial launch | Pass, limited | A clean simulator install launched to onboarding and remained foregrounded during the check. The initial page has good contrast, large primary copy, Sign in with Apple, and a clear wellness—not-diagnosis statement. |
| Checked-in XCTest scheme | Fail | The test target fails while compiling, before any tests execute, due to stale references to `RecordingStateCoordinator` in the tests. The audit found 18 such remaining test references. |
| Privacy / data-flow static review | Fail | The code automatically uploads detailed health and raw sensor data to a CloudKit **public database** after an authenticated recording disconnect. The visible local-only preference does not control this path. |
| Accessibility review | Partial | The code has 41 explicit accessibility labels and 10 hints, which is a good start. VoiceOver, Dynamic Type, Switch Control, and multi-size device testing were not completed. |
| Hardware and services | Not tested | No physical BLE device, real HealthKit authorization/data, production CloudKit, Sign in with Apple, StoreKit purchase, or real-device background execution was exercised. |

## Live first-run evidence

![Oralable first-run onboarding on the iPhone 17 Pro simulator](/Users/johnacogan67/work/oralable_swift/outputs/oralable-first-run-onboarding-iPhone17Pro.png)

The first screen is visually clean and readable, with an appropriate wellness disclaimer. However, the `TabView` page indicator is visually absent against the white background in the captured screen. The code has four onboarding pages, but there is no visible **Next** action or discoverable affordance that tells a user to swipe. That makes important Health, report, and sharing information easy to miss.

## Release-blocking findings

### B1 — Sensitive health data is automatically uploaded to a public CloudKit database without an effective user consent gate

**Severity: Blocker**

`SharedDataManager` initializes `container.publicCloudDatabase` in `OralableApp/Managers/SharedDataManager.swift` (lines 137–142). Its sync payload includes the user identifier, date, duration, derived bruxism metrics, heart-rate samples, oxygen-saturation samples, and a compressed complete sensor time series (lines 287–472).

The app wires `automaticRecordingSession.onSyncRequested` to `sharedDataManager.uploadCurrentDataForSharing()` in `OralableApp/Oralable.swift` (lines 40–49). `uploadCurrentDataForSharing()` directly invokes the CloudKit sync method; it has rate limiting but no check for a consent, local-only, professional-sharing, or CloudKit-sharing flag (`SharedDataManager.swift`, lines 474–499).

This conflicts with the apparent user-facing intent:

- `FeatureFlags.showCloudKitShare` defaults to `false` (`FeatureFlags.swift`, lines 75–84), but only hides a feature; it does not gate the background uploader.
- `SettingsViewModel.localStorageOnly` defaults to `true`, but a whole-app search found this key only inside `SettingsViewModel`; it is not read by the upload or retention paths. The view model also does not bind that setting in `setupBindings()`.
- The source itself describes the CloudKit database as being used for patient/professional sharing, while the onboarding copy says the build does not share with a dentist app.

Using a public CloudKit database does not automatically mean data is anonymously world-readable—CloudKit permissions and schema roles matter—but storing identifiable health data there demands a documented access model, explicit informed consent, and a security/legal review. The current automatic behavior is not an acceptable default for a consumer wellness app.

**Required remediation**

1. Remove the lifecycle/disconnect upload until cloud backup or professional sharing has an explicit, persisted, default-off consent state.
2. Make `localStorageOnly` a real, tested enforcement point—or replace it with clearly named controls such as **Cloud backup** and **Share with professional**. Gate every upload entry point, including disconnect and background callbacks.
3. Use a private, access-controlled CloudKit design for patient records unless there is a documented, reviewed reason to use the public database. Keep public data limited to non-sensitive invitation metadata if possible.
4. Add per-recipient authorization, revocation, delete/export behavior, audit logging, and tests proving that no upload occurs before consent.
5. Obtain privacy and security review before submitting App Store privacy disclosures.

### B2 — The XCTest scheme does not compile, so no automated tests ran

**Severity: Blocker**

The consumer app builds, but `xcodebuild test` stops during compilation of `OralableAppTests`. The tests still refer to the removed `RecordingStateCoordinator`; the audit found 18 stale references across test sources. Consequently, there is no passing regression suite for the evaluated revision.

This is more than a CI inconvenience. It means changes to BLE reconnect, automatic recording, HealthKit, export, and session persistence are not protected by a runnable automated baseline.

**Required remediation**

1. Delete, migrate, or replace the obsolete coordinator-based tests and restore a green `xcodebuild test` run.
2. Make CI fail on test-compilation errors and publish a result bundle/coverage summary.
3. Add focused tests for the consent gate, CloudKit uploads, data retention/cleanup, failed flush recovery, and first-run onboarding.

## High-priority findings

### H1 — Raw 50 Hz health/sensor CSV files have no verified retention policy and can lose data on write failure

**Severity: High**

The app writes high-resolution sensor rows—including timestamp, raw PPG channels, accelerometer axes, temperature, battery level, heart rate, and SpO2—to CSV (`Utilities/ResearchRawDataExport.swift`, lines 13–49). `SensorDataProcessor` periodically spills its in-memory history to `Application Support/Oralable/MemoryFlush` (`Managers/BLE/SensorDataProcessor.swift`, lines 61–85); `DeviceManager` writes a parallel unified-buffer dump (`Managers/DeviceManager.swift`, lines 559–574).

Two concrete issues follow:

- The `dataRetentionDays` setting defaults to 30 but is only present in `SettingsViewModel`; no enforcement or scheduled deletion path was found. The memory-flush directory has no cleanup path in the patient-app source search.
- `SensorDataProcessor` clears history after the write attempt even when it catches a write error. `DeviceManager` removes its entire unified buffer *before* attempting the write. A disk or file-system failure can therefore drop captured health data without retry, durable queueing, or user warning.

**Required remediation**

- Give raw files an explicit lifecycle: ownership, retention duration, successful-consumption marker, deletion job, account-deletion cleanup, and user-visible clear-data behavior.
- Only discard in-memory batches after durable storage succeeds. On failure, retain/retry, surface the failure, and test low-disk/full-volume behavior.
- Apply intentional iOS file-protection classes and document whether raw research exports are allowed in consumer builds.
- Add integration tests for background flush, app termination, storage failure, recovery, and deletion.

### H2 — The declared data controls and privacy disclosures need reconciliation with the actual behavior

**Severity: High**

`PrivacyInfo.xcprivacy` declares linked health data and product-interaction data for app functionality and analytics. At the same time, the repository contains no analytics SDK in the resolved packages, and the `shareAnalytics` preference is only a view-model value with no detected analytics transmission implementation. Conversely, full health data is transmitted to CloudKit by the automatic sync path.

Additionally, `Info.plist` enables `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`. Those flags may be intentional for clinical/research exports, but they expand the file-exposure surface and require a precise inventory of what health files can appear in the app’s Documents container.

**Required remediation**

- Reconcile the privacy manifest, App Store privacy answers, privacy policy, onboarding language, and actual network/file behavior. Do not rely on a UI toggle that is not enforced.
- Decide whether analytics exists. If it does not, remove or correct unsupported declarations; if it does, implement consent, data minimization, and clear documentation.
- Disable Finder/Files sharing unless it is an intentional, documented user feature. If retained, ensure sensitive outputs require an explicit export action and that account/data deletion cleans them up.

### H3 — The repository’s own launch checklist still lists core external-release work as unfinished

**Severity: High**

`LAUNCH_READINESS_CHECKLIST.md` lists CloudKit production schema deployment, App Store Connect/IAP configuration, and App Store metadata/submission as pending critical items. It also lists legal pages, end-to-end patient-to-dentist testing, performance testing, accessibility testing, and beta testing as incomplete.

The checklist is useful context rather than independent proof, but it agrees with this audit: a passing simulator build alone is not launch readiness. The document’s January 2026 target date also appears stale relative to this review and should be replaced with owner, due-date, and evidence-based release gates.

## Product and accessibility findings

### U1 — Onboarding lacks a visible progression cue

**Severity: Medium**

The simulator screenshot shows the first of four onboarding pages. The intended page dots are not visually detectable on the white screen, and there is no **Continue** or **Learn more** control. Add a high-contrast page control plus an explicit action such as **Next** / **Get started**, and test it with larger text sizes.

### U2 — Dynamic Type and assistive-technology validation remains incomplete

**Severity: Medium**

The code provides many labels/hints and uses `Label` for the main tab items, both positive signs. It also uses fixed heights and explicit point sizes in several primary views, including onboarding (`OnboardingView.swift` sets a 400-point page frame and an 80-point SF Symbol). This can cause clipping, spacing failures, or inaccessible visual hierarchy under large Dynamic Type.

**Required remediation**

- Run the primary flows using VoiceOver, Larger Accessibility Sizes, Bold Text, Reduce Motion, and Switch Control.
- Test first-run, pairing, live recording, no-device/error, sharing/export, and account deletion on the smallest supported iPhone and an iPad.
- Replace fixed content heights where possible with adaptive layout and scroll-safe containers.

## Positives worth preserving

- The normal Debug and optimized Release simulator builds succeed.
- A fresh launch displayed a high-contrast, uncluttered first-run experience.
- The wellness—not-diagnosis statement is present in initial onboarding.
- Sign in with Apple, HealthKit, CloudKit, Bluetooth background mode, a privacy manifest, and supporting usage descriptions are configured in the project.
- The codebase already has a meaningful accessibility foundation: explicit labels/hints in device and dashboard areas, semantic tab labels, and standard Sign in with Apple UI.
- Raw-sensor persistence is clearly trying to avoid loss from a bounded live buffer; the solution needs durability and retention hardening rather than removal.

## Recommended release sequence

1. **Immediately disable or gate automatic public-database health uploads.** Define and test a consent-first data model before any external beta.
2. **Repair the test target** and require green test compilation/execution in CI.
3. **Harden sensor persistence:** atomic success semantics, retry/recovery, retention, deletion, file protection, and low-storage tests.
4. **Complete production service validation:** CloudKit schema/permissions, Sign in with Apple, HealthKit, BLE background behavior, StoreKit, and account/data deletion on real devices.
5. **Finish submission operations:** accurate App Store privacy answers, privacy policy/terms/support pages, real signed archive validation, screenshots, TestFlight cohort, and review notes.
6. **Resolve the onboarding discoverability issue** and perform a full accessibility/device-size pass.

## Review limitations and reproducibility notes

This review intentionally did not alter app source code. It produced build logs and runtime evidence under `.work/ios-evaluation/` and the deliverables in `outputs/`. The working tree was already non-clean during the audit, with many modified and untracked files, so a clean, tagged release commit should be created before repeatable CI and release evidence can be trusted.

The following were outside the verified scope: professional-app behavior, a device-signed archive/IPA, production CloudKit access-control rules, real hardware/BLE reliability, HealthKit behavior, Sign in with Apple completion, StoreKit purchase/restore, background execution on physical devices, App Store Connect metadata, network security testing, and legal/regulatory review.
