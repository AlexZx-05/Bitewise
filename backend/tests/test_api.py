from uuid import uuid4

from sqlalchemy.orm import Session

from app.models import FoodProduct, Ingredient
from app.api.v1.routes.profiles import LOCAL_PROFILE_ID


def test_health(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_profile_can_be_created_and_updated(client):
    initial = client.get("/api/v1/me")
    assert initial.status_code == 200
    assert initial.json()["id"] == LOCAL_PROFILE_ID
    assert initial.json()["daily_calorie_goal"] is None

    updated = client.put(
        "/api/v1/me/profile",
        json={
            "display_name": "Alex",
            "daily_calorie_goal": 2100,
            "daily_protein_goal_g": 120,
        },
    )
    assert updated.status_code == 200
    assert updated.json()["display_name"] == "Alex"
    assert updated.json()["daily_calorie_goal"] == 2100
    assert updated.json()["daily_protein_goal_g"] == "120.00"

    fetched = client.get("/api/v1/me")
    assert fetched.json()["display_name"] == "Alex"
    assert fetched.json()["daily_calorie_goal"] == 2100


def test_profile_rejects_negative_goals(client):
    response = client.put(
        "/api/v1/me/profile",
        json={"daily_calorie_goal": -1},
    )

    assert response.status_code == 422


def test_product_not_found_returns_404(client):
    response = client.get(f"/api/v1/products/{uuid4()}")

    assert response.status_code == 404
    assert response.json()["detail"] == "Product not found"


def test_product_response_includes_ingredients(client, db_session: Session):
    product_id = uuid4()
    product = FoodProduct(id=product_id, name="Oat Bar", brand="FoodScan")
    product.ingredients.append(Ingredient(name="Oats"))
    db_session.add(product)
    db_session.commit()
    response = client.get(f"/api/v1/products/{product_id}")

    assert response.status_code == 200
    assert response.json()["name"] == "Oat Bar"
    assert response.json()["ingredients"] == ["Oats"]
