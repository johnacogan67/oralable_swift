# TestFlight — Gen 2 patient app

**Who:** Ed and Pedro, first dentist nights. Patient app only.
**Device:** Gen 2 · PCB REV11 · LP270829 · firmware `2.0.6-gen2-nrfconnect`.
**App:** Oralable patient TestFlight. Write the build number you install on the sheet. The current source stamp is **4.3.3**.

This list does not make the app production-compatible. That claim waits on the record in [GEN2_COMPATIBILITY_GATE.md](./GEN2_COMPATIBILITY_GATE.md).

## Before you archive

Patient target only. Leave Oralable for Professionals off the TestFlight send.

In the build, these stay as follows:

- Vitals phase **on** (heart rate, SpO₂, battery, overnight hypnogram)
- Dual Protocol A **off**
- CloudKit share **off**
- Share with a professional **off**
- Subscriptions **off**

Settings, onboarding, and discovery name Gen 2. They do not name Gen 1 or firmware 1.0.85.

## On the phone

1. Pair the clip. The firmware string reads `2.0.x`.
2. Battery percent uses **3.30 V = 0%** and **4.20 V = 100%**. A cell near **4048 mV** shows about **83%**, not 59%. If the status characteristic already has a percent, the screen shows that percent.
3. Worn temple session, phone nearby. Heart rate is plausible. Write down how often SpO₂ is flagged. Run `scripts/check_ir_dc_scaling.py` on the infrared raw counts.
4. One night, phone nearby, at least **4 hours** worn. Six hours is the better figure night.
5. In the morning: **Share → Export night pack**. Keep the PDF and the flushed night CSV. The short continuous CSV is not the handoff file.
6. On the case-report form, write the firmware string the phone read and the app build. Do not write an apnea index.

## Still open after this list

- A reviewer signs the Gen 2 compatibility record.
- Five kits stay gated until each unit holds a short worn heart-rate and SpO₂ session without browning out.
- Over-the-air update (G2-P5) is not required for a bench-flashed loaner.
- The dentist CloudKit app stays off.
