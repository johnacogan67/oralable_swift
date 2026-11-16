# CloudKit Production Deployment Gate

**Status:** Production schema is **not verified or deployed**. This guide is a manual deployment checklist; it does not establish that the CloudKit container exists, is configured, is secure, or is suitable for any particular use.

**Canonical source:** `cursor_oralable/contracts/oralable_app_services_v1.json`
**Code constants:** `OralableCore/Sources/OralableCore/CloudKit/OralableAppServiceContract.swift`
**Related local contract:** [APP_SERVICE_CONTRACT.md](./APP_SERVICE_CONTRACT.md)

## Scope and release restriction

The local targets declare the shared container `iCloud.com.jacdental.oralable.shared` and the public database. The consumer feature flag `showCloudKitShare` is off in the pre-release configuration and the professional app is deferred. Do not represent CloudKit sharing or synchronization as available until all gates below are complete.

CloudKit’s production schema has durable consequences. This procedure requires a human with the appropriate Apple Developer access to review and deploy it in CloudKit Console. Do not treat source-controlled entitlements or passing local tests as a deployment.

## Canonical schema

Create or reconcile these record types in the **Development Public Database** before considering a production deployment. Field types and queryability must match the contract exactly.

### `ShareInvitation`

| Field | Type | Queryable | Purpose |
|---|---|---:|---|
| `patientID` | String | Yes | Opaque consumer account identifier |
| `shareCode` | String | Yes | Time-limited redemption code |
| `createdDate` | Date/Time | No | Creation timestamp |
| `expiryDate` | Date/Time | Yes | Expiration timestamp |
| `isActive` | Int64 | Yes | `1` is redeemable/active; `0` is inactive |
| `professionalID` | String | No | Canonical recipient identifier after redemption |
| `dentistID` | String | No | Legacy migration alias only |

### `SharedPatientData`

| Field | Type | Queryable | Purpose |
|---|---|---:|---|
| `patientID` | String | Yes | Opaque consumer account identifier |
| `professionalID` | String | Yes | Canonical recipient identifier |
| `shareCode` | String | Yes | Invitation-link value |
| `accessGrantedDate` | Date/Time | No | Connection timestamp |
| `isActive` | Int64 | Yes | `1` active; `0` revoked/inactive |
| `professionalName` | String | No | Optional display name |
| `patientName` | String | No | Optional consumer-provided display name |
| `lastDataUpdate` | Date/Time | No | Optional latest data timestamp |
| `dentistID` | String | Yes | Legacy migration alias only |
| `dentistName` | String | No | Legacy migration alias only |

### `HealthDataRecord`

| Field | Type | Queryable | Purpose |
|---|---|---:|---|
| `patientID` | String | Yes | Opaque consumer account identifier |
| `recordingDate` | Date/Time | Yes | Session/day timestamp |
| `sessionDuration` | Double | No | Seconds |
| `bruxismEvents` | Int64 | No | Locally calculated count; not a clinical diagnosis |
| `averageIntensity` | Double | No | Locally calculated summary |
| `peakIntensity` | Double | No | Locally calculated summary |
| `heartRateData` | Bytes | No | JSON-encoded numeric array |
| `oxygenSaturation` | Bytes | No | JSON-encoded numeric array |
| `sensorDataCompressed` | Bytes | No | LZFSE-compressed JSON |
| `sensorDataUncompressedSize` | Int64 | No | Decompression guard |

Do not invent a field named `used` or `isRevoked`; the active state is always `isActive`.

## Migration behavior

`professionalID` and `professionalName` are canonical. The deployed code deliberately writes both those fields and the legacy `dentistID` / `dentistName` aliases. It reads canonical values first and falls back to aliases, and its queries match either identifier while the migration is active.

Do not delete legacy fields from a Development or Production schema until all of the following are documented: existing record migration, two-app physical-device validation, access-control review, data-retention/deletion behavior, and an updated contract version. The production schema must support both values during the bridge.

## Manual deployment sequence

1. Confirm the bundle IDs, entitlements, and container identifier against [APP_SERVICE_CONTRACT.md](./APP_SERVICE_CONTRACT.md).
2. In CloudKit Console, select `iCloud.com.jacdental.oralable.shared`; create it manually only if the organization has approved the identifier and ownership.
3. In the Development Public Database, create/reconcile the schema above and mark the listed fields queryable.
4. Design and review security roles and query access. The code’s predicates are not an authorization boundary. In particular, do not grant broad public read/write access just to make development queries succeed.
5. Exercise opt-in sharing, redemption, data read, revocation, expiration, account deletion, and legacy-field migration using actual test accounts and physical devices.
6. Record the reviewed schema diff, test evidence, responsible owner, date, and data-retention/privacy decision.
7. Have authorized personnel review the Development-to-Production diff in CloudKit Console and deploy it manually.
8. Validate the Production environment with release candidates before enabling `showCloudKitShare` or any professional-app release claim.

## Required evidence before enabling sharing

- `python3 cursor_oralable/scripts/verify_app_service_contract.py --strict` passes for local configuration.
- Consumer and professional app builds use the canonical bundle/container identifiers.
- CloudKit Console production schema, indexes, and security roles are reviewed and recorded.
- The migration aliases work with existing development data, then a retirement plan is approved.
- Consent, access revocation, account deletion, retention, support, privacy, and legal workflows have been tested and reviewed.
- A physical-device test confirms the entire opt-in share path, not merely local StoreKit/CloudKit fixtures.

Until then, the CloudKit entitlements and source code are preparatory configuration only.
