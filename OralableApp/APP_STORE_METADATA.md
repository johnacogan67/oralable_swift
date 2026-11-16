# App Store Metadata — Oralable

**Status:** Pre-submission working copy. It is not an App Store Connect record and must not be pasted into a submission until every release gate in [APP_SERVICE_CONTRACT.md](./APP_SERVICE_CONTRACT.md) and [LAUNCH_READINESS_CHECKLIST.md](./LAUNCH_READINESS_CHECKLIST.md) is complete.

**Pre-submission status:** Professional sharing is not available in the consumer pre-release build. Subscriptions are not available until the relevant App Store Connect product gate is complete.

## App information

| Field | Value |
|---|---|
| App name | Oralable |
| Bundle ID | `com.jacdental.oralable` |
| Primary category | Health & Fitness |
| Release scope | Consumer/patient application only |
| Professional companion | Deferred; do not claim it is available |

## Release claim boundary

### Permitted only when confirmed by the submission build

- Connects to Oralable hardware using Bluetooth.
- Displays locally collected sensor information and supports local CSV export.
- Can write supported heart-rate and oxygen-saturation samples to Apple Health after the user grants permission and only when source samples are available.
- Provides wellness and informational features; it does not diagnose, treat, or replace professional advice.

### Do not claim before the corresponding gate is complete

- Professional/dentist sharing, remote monitoring, CloudKit backup, synchronization, or a working share code.
- A subscription, premium plan, price, or purchase availability.
- Sleep-stage measurement, medical monitoring, diagnostic accuracy, bruxism detection, treatment efficacy, or clinical validation.
- HIPAA/GDPR compliance, end-to-end encryption, regulatory certification, or “secure” service claims that have not undergone legal and technical review.
- Compatibility with other devices or an iPad release unless that configuration is built and tested.

## Pre-submission description draft

### Promotional text (170 characters maximum)

Connect your Oralable device, review locally collected sensor information, and export CSV records. Optional Apple Health export is available with your permission.

### Description

Oralable works with the Oralable hardware device to help you review locally collected sensor information on your iPhone.

Use Bluetooth to connect your device, review available session information, and export local CSV files for your own records. When you choose to grant Apple Health permission and supported source samples are available, Oralable can write heart-rate and oxygen-saturation samples to Apple Health.

Oralable is designed for wellness and informational use. It is not a medical device and does not diagnose, treat, cure, or prevent a medical condition. Do not use it to make medical decisions. Seek advice from an appropriately qualified professional for health concerns.

### Suggested keywords

`oral wellness,bluetooth sensor,health export,csv,wellness device,heart rate,oxygen saturation`

Re-check character limits, keyword availability, and all claims in App Store Connect immediately before submission.

## Screenshot boundary

Use only captures from the actual signed candidate build. Screenshots may show:

1. Bluetooth device connection.
2. Locally displayed session/sensor information that is enabled in the candidate build.
3. Local CSV export.
4. Optional Apple Health permission/export only if it is exercised successfully with a test account.

Do not show or caption disabled professional sharing, CloudKit synchronization, subscriptions, advanced algorithms, diagnosis, sleep stages, external-device support, or placeholder/demo data as a consumer release feature.

## Apple Health disclosure check

The current `Info.plist` asks permission to read and write heart-rate and oxygen-saturation data. It explicitly does not write night states as sleep stages. The App Privacy questionnaire, support copy, screenshots, and review notes must describe the final build’s actual data collection, linkage, retention, and sharing behavior after legal review; this document is not a privacy policy.

## Review notes template — complete immediately before submission

Do not submit review notes containing a fabricated share code, demo account, StoreKit availability, portal configuration, or hardware path. Replace the following placeholders with independently tested facts:

- Hardware or simulator path available to the reviewer: `[complete after validation]`
- Account requirement: `[complete after validation]`
- Apple Health path and data types exercised: `[complete after validation]`
- Data deletion path: `[complete after validation]`
- Support contact with a monitored reply channel: `[complete after validation]`

## Submission gates

Before copying this draft into App Store Connect, record evidence that:

1. The signed release target uses `com.jacdental.oralable` and the feature flags match the screenshots and copy.
2. The current model/provenance release gate passes; no stub or unreviewed model is routed to a production feature.
3. Apple Health authorization and the permitted quantity types have been tested on physical hardware.
4. Privacy policy, terms, support URL, privacy questionnaire, and age rating have undergone review.
5. No service-dependent claim appears until the relevant Apple Developer, App Store Connect, CloudKit, hardware, and legal gate has been completed.

For service identifiers and scope, use [APP_SERVICE_CONTRACT.md](./APP_SERVICE_CONTRACT.md), not this prose document.
