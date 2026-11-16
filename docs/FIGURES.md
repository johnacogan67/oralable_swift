# oralable_swift figures index

**Master inventory:** [cursor_oralable/docs/FIGURES.md](../../cursor_oralable/docs/FIGURES.md)

Repo-local assets: [`figures/`](./figures/). Screen flows use Mermaid in [MOBILE_APP_FLOWS.md](./MOBILE_APP_FLOWS.md). Use `FIG-IOS-*` for UI mocks/screenshots.

## Maintenance

1. Add a row here **and** on the master hub for shared product visuals.
2. Copy [`figures/_placeholder.svg`](./figures/_placeholder.svg) → `FIG-IOS-NNN-slug.svg`.
3. Wireframes are **draft** until replaced by a device screenshot. Keep the same filename.

## Inventory — `FIG-IOS-*`

| ID | Title | Path | Status | Owning doc(s) | Notes |
|----|-------|------|--------|---------------|-------|
| FIG-IOS-001 | Phase 0 Vitals home | [figures/FIG-IOS-001-vitals-home-mock.svg](./figures/FIG-IOS-001-vitals-home-mock.svg) | draft wireframe | MOBILE_APP_FLOWS | App 4.3.3 · `DashboardView` |
| FIG-IOS-002 | Placement picker | [figures/FIG-IOS-002-placement-picker.svg](./figures/FIG-IOS-002-placement-picker.svg) | draft wireframe | MOBILE_APP_FLOWS | Pre-connect `VitalsPlacementPickerSection` |
| FIG-IOS-003 | iOS night report / hypnogram | [figures/FIG-IOS-003-night-report-ios.svg](./figures/FIG-IOS-003-night-report-ios.svg) | draft wireframe | MOBILE_APP_FLOWS, OVERNIGHT_NIGHT_REPORT | Adapts FIG-CO-025 layout · `StateHypnogramView` |
| FIG-IOS-004 | BLE connect flow | [figures/FIG-IOS-004-ble-connect-flow.svg](./figures/FIG-IOS-004-ble-connect-flow.svg) | draft wireframe | MOBILE_APP_FLOWS | Scan → CCC → Ready |
| FIG-IOS-005 | Dentist app deferred | [figures/FIG-IOS-005-dentist-app-dark.svg](./figures/FIG-IOS-005-dentist-app-dark.svg) | draft wireframe | MOBILE_APP_FLOWS | Phase 1+ / dark |
| FIG-IOS-006 | Phase 0 session lifecycle | [figures/FIG-IOS-006-phase0-session-lifecycle.svg](./figures/FIG-IOS-006-phase0-session-lifecycle.svg) | draft | MOBILE_APP_FLOWS §2 | Mermaid is source |
| FIG-IOS-007 | BLE to UI stack | [figures/FIG-IOS-007-ble-to-ui-stack.svg](./figures/FIG-IOS-007-ble-to-ui-stack.svg) | draft | MOBILE_APP_FLOWS §2.5 / §8 | |
| FIG-IOS-008 | Automatic recording states | [figures/FIG-IOS-008-auto-recording-states.svg](./figures/FIG-IOS-008-auto-recording-states.svg) | draft | MOBILE_APP_FLOWS §2.4 | No Start button |
| FIG-IOS-009 | Patient app screen map | [figures/FIG-IOS-009-tab-screen-map.svg](./figures/FIG-IOS-009-tab-screen-map.svg) | draft wireframe | MOBILE_APP_FLOWS | Launch + four tabs + History drill-down |

**Working diagrams (Mermaid in-doc):** [MOBILE_APP_FLOWS.md §2](./MOBILE_APP_FLOWS.md#2-how-the-patient-app-works--phase-0) — session lifecycle, tabs, placement state, auto-record, BLE→UI.

*Last updated: 21 Sep 2026*
