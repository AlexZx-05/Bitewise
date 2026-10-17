# FoodScan API

## Local development

From the repository root, start PostgreSQL:

```bash
docker compose up -d db
```

In a second terminal:

```bash
cd backend
python -m venv .venv
source .venv/Scripts/activate
python -m pip install -r requirements.txt
cp .env.example .env
alembic upgrade head
python -m uvicorn app.main:app --reload
```

The default database credentials are for local development only. Do not use
them for a deployed environment. The `.env` file is ignored by Git.

The AI and food-data features need server-side API keys. Create a Groq API key
and a USDA FoodData Central key, then put them in `backend/.env`:

```dotenv
GROQ_API_KEY=your_groq_key
GROQ_MODEL=qwen/qwen3.8-27b
USDA_API_KEY=your_usda_key
```

Never put these keys in Flutter code, commit them, or share them in chat.
Restart the API after changing `.env`. Without the Groq key, vision extraction
and generated explanations return an explicit configuration error.
Without the USDA key, meal nutrition lookup returns an explicit configuration
error.

Open `http://127.0.0.1:8000/docs` for the interactive API docs and
`http://127.0.0.1:8000/health` for the health check.

The profile and scan endpoints currently operate on one local development
profile and are not authenticated. Add authentication and per-user ownership
before exposing profile or scan data to multiple users or deploying the API.
Supported wellness goals are `fat_loss`, `muscle_gain`, and `maintenance`;
this value does not prescribe calorie or medical targets.
First-run onboarding asks for optional age, gender, height, and weight. These
details are stored on the local profile but do not currently change nutrition
calculations or recommendations; users can skip them.

Packaged food follows this pipeline: up to three JPEG/PNG label photos are sent
to the backend and Groq for JSON extraction; the user edits and confirms the
suggestions; Pydantic validates confirmed values; Python performs serving-size
arithmetic and deterministic ingredient matching; Groq explains only the
confirmed facts and selected goal; PostgreSQL stores the result. Photos are
processed in-memory and are not saved by FoodScan. Groq is an external
provider, so review its current data-use terms before using real or sensitive
images.
`POST /api/v1/scans/packaged` accepts only user-confirmed label details.
Nutrition values are stored with their declared basis (`per_serving` or
`per_100g`), and omitted values remain unknown. The initial
ingredient/allergen rule set is deliberately limited and is not an
allergen-free guarantee, health score, or medical advice.

Meal scanning follows photo identification, user confirmation of foods,
ingredients, cooking methods, and portions, selection of matching USDA
FoodData Central records, deterministic portion scaling, and a goal-context
explanation. Groq also suggests one practical alternative based on the
selected goal and confirmed food details. This is general guidance, not medical
advice or verified nutrition for the suggested alternative. Groq does not
supply meal nutrient values. The USDA match may not represent the exact
recipe, brand, oil, or salt used, and missing nutrient values remain
unavailable. Compare an alternative's own label or USDA record before
comparing specific nutrients.

Meal and packaged-food results also search Open Food Facts for a related
packaged product with a photo and complete per-100 g energy, protein,
carbohydrate, and fat values. The product is ranked by the selected goal where
possible, but this does not establish that it is healthier overall. Product
listings are community-contributed and can be incomplete or outdated; users
should verify the package label. Search terms (the scanned product name or
first confirmed meal component) are sent to Open Food Facts. The app credits
Open Food Facts in the result and uses the API with an identifying User-Agent.
If no suitable result is available or the service cannot be reached, the
goal-based text suggestion remains available without a product card. Existing
databases need `alembic upgrade head` to persist recommendation product cards.
Open Food Facts requests are subject to its published search rate limits. The
backend caches matches and allows at most nine cache misses per minute per
process. Deployments with multiple backend workers should use a shared
rate-limiter to stay within the service's per-IP limit. Register the app with
Open Food Facts, use its API usage form, and review its terms before deploying
this integration to production. Open Food Facts currently documents full-text
search on its legacy CGI endpoint and says the v3 search endpoint is not
implemented; this integration uses that endpoint until its dedicated search
service is available.

## Tests

Run tests from the `backend` directory with the virtual environment active:

```bash
python -m pytest
```

The API tests use an in-memory SQLite database and do not require Docker.
