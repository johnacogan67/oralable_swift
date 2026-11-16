# App Store Connect In-App Purchase Gate

**Status:** No App Store Connect product or paid-plan availability is verified by this repository. The local `.storekit` files are simulator/test fixtures only.

**Canonical source:** [APP_SERVICE_CONTRACT.md](./APP_SERVICE_CONTRACT.md) and `cursor_oralable/contracts/oralable_app_services_v1.json`

## Canonical product registry

| App | Subscription group | Product | Identifier | Local fixture | Current release status |
|---|---|---|---|---|---|
| Oralable | Oralable Premium | Premium Monthly | `com.jacdental.oralable.premium.monthly` | `Configuration.storekit` | Not verified in App Store Connect |
| Oralable | Oralable Premium | Premium Yearly | `com.jacdental.oralable.premium.yearly` | `Configuration.storekit` | Not verified in App Store Connect |
| Oralable for Professionals | Oralable for Professionals | Professional Monthly | `com.jacdental.oralable.professional.monthly` | `ProfessionalConfiguration.storekit` | Deferred; not verified |
| Oralable for Professionals | Oralable for Professionals | Professional Yearly | `com.jacdental.oralable.professional.yearly` | `ProfessionalConfiguration.storekit` | Deferred; not verified |
| Oralable for Professionals | Oralable for Professionals | Practice Monthly | `com.jacdental.oralable.practice.monthly` | `ProfessionalConfiguration.storekit` | Deferred; not verified |
| Oralable for Professionals | Oralable for Professionals | Practice Yearly | `com.jacdental.oralable.practice.yearly` | `ProfessionalConfiguration.storekit` | Deferred; not verified |

The consumer bundle identifier is `com.jacdental.oralable`. The deferred professional bundle identifier is `com.jacdental.oralable.professionals`. Do not create a variant with `.dentist` or add extra identifier segments; Apple product IDs cannot be changed after creation.

## Consumer-product activation sequence

Perform this sequence only after the product owner approves paid consumer features and the release copy matches what the signed build exposes.

1. Check the identifiers with `python3 cursor_oralable/scripts/verify_app_service_contract.py --strict`.
2. Confirm the signed candidate uses the consumer bundle ID and no visible screen claims a plan or price before its App Store Connect state is ready.
3. Have an authorized App Store Connect user manually create the **Oralable Premium** subscription group and exactly the two consumer product identifiers shown above.
4. Define pricing, territories, availability, trial/offers, localization, tax, banking, and legal terms in App Store Connect. Values in old planning documents are not approved price claims.
5. Test purchases, restores, entitlement changes, failures, and cancellation in Sandbox/TestFlight with product IDs that match the candidate build.
6. Complete the App Privacy and review-information workflow, submit products as required, and retain the proof of approval/state.
7. Only then enable the consumer subscription UI and make a matching public claim.

## Professional products are not an activation task

The four professional identifiers are retained in local code and test configuration to prevent identifier drift. They are **not authorization** to create a professional listing, activate products, show pricing, or imply a professional service is available. Do not action those product rows until the professional release gates in `DENTIST_APP_STORE_METADATA.md` and `APP_SERVICE_CONTRACT.md` are complete and the product owner authorizes work.

## Local fixture use

In Xcode, choose the matching test fixture only for local StoreKit testing:

- Consumer target: `Configuration.storekit`
- Professional target: `OralableForProfessionals/ProfessionalConfiguration.storekit`

A fixture can simulate local products even when App Store Connect has no corresponding product. Never use a local fixture as review evidence or a public availability claim.

## Change control

A product-ID, subscription-group, price, or entitlement change requires an explicit contract update, a local fixture update, a code update, a verifier pass, and manual App Store Connect review. Do not use source-only changes to imply a portal state change.
