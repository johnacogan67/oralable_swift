# Oralable iOS app docs

**Repo:** `oralable_swift` — patient app (**Oralable**) and professional app (**Oralable for Dentists**).  
**Shared math / BLE parse / EDF / Core ML:** [`OralableCore`](../../OralableCore/docs/README.md)  
**Versions (do not invent):** [`cursor_oralable/docs/data_room/VERSION_ALIGNMENT.md`](../../cursor_oralable/docs/data_room/VERSION_ALIGNMENT.md)  
**Agent topics:** `ios-patient` · `ios-dentist` — starters in [`cursor_oralable/AGENTS.md`](../../cursor_oralable/AGENTS.md) · map [`WORKSPACE_TOPICS.md`](../../cursor_oralable/docs/WORKSPACE_TOPICS.md)

## Start here

| Doc | Role |
|-----|------|
| [MOBILE_APP_FLOWS.md](./MOBILE_APP_FLOWS.md) | Phase 0 vitals flows · §2 working diagrams · Protocol A Setup · overnight |
| [FIGURES.md](./FIGURES.md) | `FIG-IOS-*` inventory |
| `OralableApp/docs/WEBSITE.md` | Website / hardware mirror notes |

## Phase 0 (Ed / Pedro)

- Patient app only — no dentist CloudKit share.  
- Firmware gate: hard min **1.0.63** · recommend **1.0.84**.  
- Research Kit / Dual A: see `cursor_oralable/docs/data_room/clinical/`.

## Out of scope here

Firmware GATT lives in `oralable_nrf`. Mac Python gold lives in `cursor_oralable`. Do not invent SpO₂ defaults Mac would leave missing.
