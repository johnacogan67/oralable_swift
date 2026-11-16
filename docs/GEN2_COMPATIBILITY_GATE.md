# Gen2 iOS Compatibility Gate

**Status:** Gen2 firmware `2.0.x` is a non-release hardware candidate. It is **not production compatible** merely because the iOS version parser accepts a major version greater than one or the shared TGM constants compile. On 16 Nov 2026 John authorized a release-candidate process. The app is still not production compatible.

This guide supplies the evidence required for `oralable_nrf` gate **G2-P6**. It does not authorize programming, a product release, public support, a marketing claim, or a change to the consumer app’s release scope.

## Preconditions

Before an iOS session is scheduled, the firmware program owner must record and review G2-P2, G2-P3, and G2-P4: complete GATT/connection evidence, stream parity, and battery/charging behavior. The exact candidate must have a source revision, NCS/toolchain identity, firmware version, and immutable build fingerprint.

Use a signed iOS candidate identified by its commit/archive/build number. Record the physical iPhone model, iOS version, app build, device identifier handled according to the approved evidence process, firmware candidate fingerprint, and test date. Do not place participant data, raw health data, or account credentials in this document.

## Required compatibility observations

1. Confirm discovery identifies the candidate as the intended Oralable device without treating a generic BLE advertisement as product support.
2. Confirm the firmware version reads through the TGM version characteristic. `FirmwareGate.requiresGen2CompatibilityEvidence(_:)` must identify the `2.0.x` value as requiring this gate; it is a workflow signal, not approval.
3. Confirm connect, service discovery, required characteristic discovery, notification subscription, controlled disconnect, and reconnect.
4. Capture and parse representative PPG, accelerometer, status, battery-usage, and temperature data only after the firmware G2-P2/G2-P3 evidence establishes that the expected characteristics exist. Compare packet/field handling to `cursor_oralable/contracts/tgm_gatt_v1.json`.
5. Exercise the candidate’s documented placement/state paths and record any missing Gen1 behavior as a limitation. Do not assume Gen1 automatic dock, battery, LED, or charge thresholds apply to the Gen2 cell.
6. Run a defined-duration monitored soak appropriate to the risk under review. Record disconnects, reconnects, notification failures, data gaps, battery/charging transitions, application failures, and recovery steps.
7. Re-run the app’s ordinary Gen1 validation separately. A Gen2 result must not regress or replace the Gen1 release evidence.

## Pass record

A future evidence record must include the candidate firmware/app fingerprints, all required observations, pass/fail criteria, exception/limitation list, raw-log storage references, a tester, reviewer, date, and decision. The firmware owner then updates the reviewed Gen2 program evidence outside this source-controlled template.

Until that record exists and the product owner authorizes a separate release-candidate process, app copy, screenshots, support material, and compatibility matrices must describe Gen2 only as a gated, future, or research/bring-up track—not as a currently supported device.
