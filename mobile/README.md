# FoodScan mobile app

## Local development

Start the API and PostgreSQL using the instructions in `../backend/README.md`.
Then, from this directory, run:

```bash
flutter pub get
flutter run -d chrome
```

The default web API URL is `http://127.0.0.1:8000`. Override it with
`--dart-define=FOODSCAN_API_BASE_URL=http://YOUR_COMPUTER_LAN_IP:8000` when
running on a physical phone. Android emulators default to `http://10.0.2.2:8000`.

On first launch, select a wellness goal. FoodScan saves it through the profile
API and reloads it from the backend on later launches. The profile API uses a
single unauthenticated local development profile; do not expose it to real
users or deploy it until authentication and per-user ownership are implemented.

The scanner and diary are interface entry points only; food scanning and diary
records are planned for later milestones.

Run mobile tests and static analysis with:

```bash
flutter test
flutter analyze
```
