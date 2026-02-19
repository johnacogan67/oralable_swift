# Oralable Codebase Analysis & Launch Planning Session

**Date:** February 19, 2026
**Branch:** `claude/analyze-code-lSIFU`
**Objective:** Comprehensive codebase audit and construction of a launch timeline

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Overall Completion Status](#2-overall-completion-status)
3. [Codebase Audit — TODO & Placeholder Inventory](#3-codebase-audit--todo--placeholder-inventory)
4. [Critical Blocking Items](#4-critical-blocking-items)
5. [Version & Build Configuration](#5-version--build-configuration)
6. [CI/CD Pipeline](#6-cicd-pipeline)
7. [Subscription System Status](#7-subscription-system-status)
8. [Feature Flags & Hidden Functionality](#8-feature-flags--hidden-functionality)
9. [Test Infrastructure](#9-test-infrastructure)
10. [Technical Debt Summary](#10-technical-debt-summary)
11. [Launch Timeline (6-Phase Plan)](#11-launch-timeline-6-phase-plan)
12. [Risk Assessment](#12-risk-assessment)
13. [Post-Launch Roadmap](#13-post-launch-roadmap)
14. [Key Files & Documentation Index](#14-key-files--documentation-index)
15. [Recent Git History](#15-recent-git-history)
16. [Session Deliverables](#16-session-deliverables)

---

## 1. Project Overview

**Oralable** is a dual-app iOS platform for oral health monitoring built with Swift/SwiftUI:

| App | Target | Bundle ID | Version |
|-----|--------|-----------|---------|
| **Oralable** (Patient App) | Consumers | `com.jacdental.oralable` | 4.3 (build 1) |
| **Oralable for Professionals** (Dentist App) | Dental professionals | `com.jacdental.oralable.dentist` | 1.0 (build 1) |

**Core capabilities:**
- Real-time BLE biometric monitoring (PPG IR, EMG, heart rate, SpO2, temperature, accelerometer)
- Bruxism detection via Muscle Activity Monitoring (MAM) states
- HealthKit integration (read/write)
- CloudKit-powered patient-to-dentist data sharing via share codes
- StoreKit 2 subscription system (6 products across both apps)
- Sign in with Apple authentication

**Architecture:** SwiftUI + Combine, dependency injection container, MVVM, modular BLE/signal processing layer.

---

## 2. Overall Completion Status

```
███████████████████░░░░  85-90%  READY FOR FINAL PUSH
```

| Category | Completed | Total | Notes |
|----------|-----------|-------|-------|
| Critical launch items | 17 | 20 | 3 blocking items remain |
| Code & Architecture | Done | -- | DI, BLE, recording, HealthKit, share codes, subscriptions, dashboard |
| App Store Requirements | Done | -- | Privacy manifests, Info.plist, entitlements, app icons |
| Documentation | Done | -- | CloudKit guide, IAP guide, App Store metadata drafts |
| **Blocking items** | **0** | **3** | **CloudKit schema, IAP config, App Store submission** |

---

## 3. Codebase Audit -- TODO & Placeholder Inventory

### 13 TODO/FIXME comments found across the codebase

#### Subscription Placeholders (Critical -- 4 items)

| # | File | Line | Content |
|---|------|------|---------|
| 1 | `AuthenticationViewModel.swift` | 116 | `// TODO: Integrate with actual subscription system` -- `subscriptionStatus` returns `"Active"` |
| 2 | `AuthenticationViewModel.swift` | 121 | `// TODO: Integrate with actual subscription system` -- `subscriptionPlan` returns `"Free"` |
| 3 | `AuthenticationViewModel.swift` | 126 | `// TODO: Integrate with actual subscription system` -- `hasSubscription` returns `false` |
| 4 | `AuthenticationViewModel.swift` | 131 | `// TODO: Integrate with actual subscription system` -- `subscriptionExpiryText` returns `"N/A"` |

These four placeholders mean the subscription UI currently shows hardcoded values regardless of the user's actual purchase state. The underlying `SubscriptionManager` with full StoreKit 2 integration exists but is not wired into the auth view model.

#### Device & Sensor TODOs (Non-blocking -- 3 items)

| # | File | Line | Content |
|---|------|------|---------|
| 5 | `SubscriptionSettingsView.swift` | 97 | `// TODO: Add PPG channel configuration to DeviceManager if needed` |
| 6 | `SubscriptionSettingsView.swift` | 239 | `// TODO: Add firmware version to DeviceManager if available` |
| 7 | `BLESensorRepository.swift` | 342 | `// TODO: Add a filterHistory(olderThan:) method to SensorDataProcessor` |

#### Test Infrastructure TODOs (Non-blocking -- 2 items)

| # | File | Line | Content |
|---|------|------|---------|
| 8 | `DashboardViewModelTests.swift` | 23 | `/// TODO: Create proper mock infrastructure for these dependencies` |
| 9 | `DashboardViewModelTests.swift` | 24 | `/// TODO: Update tests to work with new recording flow via RecordingStateCoordinator` |

#### Dependency Injection TODOs (Medium -- 2 items)

| # | File | Line | Content |
|---|------|------|---------|
| 10 | `ProfessionaltAppDependencies.swift` | 59 | `self.subscriptionManager = ProfessionalSubscriptionManager.shared  // TODO: Remove singleton` |
| 11 | `ProfessionaltAppDependencies.swift` | 60 | `self.dataManager = ProfessionalDataManager.shared  // TODO: Remove singleton` |

#### Feature & Signal Processing TODOs (Low -- 2 items)

| # | File | Line | Content |
|---|------|------|---------|
| 12 | `FeatureFlags.swift` | 145 | `// TODO: Enable these when implementations are complete` (PDF export) |
| 13 | `UnifiedBiometricProcessor.swift` | 459 | `// TODO: Add FFT fallback in future version` |

---

## 4. Critical Blocking Items

These 3 items prevent App Store submission. All are infrastructure/manual tasks (not code changes).

### 4.1 CloudKit Production Schema Deployment

- **Status:** PENDING
- **Estimated effort:** 3-4 hours
- **What it blocks:** Patient-to-dentist data sharing in production
- **Guide:** `CLOUDKIT_PRODUCTION_SETUP.md`
- **Details:**
  - Deploy 3 record types: `ShareInvitation`, `SharedPatientData`, `HealthDataRecord`
  - Configure indexes and security roles in CloudKit Console
  - Container: `iCloud.com.jacdental.oralable.shared`
  - Code already uses `DEBUG`/`RELEASE` conditional database selection
  - Must test in RELEASE mode on physical device after deployment

### 4.2 App Store Connect IAP Configuration

- **Status:** PENDING
- **Estimated effort:** 5-6 hours
- **What it blocks:** Subscriptions won't load in production builds
- **Guide:** `APP_STORE_CONNECT_IAP_SETUP.md`
- **Products to create:**

| App | Product ID | Price |
|-----|-----------|-------|
| Patient | `com.jacdental.oralable.premium.monthly` | 9.99/mo |
| Patient | `com.jacdental.oralable.premium.yearly` | 99.99/yr |
| Dentist | `com.jacdental.oralable.dentist.professional.monthly` | 29.99/mo |
| Dentist | `com.jacdental.oralable.dentist.professional.yearly` | 299.99/yr |
| Dentist | `com.jacdental.oralable.dentist.practice.monthly` | 99.99/mo |
| Dentist | `com.jacdental.oralable.dentist.practice.yearly` | 999.99/yr |

- Sandbox testing with 2+ accounts required after product creation
- IAP products require 24-48 hours for Apple review

### 4.3 App Store Metadata & Submission

- **Status:** PENDING
- **Estimated effort:** 6-8 hours
- **What it blocks:** Cannot submit to App Store
- **Guides:** `APP_STORE_METADATA.md`, `DENTIST_APP_STORE_METADATA.md`
- **Key requirements:**
  - 7 screenshots per app
  - Privacy policy URL: `https://oralable.com/privacy`
  - Support URL: `https://oralable.com/support`
  - App review notes with demo share code: `123456`
  - Age rating: 4+ (patient), 17+ (dentist)

---

## 5. Version & Build Configuration

### Xcode Project Versions

| Target | `MARKETING_VERSION` | `CURRENT_PROJECT_VERSION` |
|--------|-------------------|--------------------------|
| OralableApp | 4.3 | 1 |
| OralableAppTests | 4.3 | 1 |
| OralableForProfessionals | 1.0 | 1 |
| OralableForProfessionalsTests | 1.0 | 1 |

Version numbers are set in the Xcode project (`pbxproj`) and referenced via `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` in `Info.plist` files.

### Info.plist Files

| App | Path |
|-----|------|
| Patient | `OralableApp/OralableApp/Info.plist` |
| Dentist | `OralableApp/OralableForProfessionals/Info.plist` |

---

## 6. CI/CD Pipeline

**File:** `.github/workflows/ios.yml`

| Setting | Value |
|---------|-------|
| Runner | `macos-latest` |
| Trigger | Push to `main`, PRs to `main` |
| Build step | `xcodebuild build-for-testing` (iPhone simulator) |
| Test step | `xcodebuild test-without-building` (iPhone simulator) |
| Checkout action | `actions/checkout@v4` |

The workflow is properly configured. It automatically discovers the default scheme from the Xcode project.

---

## 7. Subscription System Status

### Backend (Implemented)

- `SubscriptionManager.swift` -- Full StoreKit 2 implementation
- Subscription tiers defined: Basic (free) and Premium
- 6 subscription products defined for both patient and dentist apps
- `SubscriptionSettingsView` and `SubscriptionGate` UI components exist
- Local StoreKit configuration files for testing:
  - `Configuration.storekit` (patient)
  - `OralableForDentists/DentistConfiguration.storekit` (dentist)

### Frontend (Incomplete)

The `AuthenticationViewModel` does **not** query the real `SubscriptionManager`. Four computed properties return hardcoded placeholder values:

```swift
var subscriptionStatus: String { return "Active" }      // line 117
var subscriptionPlan: String { return "Free" }           // line 122
var hasSubscription: Bool { return false }               // line 127
var subscriptionExpiryText: String { return "N/A" }      // line 132
```

**Resolution:** Wire these properties to `SubscriptionManager`'s published state. Estimated: 2-3 hours.

### Feature Flag

The subscription UI is hidden behind a feature flag:
- `FeatureFlags.showSubscription` defaults to `false` for pre-launch
- Must be toggled to `true` (or use `applyFullConfig()` / `applyWellnessConfig()`) to show

---

## 8. Feature Flags & Hidden Functionality

**File:** `OralableApp/OralableApp/Managers/FeatureFlags.swift`

The app uses a runtime feature flag system persisted in `UserDefaults`, accessible via Developer Settings (tap version label 7 times).

### Default Pre-Launch Configuration

| Flag | Default | Category |
|------|---------|----------|
| `showEMGCard` | `false` | Dashboard |
| `showHeartRateCard` | `false` | Dashboard |
| `showBatteryCard` | `false` | Dashboard |
| `showMovementCard` | `false` | Dashboard |
| `showTemperatureCard` | `false` | Dashboard |
| `showSpO2Card` | `false` | Dashboard |
| `showAdvancedMetrics` | `false` | Dashboard |
| `showShareWithProfessional` | `true` | Sharing |
| `showShareWithResearcher` | `false` | Sharing |
| `showSubscription` | `false` | Settings |
| `showDetectionSettings` | `false` | Settings |
| `showCloudKitShare` | `false` | Sharing |
| `demoModeEnabled` | `false` | Demo |
| `showPilotStudy` | `false` | Research |
| `showPDFExport` | `false` | Export (v1.1) |

**Note:** Only the PPG IR card is always shown in pre-launch mode. All other dashboard cards are hidden.

### Available Configuration Presets

| Preset | Method | Description |
|--------|--------|-------------|
| Pre-Launch | `applyPreLaunchConfig()` | PPG IR only, minimal UI |
| App Store Minimal | `applyAppStoreMinimalConfig()` | PPG IR only, CSV export, no CloudKit |
| Wellness | `applyWellnessConfig()` | Consumer features (EMG, movement, temp, battery) |
| Full | `applyFullConfig()` | All features enabled |
| Research | `applyResearchConfig()` | All features enabled including researcher sharing |

---

## 9. Test Infrastructure

### Build Validation Tests

`BuildValidationTests.swift` scans for dangerous patterns:
- `fatalError("TODO"` / `assertionFailure("TODO"`
- `// TODO: REMOVE BEFORE RELEASE` / `// FIXME: REMOVE BEFORE RELEASE`
- No such patterns currently exist in the main source code

### Dashboard ViewModel Tests

`DashboardViewModelTests.swift` requires updates:
- Mock infrastructure needs to be created for dependencies
- Tests need updating for new recording flow via `RecordingStateCoordinator`

### StoreKit Test Configurations

- Patient app: `Configuration.storekit`
- Dentist app: `DentistConfiguration.storekit`
- Both support local StoreKit 2 testing in Xcode

---

## 10. Technical Debt Summary

| Priority | Item | Location | Notes |
|----------|------|----------|-------|
| High | Subscription placeholders in AuthViewModel | `AuthenticationViewModel.swift:115-132` | 4 hardcoded values not connected to SubscriptionManager |
| Medium | Singleton pattern in Professional app DI | `ProfessionaltAppDependencies.swift:59-60` | Should use DI container like patient app |
| Medium | Dashboard test mocks outdated | `DashboardViewModelTests.swift:23-24` | Need proper mock infra for RecordingStateCoordinator |
| Low | PPG channel config not exposed | `SubscriptionSettingsView.swift:97` | DeviceManager enhancement |
| Low | Firmware version not tracked | `SubscriptionSettingsView.swift:239` | DeviceManager enhancement |
| Low | Sensor history filter missing | `BLESensorRepository.swift:342` | `filterHistory(olderThan:)` not yet on SensorDataProcessor |
| Low | FFT fallback not implemented | `UnifiedBiometricProcessor.swift:459` | Future version |
| Low | PDF export not implemented | `FeatureFlags.swift:148` | Planned for v1.1 |
| Low | Some `Logger.shared.debug()` calls remain | Various | Cleanup pass needed |

---

## 11. Launch Timeline (6-Phase Plan)

> Full details in `LAUNCH_TIMELINE.md`

### Phase 1: Code Completion -- Days 1-3 (~Feb 19-21)

| Task | Hours |
|------|-------|
| Wire subscription into AuthenticationViewModel | 2-3 |
| Enable dashboard feature flags | 1 |
| Remove Professional app singletons | 1-2 |
| Remaining TODOs (PPG, firmware, history filter) | 2-3 |
| Update DashboardViewModel test mocks | 2 |

### Phase 2: Infrastructure Setup -- Days 3-5 (~Feb 21-25)

| Task | Hours |
|------|-------|
| CloudKit production schema deployment | 3-4 |
| App Store Connect IAP configuration (6 products) | 5-6 |
| IAP sandbox testing (2+ accounts) | 2-3 |
| CloudKit end-to-end verification | 1-2 |

### Phase 3: Legal & Compliance -- Days 4-7 (~Feb 22-28)

| Task | Duration |
|------|----------|
| Privacy policy attorney review | External |
| Terms of service attorney review | External |
| Publish legal docs to oralable.com | 2 hours |
| Support page creation | 1-2 hours |
| Tax & banking forms | 1-2 hours |
| HIPAA compliance evaluation | External |

### Phase 4: App Store Metadata & Screenshots -- Days 6-8 (~Feb 26-Mar 2)

| Task | Hours |
|------|-------|
| 7 screenshots for patient app | 3-4 |
| 7 screenshots for dentist app | 3-4 |
| Finalize App Store descriptions | 1-2 |
| Configure App Store Connect metadata | 1-2 |
| Prepare demo share code for App Review | 0.5 |

### Phase 5: Beta Testing via TestFlight -- Days 8-18 (~Mar 2-12)

| Task | Duration |
|------|----------|
| Submit build to TestFlight | 1 day |
| Internal testing (core team, physical devices) | 2-3 days |
| External beta (10+ testers, real sessions) | 5-7 days |
| Bug triage and fixes | 2-3 days |
| Final build | 1 day |

### Phase 6: App Store Submission & Review -- Days 18-25 (~Mar 12-19)

| Task | Duration |
|------|----------|
| Submit both apps for review | -- |
| Apple review | 1-5 days |
| Address feedback (if any) | 1-3 days |
| Resubmission (budget for one cycle) | 1-5 days |

### Visual Summary

```
Week 1  ________##  Code completion + Infrastructure setup
Week 2  ##########  Legal/compliance + Metadata + Screenshots
Week 3  ##########  TestFlight beta begins
Week 4  ########__  Beta continues + Bug fixes
Week 5  ##########  Final build + App Store submission
Week 6  ####______  Review + Approval + Launch
```

### Key Milestones

| Milestone | Target Date |
|-----------|-------------|
| Code freeze | ~Feb 25 |
| CloudKit + IAP production ready | ~Feb 25 |
| Legal docs published | ~Mar 4 |
| TestFlight beta begins | ~Mar 5 |
| Beta complete | ~Mar 18 |
| App Store submission | ~Mar 19 |
| **Projected launch** | **~Mar 25 - Apr 1** |

---

## 12. Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| App Store rejection (health claims) | +1-2 weeks | Medium | Review Apple guidelines; avoid diagnostic language; frame as wellness monitoring |
| Legal review delays | +1-2 weeks | Medium | Engage attorney early; templates already prepared |
| HIPAA compliance requirement | +2-4 weeks | Low-Medium | CloudKit is NOT HIPAA-certified; evaluate client-side encryption or alternate backend |
| IAP product review delay | +2-3 days | Low | Submit IAP products before full app submission |
| BLE hardware availability for beta | +1 week | Low | Ensure test devices; leverage demo mode |
| Critical bugs found in beta | +1-2 weeks | Medium | Prioritize BLE reconnection and CloudKit failure recovery |

### HIPAA Note

CloudKit is not HIPAA-certified. The app stores and transmits health-related sensor data. Before launch, a decision is needed on:
- Whether client-side encryption is sufficient
- Whether a HIPAA-compliant backend (e.g., AWS HIPAA, Azure HIPAA) is required
- How the HIPAA disclaimer in the privacy policy should be worded

---

## 13. Post-Launch Roadmap

From existing documentation (`APP_STORE_METADATA.md`, `DENTIST_APP_STORE_METADATA.md`):

| Version | Target | Features |
|---------|--------|----------|
| v1.1 | Q2 2026 | PDF export, localization (Spanish, French, German), enhanced analytics |
| v1.2 | Q3 2026 | Additional language support, practice management enhancements |
| v1.3 | Q4 2026 | Advanced reporting, expanded device support |

---

## 14. Key Files & Documentation Index

### Documentation

| File | Description |
|------|-------------|
| `OralableApp/LAUNCH_READINESS_CHECKLIST.md` | Master launch checklist (last updated Nov 19, 2025) |
| `LAUNCH_TIMELINE.md` | 6-phase launch timeline (created this session) |
| `OralableApp/CLOUDKIT_PRODUCTION_SETUP.md` | CloudKit deployment guide |
| `OralableApp/APP_STORE_CONNECT_IAP_SETUP.md` | Subscription setup guide |
| `OralableApp/APP_STORE_METADATA.md` | Patient app store descriptions and screenshot strategy |
| `OralableApp/DENTIST_APP_STORE_METADATA.md` | Dentist app store descriptions |
| `OralableApp/PRIVACY_POLICY_TEMPLATE.md` | Privacy policy template |
| `OralableApp/TERMS_OF_SERVICE_TEMPLATE.md` | Terms of service template |

### Critical Code Files

| File | Purpose |
|------|---------|
| `OralableApp/Managers/FeatureFlags.swift` | Runtime feature flag management |
| `OralableApp/ViewModels/AuthenticationViewModel.swift` | Auth state + subscription placeholders |
| `OralableApp/Services/SubscriptionManager.swift` | StoreKit 2 implementation |
| `OralableApp/Views/BLESensorRepository.swift` | BLE sensor data handling |
| `OralableApp/Services/UnifiedBiometricProcessor.swift` | Signal processing pipeline |
| `OralableForProfessionals/Managers/ProfessionaltAppDependencies.swift` | Dentist app DI (with singleton TODOs) |

### Configuration Files

| File | Purpose |
|------|---------|
| `.github/workflows/ios.yml` | CI/CD pipeline |
| `OralableApp/OralableApp/Info.plist` | Patient app configuration |
| `OralableApp/OralableForProfessionals/Info.plist` | Dentist app configuration |
| `Configuration.storekit` | Patient StoreKit test config |
| `OralableForDentists/DentistConfiguration.storekit` | Dentist StoreKit test config |

---

## 15. Recent Git History

```
ce801b0  Add projected launch timeline based on codebase analysis
025d867  Add P2 structural improvements: DesignSystem adoption, DeviceManager decomposition, view extraction
9bb3de5  Add P2 improvements: accessibility, NavigationStack, error feedback
6c16d3f  Add P1 improvements: CircularBuffer migration, cached stats, signal tests
ae43988  Fix critical BLE and signal processing bugs
effbb42  Changes from Gemini
e37a7aa  Add BLE parser refactoring and signal processing algorithms
5e508a7  Add pulse morphology and HRV biomarkers from Python reference
6af728b  got BPM working
721a301  Replace manual recording with automatic state-based system
06aa74d  comment corrected
0138480  Remove temperature from device positioning detection
621da78  Add diagnostic logging for calibration pipeline and fix event file selection
880dd86  clean up after timemachine
9760c65  Update web pages: replace bruxism terminology and add documentation
```

---

## 16. Session Deliverables

| Deliverable | File | Status |
|-------------|------|--------|
| Launch timeline document | `LAUNCH_TIMELINE.md` | Committed (`ce801b0`) |
| Full session analysis document | `SESSION_ANALYSIS_2026-02-19.md` | This file |

Both files committed and pushed to `claude/analyze-code-lSIFU`.

---

*End of session analysis.*
