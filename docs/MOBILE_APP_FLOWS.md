# Oralable mobile apps — flows, screens, and roadmap

Canonical UX/navigation reference for **Oralable** (consumer) and **Oralable for Dentists** (professional).  
There are **no Figma/Sketch wireframes** in the repos; this document plus **implemented SwiftUI** are the source of truth.

**Related:** [LAUNCH_READINESS_CHECKLIST.md](../OralableApp/LAUNCH_READINESS_CHECKLIST.md) · [oralable_nrf/docs/ORALABLE_MARKET_LANDSCAPE.md](../../oralable_nrf/docs/ORALABLE_MARKET_LANDSCAPE.md) §5 · [cursor_oralable/docs/PRODUCT_ROADMAP.md](../../cursor_oralable/docs/PRODUCT_ROADMAP.md) · [cursor_oralable/docs/IP_NORTH_STAR.md](../../cursor_oralable/docs/IP_NORTH_STAR.md) · [cursor_oralable/docs/data_room/COST_AND_TIMELINE.md](../../cursor_oralable/docs/data_room/COST_AND_TIMELINE.md) · [cursor_oralable/docs/ALGORITHM_ARCHITECTURE.md](../../cursor_oralable/docs/ALGORITHM_ARCHITECTURE.md)

**Last updated:** 26 Jul 2026 · **Doc version:** 1.2.2 · FW **1.0.70** · app **4.3.3** · timeline → PRODUCT_ROADMAP §3

**Phase note (July 2026):** **Phase 0 Vitals** is the shipping UX — temple HR/SpO₂, placement picker, no muscle-fit calibration. Fit guide + `CalibrationWizardView` below are **Phase 1+ / legacy** paths (feature-flagged). Hardware: Gen1 · BOM REV8 · PCB REV10 · ES2832AA2 · FW **1.0.70** · app **4.3.3** (STAT blink = dock/charge; Automatic OK).

**Ed/Pedro:** ship **Oralable (patient) only**. Keep **Oralable for Dentists** and `showCloudKitShare` dark until Phase 1+ — see `cursor_oralable/docs/data_room/APPS_AND_REVENUE_EVAL.md`.

**Strategy:** Stage A wellness wearable → Stage B medical (later) · new US patent embodiment. Planning costs/timeline: `COST_AND_TIMELINE.md`.

---

## Table of contents

