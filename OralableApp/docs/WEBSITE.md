# oralable.com source

**Canonical website repo:** [johnacogan67/oralable-web](https://github.com/johnacogan67/oralable-web) → Netlify → **https://oralable.com**

This `docs/` folder in `oralable_swift` is a **frozen / local copy** for app-doc cross-links. **Do not** point Netlify at `oralable_swift` for the live site. Edit and deploy from **`oralable-web`**.

**Brand (public):** Official lockup `images/oralable_logo_lockup.png` · **Oralable®** · **Word of Mouth™** · footer trademark line (JAC Dental Solutions Limited). Do not spray ® on every body mention.

## Netlify (oralable-web)

1. Site → Project configuration → Build & deploy → **Link repository** → `johnacogan67/oralable-web`, branch `main`  
2. **Base directory:** empty  
3. **Build command:** empty  
4. **Publish directory:** `.`  
5. Deploy → confirm `https://oralable.com/images/oralable_logo_lockup.png` returns **200**

## Hardware ↔ BOM map (do not invent)

| Generation | BOM | PCB | Module (U5) | Battery | Firmware |
|------------|-----|-----|-------------|---------|----------|
| **Gen1** (shipping / pilot) | `PCB00003-TGM-BOM-REV8` | **REV10** pilot (REV8 prod data) | Kaga **ES2832AA2** · nRF52832 | CG-320B ~15 mAh | **1.0.70** ship (min 1.0.63) · app **4.3.3** |
| **Gen2** (upcoming) | `PCB00003-TGM-BOM-REV9` | **REV11** | Kaga **ES4L15BA1** · nRF54L15 | LP260820 ~30 mAh | **2.0.x** target |

- **Phase 0 / Phase 1+** = software on **Gen1** (same BOM REV8 / REV10). Phases do **not** change the BOM.
- Charge: Oralable magnetic case (LTC4124 / LTC6990) — **not** WPC Qi.
- Truth docs: `cursor_oralable/docs/VITALS_PHASE_GEN1_GEN2.md`, `GEN1_GEN2_MIGRATION.md`, `PRODUCT_ROADMAP.md`, `IP_NORTH_STAR.md`.
- **Strategy:** Stage A wellness wearable → Stage B medical (later). Ed/Pedro = patient app only.
- **Internal cost/timeline (do not put € ranges on public pages):** `cursor_oralable/docs/data_room/COST_AND_TIMELINE.md`

## Keep current (when facts change)

1. Update pages in **`oralable-web`** (specifications, support, about, etc.) and push `main`.  
2. Optionally mirror the same HTML into this `docs/` folder if you still want a local copy.  
3. Alternate draft trees (not live Netlify source): `../oralable-website/`, `../docs-v2/`.

**Pilot kits (July 2026):** Gen1 · BOM REV8 · PCB REV10 · ES2832AA2 · firmware **1.0.70** · app **4.3.3** (STAT blink = charging; Automatic dock).  
**Module:** Kaga ES2832AA2 (nRF52832), not Taiyo Yuden EYSHSNZWZ.
