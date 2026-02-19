# Oralable Launch Timeline

> Generated 2026-02-19 | Based on codebase analysis at 85–90% completion (17/20 critical items done)

---

## Phase 1: Code Completion (Days 1–3)

Resolve remaining TODOs and placeholder code before entering the submission pipeline.

| Task | Est. Hours | Details |
|------|-----------|---------|
| Wire subscription system into AuthenticationViewModel | 2–3 | 4 TODO items returning placeholder values (`"Active"`, `"Free"`, `false`, `"N/A"`) |
| Enable dashboard feature flags | 1 | EMG, HR, battery, movement, temperature, SpO2 cards all disabled in `FeatureFlags.swift` |
| Remove singleton pattern from Professional app DI | 1–2 | `ProfessionalSubscriptionManager.shared` and `ProfessionalDataManager.shared` |
| Address remaining TODOs (PPG config, firmware version, sensor history filter) | 2–3 | Non-blocking but improve quality |
| Update DashboardViewModel test mocks | 2 | Tests reference outdated recording flow |

**Phase 1 total: ~2–3 days (1 developer)**

---

## Phase 2: Infrastructure Setup (Days 3–5)

Deploy production backends. Can partially overlap with Phase 1.

| Task | Est. Hours | Details |
|------|-----------|---------|
| **CloudKit production schema deployment** | 3–4 | Deploy 3 record types (ShareInvitation, SharedPatientData, HealthDataRecord), configure indexes and security roles, test in RELEASE mode on physical device |
| **App Store Connect IAP configuration** | 5–6 | Create 2 subscription groups, add 6 products (2 patient + 4 dentist), localize descriptions, submit for product review |
| IAP sandbox testing | 2–3 | 2+ test accounts, test purchase/restore/cancel/expire flows |
| CloudKit end-to-end verification | 1–2 | Share code creation, data sync, professional access |

**Phase 2 total: ~2–3 days (1 developer)**

> IAP products require 24–48 hours for Apple review after submission.

---

## Phase 3: Legal & Compliance (Days 4–7)

Can run in parallel with Phase 2. Requires external coordination.

| Task | Est. Hours | Details |
|------|-----------|---------|
| Legal review of Privacy Policy | External | Template exists — needs attorney review, especially re: HIPAA disclaimer and health data |
| Legal review of Terms of Service | External | Template exists — needs attorney customization |
| Publish privacy policy to `oralable.com/privacy` | 1 | Required before App Store submission |
| Publish terms of service to `oralable.com/terms` | 1 | Required before App Store submission |
| Create support page at `oralable.com/support` | 1–2 | Required App Store field |
| Complete App Store Connect tax & banking forms | 1–2 | Required for paid apps / IAP |
| Evaluate HIPAA compliance gap | External | CloudKit is not HIPAA-certified — decide if additional client-side encryption or alternate backend is needed before launch |

**Phase 3 total: ~1 week (dependent on legal turnaround)**

---

## Phase 4: App Store Metadata & Screenshots (Days 6–8)

| Task | Est. Hours | Details |
|------|-----------|---------|
| Capture 7 screenshots for patient app | 3–4 | Hero monitoring, bruxism detection, sharing, analytics, HealthKit, premium, device compatibility |
| Capture 7 screenshots for dentist app | 3–4 | Patient dashboard, data review, practice management |
| Write/finalize App Store descriptions | 1–2 | Drafts exist in `APP_STORE_METADATA.md` and `DENTIST_APP_STORE_METADATA.md` |
| Configure App Store Connect metadata | 1–2 | Categories, age ratings, review notes, demo account |
| Prepare demo share code for App Review | 0.5 | Code `123456` already documented |

**Phase 4 total: ~2 days**

---

## Phase 5: Beta Testing via TestFlight (Days 8–18)

| Task | Est. Duration | Details |
|------|--------------|---------|
| Submit build to TestFlight | 1 day | Archive, upload, wait for processing |
| Internal testing | 2–3 days | Core team validation on physical devices with real BLE hardware |
| External beta (10+ testers) | 5–7 days | Real-world bruxism monitoring sessions, share code flow, subscription flow |
| Bug triage and fixes | 2–3 days | Address critical issues found during beta |
| Final build with fixes | 1 day | Version bump, re-upload |

**Phase 5 total: ~10 days**

---

## Phase 6: App Store Submission & Review (Days 18–25)

| Task | Est. Duration | Details |
|------|--------------|---------|
| Submit patient app for review | — | Include demo device instructions and share code |
| Submit dentist app for review | — | Include demo share code `123456` |
| App Store review | 1–5 days | Typical review time; health apps may get additional scrutiny |
| Address review feedback (if any) | 1–3 days | Common issues: health claims wording, subscription disclosures |
| Resubmission (if rejected) | 1–5 days | Budget for one rejection cycle |

**Phase 6 total: ~5–7 days**

---

## Projected Timeline Summary

```
Week 1  ████████░░  Code completion + Infrastructure setup
Week 2  ██████████  Legal/compliance + Metadata + Screenshots
Week 3  ██████████  TestFlight beta begins
Week 4  ████████░░  Beta continues + Bug fixes
Week 5  ██████████  Final build + App Store submission
Week 6  ████░░░░░░  Review + Approval + Launch
```

| Milestone | Target Date | Status |
|-----------|-------------|--------|
| Code freeze (all TODOs resolved) | Week 1 end (~Feb 25) | Pending |
| CloudKit + IAP production ready | Week 1 end (~Feb 25) | Pending |
| Legal docs published | Week 2 end (~Mar 4) | Pending |
| TestFlight beta begins | Week 3 start (~Mar 5) | Pending |
| Beta complete, final build | Week 4 end (~Mar 18) | Pending |
| App Store submission | Week 5 start (~Mar 19) | Pending |
| **Projected launch** | **Week 5–6 (~Mar 25–Apr 1)** | Pending |

---

## Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| App Store rejection (health claims) | +1–2 weeks | Medium | Review Apple health app guidelines; avoid diagnostic language |
| Legal review delays | +1–2 weeks | Medium | Engage attorney early; use templates as starting point |
| HIPAA compliance requirement | +2–4 weeks | Low–Medium | Current CloudKit setup is not HIPAA-certified; evaluate if client-side encryption suffices or if a HIPAA backend (e.g., AWS HIPAA) is needed |
| IAP product review delay | +2–3 days | Low | Submit IAP products before app submission |
| BLE hardware availability for beta | +1 week | Low | Ensure sufficient test devices for beta testers; leverage demo mode |
| Critical bugs found in beta | +1–2 weeks | Medium | Prioritize BLE reconnection and CloudKit failure recovery |

---

## Post-Launch Roadmap (from existing docs)

| Version | Target | Features |
|---------|--------|----------|
| v1.1 | Q2 2026 | PDF export, localization (Spanish, French, German), enhanced analytics |
| v1.2 | Q3 2026 | Additional language support, practice management enhancements |
| v1.3 | Q4 2026 | Advanced reporting, expanded device support |
