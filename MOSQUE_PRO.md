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

TestFlight is on (Mohammed asked for it on 2026-10-22): `testflight.yml` uploads the iPhone, iPad, Mac, Apple TV
and Vision Pro apps on every push to main that changes them. The internal group **Mosque Pro Team** gets every
build automatically; the external group **Mosque Pro Testers** has a public link and gets each build after Apple's
Beta App Review. It needs the three App Store Connect secrets (docs/07-testflight.md) and the app record for
sa.zood.mosquepro.

Every other publishing workflow (App Store review, Google Play, desktop release, store assets, content packs) is
parked in `.github/workflows-disabled/` and does not run. Move one back only after Mohammed approves publishing.
