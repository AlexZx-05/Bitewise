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
explanation. Groq does not supply meal nutrient values. The USDA match may
not represent the exact recipe, brand, oil, or salt used, and missing nutrient
values remain unavailable. No named food alternative is presented as verified
without matching data.

## Tests

Run tests from the `backend` directory with the virtual environment active:

```bash
python -m pytest
```

The API tests use an in-memory SQLite database and do not require Docker.
