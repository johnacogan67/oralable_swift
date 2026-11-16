# Oralable for Professionals — Deferred App Store Record

**Status:** The professional application is deferred to Phase 1+ and is **not authorized for App Store submission**. This document intentionally does not provide marketing copy, screenshots, pricing, review instructions, a demo account, or claims for publication.

## Canonical identity

| Field | Value |
|---|---|
| Working display name | Oralable for Professionals |
| Bundle ID | `com.jacdental.oralable.professionals` |
| Source target | `OralableForProfessionals` |
| StoreKit fixture group | Oralable for Professionals |
| Release status | Deferred; no public listing or product activation |

The historical name “Oralable for Dentists” and the retired bundle/product IDs are not submission identifiers.

## Claims prohibited while deferred

Do not make a public or App Store claim that this app currently provides patient sharing, remote monitoring, real-time data, clinician analytics, data export for records, practice management, multi-provider access, treatment-effectiveness tracking, API access, white-label reports, HIPAA/GDPR compliance, encryption guarantees, professional eligibility, or paid plans.

The local implementation and StoreKit configuration are development artifacts. They do not demonstrate that any professional workflow, CloudKit schema, subscription, privacy process, support service, or clinical use case is ready or available.

## Preconditions before new metadata is drafted

Create a new metadata draft only after all of the following have evidence:

1. The patient-to-professional CloudKit schema is deployed and security-reviewed, with canonical `professionalID` fields and tested migration aliases.
2. The consumer app’s opt-in professional-sharing path and the professional app work together on physical devices using release candidates.
3. Identity, consent, deletion, retention, access control, and support workflows have legal and privacy review appropriate to the intended jurisdictions and users.
4. The professional product’s claims, analytical methods, model provenance, and user-facing limitations are validated for the proposed audience.
5. Any relevant App Store Connect app record, subscription group, products, screenshots, test account, reviewer path, and support URLs have been created and independently verified.
6. The product owner explicitly authorizes the professional app’s submission scope.

When these gates are complete, begin from [APP_SERVICE_CONTRACT.md](./APP_SERVICE_CONTRACT.md), increment the versioned workspace contract, and write a new submission-specific document. Do not reactivate this historical draft by changing its status alone.
