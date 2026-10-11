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

Open `http://127.0.0.1:8000/docs` for the interactive API docs and
`http://127.0.0.1:8000/health` for the health check.

The profile endpoints currently operate on one local development profile and
are not authenticated. Add authentication before exposing profile data to
multiple users or deploying the API. Supported wellness goals are `fat_loss`,
`muscle_gain`, and `maintenance`; this value does not prescribe calorie or
medical targets.

## Tests

Run tests from the `backend` directory with the virtual environment active:

```bash
python -m pytest
```

The API tests use an in-memory SQLite database and do not require Docker.
