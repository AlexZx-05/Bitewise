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

## Packaged-food and meal scanning (web prototype)

From Home, choose **Packaged food**, add clear front, nutrition, and ingredient
label photos, then tap **Extract label with AI**. The photos are sent to the
FoodScan backend and Groq for structured extraction; FoodScan does not save
the images. Review and correct every suggestion before submitting. The
backend validates confirmed values, performs deterministic serving-size
calculations and limited ingredient checks, and asks Groq to explain the
confirmed data in the context of the selected goal. Groq extraction and
explanations require `GROQ_API_KEY` in `backend/.env`. The local browser OCR
option remains available as a fallback. Missing values are never estimated.

The API saves confirmed label details and findings for a local development
profile. Ingredient/allergen matching is limited and is not an allergen-free
guarantee, health rating, or medical advice. Always check the package.

For **Home-cooked meal**, take a photo, review the AI-identified foods, confirm
ingredients, cooking methods, and portion weights, then search and choose a
matching USDA FoodData Central record for each item. FoodScan calculates
portion nutrition from those selected records and asks Groq for a concise
goal-context explanation. It does not claim that database records are an exact
match for a homemade recipe. This requires `GROQ_API_KEY` and `USDA_API_KEY`
in `backend/.env`.

Scanner diary saving and native Android/iOS camera support are not implemented.

For a local browser, keep the API and PostgreSQL running, then use
`flutter run -d chrome`. The scanner API endpoints are documented at
`http://127.0.0.1:8000/docs`.

Run mobile tests and static analysis with:

```bash
flutter test
flutter analyze
```
