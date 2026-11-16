# Oralable Release Readiness Checklist

**Current release scope:** Consumer/patient app only.
**Professional app:** Deferred to Phase 1+; not authorized for App Store submission.
**Read this first:** [APP_SERVICE_CONTRACT.md](./APP_SERVICE_CONTRACT.md)

This is a release-gate checklist, not a percentage-complete estimate. A checked local source item is not evidence that a portal configuration, subscription, CloudKit deployment, security control, claim, or hardware behavior is ready for release.

## Identity and build gate

- [x] Consumer target uses `com.jacdental.oralable` in Debug and Release settings.
- [x] Local test bundles use the canonical consumer bundle-ID family.
- [x] Professional target uses `com.jacdental.oralable.professionals` and is explicitly deferred.
- [ ] Build and archive the exact consumer release candidate on a clean checkout.
- [ ] Confirm signing/provisioning for the consumer bundle ID and each enabled capability in Apple Developer.
- [ ] Run the iOS workspace test/build matrix and retain the archive, test, and artifact evidence.

## Claim and feature-scope gate

The candidate build, screenshots, App Store metadata, support material, privacy material, and review notes must make only these consumer claims: Bluetooth connection to Oralable hardware, local sensor display/CSV export, optional authorized Apple Health heart-rate/oxygen-saturation export when source samples exist, and wellness/informational intent.

- [ ] Inspect the signed candidate’s feature flags; professional sharing, subscriptions, and unvalidated/advanced claims must remain hidden unless their independent gates are completed.
- [ ] Verify the model/provenance release gate. Do not route a stub or unreviewed model into a production feature.
- [ ] Verify Apple Health consent and supported types on physical hardware. Do not claim sleep-stage, HRV, diagnostic, treatment, or clinical functionality.
- [ ] Review all user-facing copy for unsupported claims including remote monitoring, professional sharing, production sync, purchase availability, encryption, HIPAA/GDPR, or regulatory certification.

## CloudKit gate — blocks sharing claims and professional workflow

- [x] Local source references the canonical `iCloud.com.jacdental.oralable.shared` container and versioned schema contract.
- [x] Local code uses canonical `professionalID` fields with `dentistID` migration aliases.
- [ ] Review the schema in CloudKit Development Public Database.
- [ ] Validate consent, redemption, revocation, expiration, account deletion, retention, and alias migration with physical devices and test accounts.
- [ ] Review security roles; query predicates are not access control.
- [ ] Review and deploy the schema to CloudKit Production manually.
- [ ] Verify the release candidates against Production and retain evidence.
- [ ] Obtain legal/privacy approval before enabling `showCloudKitShare` or saying sharing/synchronization is available.

## App Store Connect IAP gate — blocks subscription claims

- [x] The local fixture and both subscription managers use the canonical six-product registry.
- [ ] Product owner authorizes paid consumer functionality and final pricing/terms.
- [ ] An authorized App Store Connect user creates and validates the two consumer products exactly as documented in `APP_STORE_CONNECT_IAP_SETUP.md`.
- [ ] Test Sandbox/TestFlight purchase, restore, renewal/cancellation, and unavailable-product behavior.
- [ ] Submit/approve the products as required and record the final status.
- [ ] Enable the subscription UI and associated public copy only after the preceding evidence is complete.

The professional product rows are not a release task while the professional app is deferred.

## App Store submission gate

- [ ] Confirm the signed candidate matches [APP_STORE_METADATA.md](./APP_STORE_METADATA.md); update it with only independently verified facts.
- [ ] Capture real screenshots from the candidate build; no wireframes, placeholders, hidden features, or fabricated service demonstrations.
- [ ] Publish and review the final privacy policy, terms, account-deletion path, support URL, and App Privacy questionnaire.
- [ ] Complete age rating, export-compliance questions, reviewer instructions, accessibility review, and support escalation process.
- [ ] Complete TestFlight/hardware validation appropriate to the final enabled features.
- [ ] Product owner signs off on the final build, claims, scope, and go/no-go decision.

## Deferred professional-app gate

Do not start an App Store submission, activate StoreKit products, or publish professional claims until every precondition in [DENTIST_APP_STORE_METADATA.md](./DENTIST_APP_STORE_METADATA.md) is met and the product owner authorizes a distinct scope.

## Required local verification

Run before a release-review meeting:

```sh
python3 ../cursor_oralable/scripts/verify_app_service_contract.py --strict
```

Then run the documented workspace CI/build checks. The local verifier confirms source-controlled consistency only; it cannot verify Apple portal configuration or physical-device behavior.
