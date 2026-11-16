# oralable.com source

**App working diagrams:** [MOBILE_APP_FLOWS.md §2](../../docs/MOBILE_APP_FLOWS.md#2-how-the-patient-app-works--phase-0)

**Canonical website repo:** [johnacogan67/oralable-web](https://github.com/johnacogan67/oralable-web) → Netlify → **https://oralable.com**

This `docs/` folder in `oralable_swift` is a **frozen / local copy** for app-doc cross-links. **Do not** point Netlify at `oralable_swift` for the live site. Edit and deploy from **`oralable-web`**.

**Brand (public):** Official lockup `images/oralable_logo_lockup.png` · **Oralable®** · **Word of Mouth™** · footer trademark line (JAC Dental Solutions Limited). Do not spray ® on every body mention.  
**App/docs figures:** [../../docs/FIGURES.md](../../docs/FIGURES.md) · master [cursor_oralable/docs/FIGURES.md](../../../cursor_oralable/docs/FIGURES.md)

## Netlify (oralable-web)

1. Site → Project configuration → Build & deploy → **Link repository** → `johnacogan67/oralable-web`, branch `main`  
2. **Base directory:** empty  
3. **Build command:** empty  
4. **Publish directory:** `.`  
5. Deploy → confirm `https://oralable.com/images/oralable_logo_lockup.png` returns **200**

## Hardware ↔ BOM map (do not invent)

| Generation | BOM | PCB | Module (U5) | Battery | Firmware |
|------------|-----|-----|-------------|---------|----------|
| **Gen 2** (current · bring-up · kits not shipped) | `PCB00003-TGM-BOM-REV9` | **REV11** | Kaga **ES4L15BA1** · nRF54L15 | **LP270829** 35 mAh | **2.0.x** target (not flashed) · app **4.3.3** (build **5**) |
| **Gen 1** (frozen) | `PCB00003-TGM-BOM-REV8` | **REV10** | Kaga **ES2832AA2** · nRF52832 | CG-320B ~15 mAh | **1.0.85** frozen. Source of the port. |

- **Phase 0 / Phase 1+** = software on **Gen 2** (BOM REV9 / REV11). Gen 1 is frozen.
- Charge: Oralable charging case (LTC4124 / LTC6990) — **not** WPC Qi; no magnets on the charger.
- Truth docs: `cursor_oralable/docs/VITALS_PHASE_GEN1_GEN2.md`, `GEN1_GEN2_MIGRATION.md`, `PRODUCT_ROADMAP.md`, `IP_NORTH_STAR.md`.
- **Strategy:** Stage A wellness wearable → Stage B medical (later). Ed/Pedro = patient app only.
- **Internal cost/timeline (do not put € ranges on public pages):** `cursor_oralable/docs/data_room/COST_AND_TIMELINE.md`

## Keep current (when facts change)

1. Update pages in **`oralable-web`** (specifications, support, about, etc.) and push `main`.  
2. Optionally mirror the same HTML into this `docs/` folder if you still want a local copy.  
3. Alternate draft trees (not live Netlify source): `../oralable-website/`, `../docs-v2/`.

**Kits (14 Oct 2026):** Gen 2 · BOM REV9 · PCB REV11 · ES4L15BA1 · cell LP270829 · firmware **2.0.x** not flashed · app **4.3.3** (build **5**) · **not shipped**. First install is `flash_and_rtt.sh`, same as Gen 1.  
**Public copy:** kits not yet shipped; firmware in bring-up; no “Beacon trials underway”; no diagnostics / FDA-CE claims.  
**Module:** Kaga ES4L15BA1 (nRF54L15). Gen 1 ES2832AA2 is frozen.
