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
Analysis also provides a practical alternative based on the selected goal and
confirmed details. It is general guidance; verify any alternative's own label
before comparing its nutrition.

For **Home-cooked meal**, take a photo, review the AI-identified foods, confirm
ingredients, cooking methods, and portion weights, then search and choose a
matching USDA FoodData Central record for each item. FoodScan calculates
portion nutrition from those selected records and asks Groq for a concise
goal-context explanation and a practical alternative for the selected goal.
Alternative suggestions are general guidance, not medical advice or verified
nutrition for the proposed swap. It does not claim that database records are an
exact match for a homemade recipe. This requires `GROQ_API_KEY` and
`USDA_API_KEY` in `backend/.env`.

Both analysis results may also include a related packaged product from Open
Food Facts, with its package photo and per-100 g calories, protein,
carbohydrates, and fat. Listings are community-contributed and may be
incomplete or outdated; compare the package label yourself. Search terms are
sent to Open Food Facts. A product card is omitted when no listing includes
both a photo and all four nutrition values; the text recommendation remains.

On first launch, a branded welcome screen introduces food-label scanning, meal
analysis, and food insights. Onboarding asks the user to select a goal, then
offers optional age, gender, height, and weight profile details before opening
the dashboard. The selected goal is saved together with any details entered
when the user continues or skips the details step. Existing profiles with a
saved goal go straight to the dashboard after the branded intro. Personal
details are optional and do not currently change nutrition calculations or
recommendations.

Scanner diary saving and native Android/iOS camera support are not implemented.

For a local browser, keep the API and PostgreSQL running, then use
`flutter run -d chrome`. The scanner API endpoints are documented at
`http://127.0.0.1:8000/docs`.

Run mobile tests and static analysis with:

```bash
flutter test
flutter analyze
```
