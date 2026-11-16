# Oralable App-Service Contract

**Canonical machine-readable source:** `cursor_oralable/contracts/oralable_app_services_v1.json`  
**Shared Swift constants:** `OralableCore/Sources/OralableCore/CloudKit/OralableAppServiceContract.swift`

This contract aligns local Xcode settings, StoreKit test fixtures, CloudKit code, entitlement declarations, App Store drafts, and release guidance. It **does not** create, modify, or prove configuration in Apple Developer, App Store Connect, CloudKit Console, or HealthKit. Those portal actions remain explicit manual release gates.

## Canonical app identities

| App | Bundle ID | Current release status |
|---|---|---|
| Oralable | `com.jacdental.oralable` | Patient application, pre-release |
| Oralable for Professionals | `com.jacdental.oralable.professionals` | Deferred Phase 1+ application; not authorized for App Store submission |

The consumer test bundles use the consumer identifier with `.tests` and `.uitests` suffixes. The professional test bundles use the professional identifier with the same suffixes.

## StoreKit identifiers

| App | Tier | Monthly | Yearly | Portal status |
|---|---|---|---|---|
| Oralable | Premium | `com.jacdental.oralable.premium.monthly` | `com.jacdental.oralable.premium.yearly` | Not verified in App Store Connect |
| Oralable for Professionals | Professional | `com.jacdental.oralable.professional.monthly` | `com.jacdental.oralable.professional.yearly` | Deferred, not verified |
| Oralable for Professionals | Practice | `com.jacdental.oralable.practice.monthly` | `com.jacdental.oralable.practice.yearly` | Deferred, not verified |

Local `.storekit` files are test fixtures, not evidence that a product is registered, approved, or for sale. Keep the consumer subscription UI and any App Store subscription claim hidden until the consumer products are verified in App Store Connect. Do not expose the professional products while the professional app is deferred.

## CloudKit schema and migration

Both targets refer to `iCloud.com.jacdental.oralable.shared` and use the public database when sharing is enabled. The production schema is **not verified or deployed**.

The three record types are `ShareInvitation`, `SharedPatientData`, and `HealthDataRecord`. Field names, types, and required queryable fields are in the versioned JSON contract. `professionalID` and `professionalName` are canonical. The code writes and reads legacy `dentistID` / `dentistName` aliases only as a migration bridge:

1. Writers set canonical and legacy aliases.
2. Readers prefer the canonical value and fall back to the legacy value.
3. Remove legacy aliases only after production schema deployment, existing-record migration, two-app validation, and a new contract version.

Never deploy CloudKit schema changes or relax database permissions from this repository alone. Review the proposed schema in Development, validate on physical devices, review security roles, and make the production deployment manually in CloudKit Console.

## Supported HealthKit scope

After a user grants authorization, the consumer application can read and write **heart-rate** and **oxygen-saturation** quantity samples. Values are downsampled to at most one sample per five seconds before writing. It does not write sleep stages or HRV, and it must not claim diagnostic, treatment, or clinical-validation capability.

## Claims and release scope

The consumer app’s pre-release copy may claim Bluetooth connection to Oralable hardware, local sensor display/CSV export, optional authorized Apple Health heart-rate and oxygen-saturation export when source samples are available, and wellness/informational intent.

Until all service gates are completed, it must not claim that professional sharing, production CloudKit synchronization, subscriptions for purchase, sleep-stage measurement, medical monitoring, diagnosis, treatment benefit, HIPAA/GDPR compliance, end-to-end encryption, or regulatory certification is available.

The professional application has no approved App Store listing or public product, subscription, remote-monitoring, practice-management, clinical, privacy-compliance, or treatment-outcome claim while it remains deferred.

## Change control

An identifier, schema, or claim change requires all of the following before release consideration:

1. Update and version the JSON contract.
2. Update the shared Swift constants and all affected local fixtures.
3. Run `python3 cursor_oralable/scripts/verify_app_service_contract.py --strict` and the relevant Swift tests.
4. Review App Store copy against the current feature flags and model/provenance gates.
5. Perform the separate manual Apple Developer, App Store Connect, CloudKit Console, and hardware-validation review.
