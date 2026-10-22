# Mosque Pro (مسجد وأكثر)

A separate copy of Near Mosque (MFvision/nearest-mosque at 630791a, 2026-10-22) for the upgraded app (English name Mosque Pro, Arabic «مسجد وأكثر»):
the TV prayer screen, Clean network, and Ayah and Hadith of the day. Near Mosque is never changed from here.

| | Near Mosque | Mosque Pro |
|---|---|---|
| Apple bundle ID | sa.zood.nearmosque | sa.zood.mosquepro |
| Android application ID | com.AVA.nearmosque | com.AVA.mosquepro |
| Desktop installer | near-mosque, its own upgrade UUID | mosque-pro, a new upgrade UUID |
| Website domain | nearmosque.net | none yet (no CNAME) |

Kotlin and Swift package names (`sa.zood.nearmosque.*`) are internal and stay as they are.

Every publishing workflow (TestFlight, App Store, Google Play, desktop release, store assets, content packs) is
parked in `.github/workflows-disabled/` and does not run. Only `ci.yml` (build and tests) is active. Move a
workflow back only after Mohammed approves publishing.
