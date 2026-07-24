# oralable.com source

**Live site source:** this `docs/` folder (`CNAME` → `oralable.com`). Deploy via GitHub Pages (or Netlify publish `.` from this folder).

**Alternate trees (keep facts in sync if still used):**
- `../oralable-website/` — Netlify-style marketing draft
- `../docs-v2/` — alternate layout draft

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

## Keep current

When Gen1 firmware, hardware module, charger story, pilot phase, or Stage A/B messaging changes:

1. Update `specifications.html` Hardware identity + Gen2 table (BOM/PCB/module/FW).
2. Update `support.html` / `user-guide.html` charging & placement FAQs.
3. Update `about.html` **Hardware ↔ BOM map**, roadmap eras, and Stage A→B / patent wording (no medical claims; no euro budgets).
4. Update early-access copy (`beta.txt` / `beta.html`) — no stale “Launching January 2026”.
5. Mirror the same facts in `../oralable-website/` and `../docs-v2/` if those trees are published anywhere.
6. Sync internal docs via `PRODUCT_ROADMAP.md` / `COST_AND_TIMELINE.md`.
7. Commit + deploy so https://oralable.com reflects the change.

**Pilot kits (July 2026):** Gen1 · BOM REV8 · PCB REV10 · ES2832AA2 · firmware **1.0.70** · app **4.3.3** (STAT blink = charging; Automatic dock).
**Module:** Kaga ES2832AA2 (nRF52832), not Taiyo Yuden EYSHSNZWZ.