1. [Apps and bundles](#1-apps-and-bundles)
2. [Consumer app — launch and navigation](#2-consumer-app--launch-and-navigation)
3. [Consumer app — screen inventory](#3-consumer-app--screen-inventory)
4. [Professional app — navigation](#4-professional-app--navigation)
5. [Professional app — screen inventory](#5-professional-app--screen-inventory)
6. [Patient → dentist data flow](#6-patient--dentist-data-flow)
7. [BLE → UI data path](#7-ble--ui-data-path)
8. [Pre-launch UI (feature flags)](#8-pre-launch-ui-feature-flags)
9. [Done vs remaining](#9-done-vs-remaining)
10. [Roadmap and timeline](#10-roadmap-and-timeline)
11. [Source files (navigation)](#11-source-files-navigation)

---

## 1. Apps and bundles

| App | Target | Bundle ID | Entry point |
|-----|--------|-----------|-------------|
| **Oralable** | Patient / consumer | `com.jacdental.oralable` | `OralableApp/Oralable.swift` → `LaunchCoordinator` |
| **Oralable for Dentists** | Clinician / practice | `com.jacdental.oralable.dentist` | `OralableForProfessionals/OralableForProfessionals.swift` → `ProfessionalRootView` |

Shared: **OralableCore** (BLE parsing, algorithms, design tokens, `AutomaticRecordingSession`, CloudKit handshake export).

---

## 2. Consumer app — launch and navigation

**Controller:** `OralableApp/Views/LaunchCoordinator.swift`

```mermaid
flowchart TD
    START[App launch] --> LC[LaunchCoordinator]
    LC --> AUTH{isAuthenticated?}
    AUTH -->|No + first launch| OB[OnboardingView<br/>4 pages + Sign in with Apple]
    AUTH -->|No| LOGIN[LoginView]
    AUTH -->|Yes| SETUP{hasPairedOralablePrimary<br/>AND hasCompletedFirstFit?}
    SETUP -->|Yes| MAIN[MainTabView]
    SETUP -->|Trial mode| TRIAL[TrialSetupDashboardView]
    SETUP -->|Else| FIRST[FirstLaunchOnboardingView]
    FIRST --> DISC[DeviceDiscoveryView sheet]
    FIRST --> FIT[TemporalisFitGuideView]
    FIT --> CAL[CalibrationWizardView]
    CAL --> OK[SetupSuccessView]
    OK -->|Go to dashboard| MAIN
    MAIN --> TAB1[Dashboard tab]
    MAIN --> TAB2[Devices tab]
    MAIN --> TAB3[Share tab]
    MAIN --> TAB4[Settings tab]
```

### First-launch setup sequence

**Phase 0 (current):** pair → placement (temple / case / bench) → vitals dashboard. Calibration wizard is **not** required.

| Step | Screen | Purpose |
|------|--------|---------|
| 1 | `FirstLaunchOnboardingView` | Explain pair → place on temple → vitals |
| 2 | `DeviceDiscoveryView` | Scan/connect Oralable Gen1 REV10 (TGM `3A0FF000`) |
| 3 | Placement picker / Vitals device status | Manual or Automatic (FW ≥ 1.0.70 STAT); Charge/Taper chips |
| 4 | Dashboard | HR / SpO₂ with quality gating |

**Phase 1+ / legacy (muscle path — deferred):**

| Step | Screen | Purpose |
|------|--------|---------|
| 3′ | `TemporalisFitGuideView` | Mirror camera + placement on temporalis peak |
| 4′ | `CalibrationWizardView` | IR-DC baseline / coupling check |
| 5′ | `SetupSuccessView` | Confirm; **only here** → `markFirstFitCompleted()` → `MainTabView` |

**Trial path:** User can skip pairing → `TrialSetupDashboardView` (limited dashboard without full gold-standard setup).

**Auto-resume:** If `sessionHistoryStore.temporalisSleepCalibration` exists on launch, pairing + first-fit flags can be restored (`LaunchCoordinator.onAppear`).

### Main tabs (`MainTabView.swift`)

| Tab | Root view | Notes |
|-----|-----------|-------|
| Dashboard | `HomeView` → `DashboardView` **or** `SimplifiedDashboardView` | Toggle via Settings → `useSimplifiedDashboard` (`@AppStorage`) |
| Devices | `DevicesView` | BLE scan, paired devices, `DeviceDetailView` |
| Share | `ShareView` | Export CSV, share with professional (when enabled) |
| Settings | `SettingsView` | Health, support links, hidden developer settings (7-tap version) |

### Dashboard drill-down

```mermaid
flowchart LR
    DASH[DashboardView] --> HIST[HistoricalView]
    DASH --> PROF[ProfileView sheet]
    DASH --> DISC[DeviceDiscoveryView sheet]
    HIST --> DETAIL[HistoricalMetricDetailView]
    HIST --> SESSION[SessionHistoryView]
    DETAIL --> HDET[HistoricalDetailView]
```

**Recording:** Automatic on BLE connect (`AutomaticRecordingSession`); no manual start/stop on dashboard. State indicator: streaming / positioned / activity (`RecordingStateIndicator`).

---

## 3. Consumer app — screen inventory

| Screen | File | Status | Notes |
|--------|------|--------|-------|
| Launch coordinator | `LaunchCoordinator.swift` | ✅ Shipped | Single gate for auth + setup |
| Welcome onboarding | `OnboardingView.swift` | ✅ | 4 pages, Sign in with Apple, skip |
| Login | `LoginView.swift` | ✅ | Returning users |
| First-launch setup | `FirstLaunchOnboardingView.swift` | ✅ | Pair + fit entry |
| Trial dashboard | `TrialSetupDashboardView.swift` | ✅ | Skipped pairing |
| Main tabs | `MainTabView.swift` | ✅ | 4 tabs |
| Dashboard (full) | `DashboardView.swift` | ✅ | PPG IR always; optional cards behind flags |
| Dashboard (simplified) | `SimplifiedDashboardView.swift` | ✅ | Reduced layout |
| Apple Health summary strip | `DashboardView` (`showAppleHealthSummary`) | ✅ | TFI + SASHB cards when clinical metrics on |
| Devices list | `DevicesView.swift` | ✅ | |
| Device discovery | `DeviceDiscoveryView.swift` | ✅ | Scan + pair |
| Device detail | `DeviceDetailView.swift` | ✅ | |
| Share / export | `ShareView.swift` | ✅ | CSV paths; CloudKit share gated |
| Professional share section | `ProfessionalShareView.swift`, share components | ✅ | Behind `showCloudKitShare` |
| Settings | `SettingsView.swift` | ✅ | |
| Subscription | `SubscriptionSettingsView.swift` | ✅ | Behind `showSubscription` |
| Thresholds / events | `ThresholdsSettingsView.swift`, `EventSettingsView.swift` | ✅ | Behind flags |
| Developer settings | `DeveloperSettingsView.swift` | ✅ | Feature flags, demo mode, FW tools |
| Historical overview | `HistoricalView.swift` | ✅ | Charts, date navigation |
| Historical detail | `HistoricalDetailView.swift` | ⚠️ Partial | PDF + HealthKit export stubs |
| Session history | `SessionHistoryView.swift` | ✅ | |
| Temporalis fit guide | `TemporalisFitGuideView.swift` | ✅ | Mirror + calibration flow |
| Calibration | `CalibrationWizardView.swift`, `CalibrationView.swift` | ✅ | |
| Setup success | `SetupSuccessView.swift` | ✅ | Gates main app |
| Profile | `ProfileView.swift` | ✅ | |
| Logs / debug | `LogsView.swift`, `DebugMenuView.swift` | ✅ Dev | |
| Worn status | `WornStatusView.swift` | ✅ | Off-body indicator |
| Subscription tier picker | `SubscriptionTierSelectionView.swift` | ✅ | |

**Component library:** `OralableApp/Components/`, `DesignSystem.swift`, `OralableCore/DesignSystem/`.

---

## 4. Professional app — navigation

**Controller:** `ProfessionalRootView` in `OralableForProfessionals.swift`

```mermaid
flowchart TD
    START[App launch] --> ROOT[ProfessionalRootView]
    ROOT --> AUTH{isAuthenticated?}
    AUTH -->|No| POB[ProfessionalOnboardingView<br/>3 pages + Sign in with Apple]
    AUTH -->|Yes| TABS[ProfessionalMainTabView]
    TABS --> PL[PatientListView]
    TABS --> SET[ProfessionalsSettingsView]
    PL --> ADD[AddPatientView<br/>share code / CSV]
    PL --> PD[PatientDetailView sheet]
    PD --> PDB[PatientDashboardView]
    PDB --> PH[PatientHistoricalView]
    PL --> DEMO[DemoParticipantDetailView<br/>demo data]
```

---

## 5. Professional app — screen inventory

| Screen | File | Status | Notes |
|--------|------|--------|-------|
| Professional onboarding | `OralableForProfessionals.swift` | ✅ | 3 pages + Sign in |
| Participant list | `PatientListView.swift` | ✅ | Search, empty state, upgrade banner |
| Add participant | `AddPatientView.swift` | ✅ | 6-digit share code + CSV import |
| Participant detail | `PatientDetailView.swift` | ✅ | Wraps dashboard |
| Participant dashboard | `PatientDashboardView.swift` | ✅ | TFI / session summary |
| Participant historical | `PatientHistoricalView.swift` | ✅ | Multi-session charts |
| Demo participant | `DemoParticipantDetailView.swift` | ✅ | `DemoDataManager` |
| Settings | `ProfessionalsSettingsView.swift` | ✅ | |
| Upgrade prompt | `UpgradePromptView.swift` | ✅ | Starter tier limits |
| Developer settings | `DeveloperSettingsView.swift` | ✅ | |

---

## 6. Patient → dentist data flow

```mermaid
sequenceDiagram
    participant D as Oralable REV10
    participant C as Consumer app
    participant CK as CloudKit shared DB
    participant P as Dentist app

    D->>C: BLE 50 Hz PPG/ACC (worn-gated)
    C->>C: AutomaticRecordingSession + rollups
    C->>CK: SharedDataManager upload (LZFSE JSON)
    Note over CK: ShareInvitation + HealthDataRecord
    P->>CK: ProfessionalDataManager query by share code
    P->>P: PatientDashboardView / historical charts
    P->>P: Optional CSV import (CSVParser)
```

**Handshake export:** `OralableCore` `ProfessionalHandshakeExport` — hourly TFI / SASHB for clinician review.

**Launch blocker:** Production CloudKit schema not deployed — see [CLOUDKIT_PRODUCTION_SETUP.md](../OralableApp/CLOUDKIT_PRODUCTION_SETUP.md).

---

## 7. BLE → UI data path

Technical flow (not screen flow). See also `cursor_oralable/docs/upload/02_IOS_BLE_STREAMING_SUMMARY.txt`.

```
Oralable REV10 (TGM GATT 3A0FF000)
  → BLECentralManager (NotifyOnDisconnection)
    → DeviceConnectionCoordinator (discover → FW gate → placement → awaited staggered CCC)
      → OralableDevice + BLEDataParser (OralableCore)
        → DeviceManagerAdapter (50 Hz alignment)
          ├→ SensorDataProcessor → history, auto-flush CSV
          ├→ UnifiedBiometricProcessor → HR, SpO₂, TFI
          ├→ AutomaticRecordingSession → state events, pause/resume on disconnect
          └→ DashboardViewModel → DashboardView UI
```

**Connect readiness:** `disconnected` → `connecting` → … → `enablingNotifications` → `ready` when PPG + ACC + **status + battery** CCC confirms are set (`OralableDevice.NotificationReadiness.allRequired`).

**CCC order (await each `didUpdateNotificationState`):** battery `004` → status `009` → PPG `001` → ACC `002` → temp `003`. Battery CCC and streaming CCC blocks use **timeouts**; on failure the coordinator calls `cancelPendingContinuations()` so waiters do not hang. Disable/`isNotifying == false` also resumes waiters with error.

---

## 8. Pre-launch UI (feature flags)

`FeatureFlags.swift` — toggles in **Developer Settings** (tap app version 7× in Settings).

| Flag | Default (pre-launch) | UI affected |
|------|----------------------|-------------|
| `showHeartRateCard` | **false** | Dashboard HR card |
| `showSpO2Card` | **false** | Dashboard SpO₂ card |
| `showMovementCard` | **false** | Movement / ACC card |
| `showTemperatureCard` | **false** | Temperature card |
| `showBatteryCard` | **false** | Battery card |
| `showEMGCard` | **false** | EMG card (ANR path) |
| `showSubscription` | **false** | Settings subscription section |
| `showCloudKitShare` | **false** | Share with professional |
| `showDetectionSettings` | **false** | Thresholds / event settings |
| `showPilotStudy` | **false** | Pilot UI |
| PPG IR card | **always on** | Core dashboard waveform |

**App Store screenshots** should reflect **flag-off** consumer UI unless you intentionally launch with flags lifted.

### Firmware diagnostics (Developer Settings, FW ≥ 1.0.37)

Hidden: Settings → About → tap version **7×** → **Developer Settings**.

| Action | BLE | Purpose |
|--------|-----|---------|
| Auto on connect | Notify `3A0FF00A` | Firmware log lines → app log + nRF CSV export |
| **Dump firmware diagnostics** | Write `3A0FF00B` opcode `0x07`, read `3A0FF00C` | Snapshot charging/worn/battery + config state |
| **Apply firmware settings** | Write `3A0FF00B` TLV | LED PA, intervals, stream mask (bench) |
| **Export nRF-style CSV** | — | Full session log for side-by-side with nRF Connect |

iOS `FirmwareGate` minimum **1.0.63** (hard gate). Recommend **1.0.70** (`recommendedOralableSemanticVersion`) for Automatic dock via LTC4124 STAT blink/taper. Older than **1.0.70** still connect with manual placement. Bench matrix: [ORALABLE_SYSTEM_ARCHITECTURE.md](../../cursor_oralable/docs/ORALABLE_SYSTEM_ARCHITECTURE.md#3-validation-status-matrix-where-we-are).

---

## 9. Done vs remaining

### ✅ Implemented (code-complete)

- Dual-app architecture + OralableCore
- Full launch graph (auth → onboarding → setup → tabs)
- Real-time dashboard + historical charts + session history
- Automatic recording with disconnect pause/resume
- BLE nRF Connect–aligned connect (FW ≥ 1.0.36 gate; awaited CCC; fw-log `00A`–`00C` when FW ≥ 1.0.37)
- **Vitals phase:** `VitalsDeviceStatusCard` + **Device LED mirror** (`DeviceStatusLEDView` / OralableCore `statusLED()`)
- Share/export CSV paths, clinical PDF generator (server-side path in app)
- StoreKit 2 code (6 IAP products)
- Design system + asset colors (both apps)
- UI tests: `OnboardingUITests`, `NavigationTests`, `NRFConnectCompatibilityTests`
- Demo data path for dentist app

### ⏳ Launch blockers (infra, not UI code)

| Item | Doc |
|------|-----|
| CloudKit production schema | `CLOUDKIT_PRODUCTION_SETUP.md` |
| App Store Connect IAP live | `APP_STORE_CONNECT_IAP_SETUP.md` |
| Metadata + screenshots + submission | `APP_STORE_METADATA.md`, `DENTIST_APP_STORE_METADATA.md` |

### ✅ Shipped (export path) — morning card still open

| Item | Spec reference | Notes |
|------|----------------|-------|
| **Overnight clinical PDF** | [OVERNIGHT_NIGHT_REPORT.md](../../cursor_oralable/docs/OVERNIGHT_NIGHT_REPORT.md) · FTS APP-10 | Share → Clinical Temporalis Report — hypnogram-first, hourly stack, dual-rail, event CSV. **In-app morning card / Figma still open.** |

### 🔲 Product UX not designed or built

| Item | Spec reference | Notes |
|------|----------------|-------|
| **Wireframes / screen map (visual)** | — | **This doc** replaces until Figma exists |
| **Overnight morning card (in-app)** | OVERNIGHT_NIGHT_REPORT · APP-10 remainder | Band chips + hypnogram on dashboard/history — PDF path already shipped |
| **App Store screenshot designs** | Launch checklist | 7 per app — copy exists, art not in repo |
| PDF export from `HistoricalDetailView` | Launch checklist known issues | Stub at line ~73 |
| HealthKit export from historical | Launch checklist | Stub |
| Dentist onboarding guide (PDF/web) | Launch checklist post-launch | |
| Android app | Landscape §10 | Native Kotlin MVP, 2026 H2 target |
| In-app firmware OTA | Landscape §12 | Use Nordic Device Manager for now |
| iPad / Watch / widgets | Launch checklist post-launch | |

---

## 10. Roadmap and timeline

Aligns with [PRODUCT_ROADMAP.md](../../cursor_oralable/docs/PRODUCT_ROADMAP.md), [IP_NORTH_STAR.md](../../cursor_oralable/docs/IP_NORTH_STAR.md), [COST_AND_TIMELINE.md](../../cursor_oralable/docs/data_room/COST_AND_TIMELINE.md), [LAUNCH_READINESS_CHECKLIST.md](../OralableApp/LAUNCH_READINESS_CHECKLIST.md), and [ORALABLE_MARKET_LANDSCAPE.md](../../oralable_nrf/docs/ORALABLE_MARKET_LANDSCAPE.md) §12.

| Phase | Target | Hardware | Deliverables |
|-------|--------|----------|--------------|
| **Phase 0 — Vitals** | Now – Sep 2026 | Gen1 BOM REV8 / REV10 / FW **1.0.70** · app **4.3.3** | Temple HR/SpO₂; placement + STAT LED mirror; kits **gated**; patient app only |
| **Eng overnight PDF** | **Shipped 24 Jul 2026** | Same Gen1 | Share clinical PDF + Mac night pack (hypnogram-first) — early eng, not Phase 1+ complete |
| **Phase 1+ — Muscle** | Q4 2026 – Q1 2027 | **Same Gen1** hardware | IR-DC / TFI / SASHB live UX; Protocol B; ≥6 h overnight eval; morning card |
| **Gen2 hardware** | Q4 2026 – H2 2027 | BOM REV9 / REV11 / ES4L15BA1 / FW 2.0.x | Same GATT; longer battery; chrsts/SOC/LED targets |
| **P4 — Android MVP** | Q3–Q4 2026+ | Gen1 stream | Kotlin BLE + local CSV |
| **P5 — Regulated UI** | H2 2027 – 2028 | Gen2 primary | SaMD-locked labeling, 510(k) monitoring claims |

Canonical calendar: [PRODUCT_ROADMAP.md §3](../../cursor_oralable/docs/PRODUCT_ROADMAP.md#3-timeline-calendar--canonical).

### Unified overnight report (status)

**Canonical direction:** [`OVERNIGHT_NIGHT_REPORT.md`](../../cursor_oralable/docs/OVERNIGHT_NIGHT_REPORT.md)

- **Evaluable overnight:** **≥ 6 hours** worn (goal **8 h**). Under 6 h → Insufficient data (no bands).
- **Scoring:** blood-pressure-style **Low / Moderate / High** on TFI, SASHB/h, rescue/h, tonic min/h — **not** sleep-score-first; cohort percentiles later; personal trends first.
- **Primary graphic:** **state hypnogram** (most useful overnight view). Hourly stack and dual-rail support dentist detail; 3D is appendix.

**Shipped (Share PDF):** `ClinicalReportGenerator` + `OvernightStateClassifier` + `NightReportSampleLoader`  
Pages: KPIs → **bout hypnogram (lead)** → hourly stack + SASHB → smoking-gun IR-DC/SpO₂ → event table; plus `Oralable_Night_Events_*.csv`.  
Samples from `sensorDataHistory` + memory-flush CSVs + session `dataFilePath`.

**Still open (UI):** morning card with **three band chips + hypnogram**:

```
┌─────────────────────────────────────────┐
│  Night · ≥6h · Jaw load | O2 | Rescue   │  ← Low / Moderate / High chips
├─────────────────────────────────────────┤
│  State hypnogram (primary)              │
├─────────────────────────────────────────┤
│  Hourly stack + SASHB (secondary)       │
├─────────────────────────────────────────┤
│  [Share PDF] [Send to dentist]          │
└─────────────────────────────────────────┘
```

Consumer: Share clinical PDF today; later `OvernightReportView`.  
Dentist: same bands + hypnogram language; handshake hourly rollups.

---

## 11. Source files (navigation)

| Concern | Path |
|---------|------|
| Consumer launch flow | `OralableApp/Views/LaunchCoordinator.swift` |
| Consumer tabs | `OralableApp/Views/MainTabView.swift` |
| First-launch state | `OralableApp/Managers/FirstLaunchManager.swift` |
| Professional root | `OralableForProfessionals/OralableForProfessionals.swift` |
| Feature flags | `OralableApp/Managers/FeatureFlags.swift` |
| CloudKit share | `OralableApp/Managers/SharedDataManager.swift` |
| Pro data ingest | `OralableForProfessionals/Managers/ProfessionalDataManager.swift` |
| Design tokens | `OralableCore/Sources/OralableCore/DesignSystem/` |

---

*Maintainers: update this file when adding a new root navigation path or shipping a major UX phase. Bump version in footer when structure changes.*
