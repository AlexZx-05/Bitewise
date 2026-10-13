from uuid import uuid4
from decimal import Decimal

from sqlalchemy.orm import Session

from app.models import FoodProduct, Ingredient
from app.api.v1.routes.profiles import LOCAL_PROFILE_ID


def test_external_api_keys_are_loaded_as_secrets():
    from app.core.config import Settings

    settings = Settings(
        groq_api_key="groq-test-key",
        usda_api_key="usda-test-key",
    )

    assert settings.groq_api_key.get_secret_value() == "groq-test-key"
    assert settings.usda_api_key.get_secret_value() == "usda-test-key"
    assert settings.groq_model == "qwen/qwen3.8-27b"


def test_groq_quota_error_is_actionable_and_does_not_expose_raw_provider_text(
    monkeypatch,
):
    import asyncio

    from app.services import groq
    from pydantic import SecretStr

    class FakeResponse:
        status_code = 429
        is_error = True

        @staticmethod
        def json():
            return {
                "error": {
                    "message": (
                        "You exceeded your current quota for free_tier_requests."
                    )
                }
            }

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return None

        async def post(self, *args, **kwargs):
            return FakeResponse()

    monkeypatch.setattr(groq.httpx, "AsyncClient", FakeAsyncClient)
    monkeypatch.setattr(groq.settings, "groq_api_key", SecretStr("test-key"))

    try:
        asyncio.run(groq._generate_json([{"text": "test"}], max_output_tokens=5))
    except groq.GroqServiceError as error:
        assert error.status_code == 503
        assert "rate or usage limit reached" in str(error)
        assert "free_tier_requests" not in str(error)
    else:
        raise AssertionError("Quota exhaustion must be reported.")


def test_groq_request_uses_chat_completions_json_mode_and_inline_vision(monkeypatch):
    import asyncio

    from app.services import groq
    from pydantic import SecretStr

    captured = {}

    class FakeResponse:
        is_error = False

        @staticmethod
        def json():
            return {"choices": [{"message": {"content": '{"recognized":true}'}}]}

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return None

        async def post(self, url, *, headers, json):
            captured.update(url=url, headers=headers, json=json)
            return FakeResponse()

    monkeypatch.setattr(groq.httpx, "AsyncClient", FakeAsyncClient)
    monkeypatch.setattr(groq.settings, "groq_api_key", SecretStr("test-key"))

    result = asyncio.run(
        groq._generate_json(
            [
                {"text": "Read this label."},
                {
                    "inline_data": {
                        "mime_type": "image/jpeg",
                        "data": "aW1hZ2U=",
                    }
                },
            ],
            max_output_tokens=10,
        )
    )

    assert result == {"recognized": True}
    assert captured["url"] == (
        "https://api.groq.com/openai/v1/chat/completions"
    )
    assert captured["headers"]["Authorization"] == "Bearer test-key"
    assert captured["json"]["model"] == "qwen/qwen3.8-27b"
    assert captured["json"]["response_format"]["type"] == "json_object"
    assert captured["json"]["messages"][0]["content"][1]["image_url"]["url"] == (
        "data:image/jpeg;base64,aW1hZ2U="
    )


def test_groq_exposes_safe_request_rejection_reason(monkeypatch):
    import asyncio

    from app.services import groq
    from pydantic import SecretStr

    class FakeResponse:
        status_code = 400
        is_error = True

        @staticmethod
        def json():
            return {
                "error": {
                    "message": "Unknown model qwen/model; key gsk_sensitive-token"
                }
            }

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return None

        async def post(self, *args, **kwargs):
            return FakeResponse()

    monkeypatch.setattr(groq.httpx, "AsyncClient", FakeAsyncClient)
    monkeypatch.setattr(groq.settings, "groq_api_key", SecretStr("valid-test-key"))

    try:
        asyncio.run(groq._generate_json([{"text": "test"}], max_output_tokens=5))
    except groq.GroqServiceError as error:
        assert error.status_code == 502
        assert "Unknown model qwen/model" in str(error)
        assert "[redacted key]" in str(error)
        assert "gsk_sensitive-token" not in str(error)
    else:
        raise AssertionError("A provider HTTP 400 must be reported.")


def test_packaged_extraction_accepts_null_lists_without_inventing_facts():
    from app.schemas.scan import PackagedLabelExtraction

    extracted = PackagedLabelExtraction.model_validate(
        {
            "nutrition": {"energy_kcal": None},
            "ingredients": None,
            "declared_allergens": None,
            "missing_fields": None,
            "uncertain_fields": None,
        }
    )

    assert extracted.ingredients == []
    assert extracted.declared_allergens == []
    assert extracted.missing_fields == []
    assert extracted.uncertain_fields == []
    assert extracted.nutrition.energy_kcal is None


def test_packaged_extraction_normalizes_provider_field_variants():
    from app.schemas.scan import PackagedLabelExtraction

    extracted = PackagedLabelExtraction.model_validate(
        {
            "product_name": "Example snack",
            "nutrition": None,
            "energy_kcal": "120",
            "protein_g": "not readable",
            "ingredients": "corn, oil",
            "allergens": ["milk"],
            "missing_fields": None,
            "uncertain_fields": None,
            "extraction_note": None,
        }
    )

    assert extracted.nutrition.energy_kcal == 120
    assert extracted.nutrition.protein_g is None
    assert extracted.ingredients == ["corn, oil"]
    assert extracted.declared_allergens == ["milk"]
    assert "protein_g" in extracted.uncertain_fields
    assert "protein_g" in extracted.missing_fields
    assert extracted.extraction_note


def test_packaged_extraction_keeps_malformed_provider_facts_unknown():
    from app.schemas.scan import PackagedLabelExtraction

    extracted = PackagedLabelExtraction.model_validate(
        {
            "name": "Example snack",
            "serving_size_g": "30 g",
            "nutrition_basis": "Per 100 g",
            "nutrition": "not a nutrition table",
            "ingredients": ["corn", None],
            "extraction_note": 10,
        }
    )

    assert extracted.product_name == "Example snack"
    assert extracted.serving_size_g == Decimal("30")
    assert extracted.nutrition_basis == "per_100g"
    assert extracted.nutrition.energy_kcal is None
    assert set(extracted.missing_fields) >= {
        "energy_kcal",
        "protein_g",
        "carbohydrates_g",
        "total_fat_g",
        "sodium_mg",
    }
    assert "ingredients" in extracted.uncertain_fields
    assert extracted.ingredients == ["corn"]
    assert extracted.extraction_note


def test_packaged_extraction_normalizes_overlong_provider_note():
    from app.schemas.scan import PackagedLabelExtraction

    extracted = PackagedLabelExtraction.model_validate(
        {"extraction_note": "Review the label. " * 40}
    )

    assert (
        extracted.extraction_note
        == "Some extracted details could not be read. Review the label."
    )


def test_meal_extraction_normalizes_common_vision_response_variants():
    from app.schemas.meal import MealVisionExtraction

    extracted = MealVisionExtraction.model_validate(
        {
            "result": {
                "dish_name": "Rice and vegetables",
                "components": {
                    "items": ["cooked rice", {"name": "vegetables"}],
                },
                "uncertain_fields": None,
            }
        }
    )

    assert extracted.meal_name == "Rice and vegetables"
    assert [item.food_name for item in extracted.components] == [
        "cooked rice",
        "vegetables",
    ]
    assert all(item.estimated_portion_g is None for item in extracted.components)
    assert extracted.extraction_note


def test_meal_extraction_recovers_missing_name_from_reviewable_components():
    from app.schemas.meal import MealVisionExtraction

    extracted = MealVisionExtraction.model_validate(
        {
            "meal_name": None,
            "components": ["cooked rice", {"name": "lentil stew"}],
        }
    )

    assert extracted.meal_name == "cooked rice and lentil stew"
    assert "meal_name" in extracted.uncertain_fields
    assert [item.food_name for item in extracted.components] == [
        "cooked rice",
        "lentil stew",
    ]


def test_meal_extraction_uses_review_prompt_when_name_and_components_are_missing():
    from app.schemas.meal import MealVisionExtraction

    extracted = MealVisionExtraction.model_validate(
        {"meal_name": "", "components": [{"food_name": "unidentified food"}]}
    )

    assert extracted.meal_name == "unidentified food"
    assert "meal_name" in extracted.uncertain_fields


def test_meal_extraction_error_identifies_invalid_response_fields(monkeypatch):
    import asyncio

    from app.services import groq

    async def invalid_response(*args, **kwargs):
        return {"meal_name": "Lunch", "components": []}

    monkeypatch.setattr(groq, "_generate_json", invalid_response)
    try:
        asyncio.run(groq.extract_meal("image/jpeg", b"meal-photo"))
    except groq.GroqServiceError as error:
        assert "components" in str(error)
    else:
        raise AssertionError("Invalid meal output should be reported.")


def test_usda_legacy_and_current_nutrient_numbers_are_mapped():
    from app.services.usda import _extract_nutrients

    nutrients = _extract_nutrients(
        {
            "foodNutrients": [
                {
                    "nutrient": {"number": "208", "name": "Energy"},
                    "amount": 380,
                },
                {
                    "nutrient": {"number": "203", "name": "Protein"},
                    "amount": 9,
                },
                {
                    "nutrient": {"number": "205", "name": "Carbohydrate"},
                    "amount": 80.1,
                },
                {
                    "nutrient": {"number": "204", "name": "Total lipid"},
                    "amount": 3.5,
                },
                {
                    "nutrient": {"number": "307", "name": "Sodium"},
                    "amount": 116,
                },
            ]
        }
    )

    assert nutrients == {
        "energy_kcal": Decimal("380"),
        "protein_g": Decimal("9"),
        "carbohydrates_g": Decimal("80.1"),
        "total_fat_g": Decimal("3.5"),
        "sodium_mg": Decimal("116"),
    }


def test_usda_food_search_includes_prepared_food_and_branded_records(monkeypatch):
    import asyncio

    from pydantic import SecretStr

    from app.services import usda

    captured = {}

    class FakeResponse:
        status_code = 200
        is_error = False

        @staticmethod
        def json():
            return {
                "foods": [
                    {
                        "fdcId": 123,
                        "description": "Lentil stew",
                        "dataType": "Survey (FNDDS)",
                    }
                ]
            }

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return None

        async def post(self, url, *, params, json):
            captured.update(url=url, params=params, json=json)
            return FakeResponse()

    monkeypatch.setattr(usda.httpx, "AsyncClient", FakeAsyncClient)
    monkeypatch.setattr(usda.settings, "usda_api_key", SecretStr("test-key"))

    foods = asyncio.run(usda.search_foods("dal"))

    assert foods == [
        {
            "fdc_id": 123,
            "description": "Lentil stew",
            "data_type": "Survey (FNDDS)",
        }
    ]
    assert captured["params"] == {"api_key": "test-key"}
    assert captured["json"] == {
        "query": "dal",
        "pageSize": 20,
        "dataType": [
            "Foundation",
            "SR Legacy",
            "Survey (FNDDS)",
            "Branded",
        ],
    }


def test_usda_food_search_retries_query_without_punctuation(monkeypatch):
    import asyncio

    from pydantic import SecretStr

    from app.services import usda

    requests = []

    class FakeResponse:
        def __init__(self, status_code, payload):
            self.status_code = status_code
            self.is_error = status_code >= 400
            self.payload = payload

        def json(self):
            return self.payload

    class FakeAsyncClient:
        def __init__(self, *args, **kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return None

        async def post(self, url, *, params, json):
            requests.append(json["query"])
            if len(requests) == 1:
                return FakeResponse(400, {"message": "Invalid query"})
            return FakeResponse(
                200,
                {
                    "foods": [
                        {
                            "fdcId": 456,
                            "description": "Carrots, cooked",
                            "dataType": "SR Legacy",
                        }
                    ]
                },
            )

    monkeypatch.setattr(usda.httpx, "AsyncClient", FakeAsyncClient)
    monkeypatch.setattr(usda.settings, "usda_api_key", SecretStr("test-key"))

    foods = asyncio.run(usda.search_foods("Spiced carrot salad/stir-fry"))

    assert requests == [
        "Spiced carrot salad/stir-fry",
        "Spiced carrot salad stir fry",
    ]
    assert foods[0]["description"] == "Carrots, cooked"


def test_usda_search_error_messages_are_actionable():
    from app.services.usda import UsdaServiceError, _raise_for_response

    class FakeResponse:
        is_error = True

        def __init__(self, status_code):
            self.status_code = status_code

    expected_messages = {
        400: "Try a shorter name",
        403: "Check USDA_API_KEY",
        429: "rate-limited",
    }
    for status_code, expected_message in expected_messages.items():
        try:
            _raise_for_response(FakeResponse(status_code))
        except UsdaServiceError as error:
            assert expected_message in str(error)
        else:
            raise AssertionError(f"HTTP {status_code} must be reported.")


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


def test_profile_goal_is_saved_and_validated(client):
    saved = client.put(
        "/api/v1/me/profile",
        json={"goal": "fat_loss"},
    )
    assert saved.status_code == 200
    assert saved.json()["goal"] == "fat_loss"

    fetched = client.get("/api/v1/me")
    assert fetched.json()["goal"] == "fat_loss"

    rejected = client.put(
        "/api/v1/me/profile",
        json={"goal": "extreme_diet"},
    )
    assert rejected.status_code == 422


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


def test_packaged_scan_is_analyzed_and_persisted(client, monkeypatch):
    from app.api.v1 import routes

    async def fake_explanation(*args, **kwargs):
        return "Test explanation."

    monkeypatch.setattr(
        routes.scans,
        "explain_packaged_label",
        fake_explanation,
    )
    response = client.post(
        "/api/v1/scans/packaged",
        json={
            "product_name": "Oat & Peanut Bar",
            "brand": "Example Foods",
            "serving_size_g": 40,
            "nutrition_basis": "per_serving",
            "energy_kcal": 180,
            "protein_g": 6,
            "ingredients": ["Oats", "peanuts", "sugar"],
            "precautionary_allergen_statement": "May contain milk.",
        },
    )

    assert response.status_code == 201
    result = response.json()
    assert result["status"] == "completed"
    assert result["product"]["product_name"] == "Oat & Peanut Bar"
    assert result["product"]["carbohydrates_g"] is None
    assert result["goal_insight"]
    assert result["llm_explanation"] == "Test explanation."
    assert {finding["category"] for finding in result["findings"]} == {
        "declared_allergen",
        "ingredient_fact",
        "precautionary_allergen",
    }
    assert any(
        finding["label"] == "Label lists peanut" for finding in result["findings"]
    )
    assert any(
        finding["label"] == "May contain milk" for finding in result["findings"]
    )

    fetched = client.get(f"/api/v1/scans/{result['scan_id']}")
    assert fetched.status_code == 200
    assert fetched.json()["product"]["ingredients"] == ["Oats", "peanuts", "sugar"]


def test_packaged_extraction_uses_uploaded_photos(client, monkeypatch):
    from app.api.v1 import routes
    from app.schemas.scan import PackagedLabelExtraction

    async def fake_extraction(images):
        assert images == [("image/jpeg", b"label-photo")]
        return PackagedLabelExtraction(
            product_name="Example Chips",
            serving_size_g=30,
            nutrition_basis="per_100g",
            nutrition={"energy_kcal": 500},
            ingredients=["potato", "oil"],
            declared_allergens=["milk"],
            missing_fields=["protein_g"],
            uncertain_fields=["serving_size_g"],
        )

    monkeypatch.setattr(routes.scans, "extract_packaged_label", fake_extraction)
    response = client.post(
        "/api/v1/scans/packaged/extract",
        files={"files": ("label.jpg", b"label-photo", "image/jpeg")},
    )

    assert response.status_code == 200
    result = response.json()["extracted"]
    assert result["product_name"] == "Example Chips"
    assert result["nutrition"]["energy_kcal"] == "500"
    assert result["declared_allergens"] == ["milk"]
    assert result["missing_fields"] == ["protein_g"]
    assert result["uncertain_fields"] == ["serving_size_g"]


def test_packaged_extraction_rejects_non_image_upload(client):
    response = client.post(
        "/api/v1/scans/packaged/extract",
        files={"files": ("label.txt", b"not an image", "text/plain")},
    )

    assert response.status_code == 415


def test_packaged_extraction_limits_upload_to_three_images(client):
    response = client.post(
        "/api/v1/scans/packaged/extract",
        files=[
            ("files", ("front.jpg", b"front", "image/jpeg")),
            ("files", ("nutrition.jpg", b"nutrition", "image/jpeg")),
            ("files", ("ingredients.jpg", b"ingredients", "image/jpeg")),
            ("files", ("extra.jpg", b"extra", "image/jpeg")),
        ],
    )

    assert response.status_code == 422
    assert "one and three" in response.json()["detail"]


def test_meal_photo_extraction_requires_user_confirmation(client, monkeypatch):
    from app.api.v1.routes import meals
    from app.schemas.meal import MealVisionExtraction

    async def fake_extract(mime_type, image):
        assert mime_type == "image/jpeg"
        assert image == b"meal-photo"
        return MealVisionExtraction(
            meal_name="Rice and dal",
            components=[
                {
                    "food_name": "Cooked white rice",
                    "estimated_portion_g": 180,
                    "possible_ingredients": ["rice", "water"],
                    "suggested_cooking_method": "boiled",
                    "uncertain_fields": ["portion", "ingredients"],
                }
            ],
            uncertain_fields=["portion"],
            extraction_note="Confirm the visible food and portion.",
        )

    monkeypatch.setattr(meals, "extract_meal", fake_extract)
    response = client.post(
        "/api/v1/scans/meals/extract",
        files={"image": ("meal.jpg", b"meal-photo", "image/jpeg")},
    )

    assert response.status_code == 200
    extracted = response.json()["extracted"]
    assert extracted["meal_name"] == "Rice and dal"
    assert extracted["components"][0]["food_name"] == "Cooked white rice"
    assert extracted["components"][0]["uncertain_fields"] == [
        "portion",
        "ingredients",
    ]


def test_meal_confirm_uses_selected_usda_food_and_confirmed_portion(
    client, monkeypatch
):
    from app.api.v1.routes import meals

    async def fake_food(fdc_id):
        return {
            "fdc_id": fdc_id,
            "description": "Rice, white, cooked",
            "data_type": "SR Legacy",
            "nutrition_per_100g": {
                "energy_kcal": 130,
                "protein_g": 2.7,
                "carbohydrates_g": 28.2,
                "total_fat_g": 0.3,
                "sodium_mg": 1,
            },
        }

    async def fake_explanation(*args, **kwargs):
        return "Test meal explanation."

    monkeypatch.setattr(meals, "get_food_nutrition", fake_food)
    monkeypatch.setattr(meals, "explain_meal", fake_explanation)
    response = client.post(
        "/api/v1/scans/meals/confirm",
        json={
            "meal_name": "Rice",
            "meal_type": "lunch",
            "components": [
                {
                    "fdc_id": 123,
                    "food_name": "Cooked white rice",
                    "portion_g": 150,
                    "portion_pieces": 2,
                    "grams_per_piece": 75,
                    "ingredients": ["rice", "water"],
                    "cooking_method": "boiled",
                }
            ],
        },
    )

    assert response.status_code == 201
    result = response.json()
    assert result["nutrition_totals"]["energy_kcal"] == "195.0"
    assert result["nutrition_totals"]["protein_g"] == "4.0"
    assert result["meal_type"] == "lunch"
    assert result["components"][0]["portion_pieces"] == "2"
    assert result["components"][0]["grams_per_piece"] == "75"
    assert result["components"][0]["data_source"] == (
        "USDA FoodData Central (SR Legacy)"
    )
    assert result["goal_explanation"] == "Test meal explanation."

    fetched = client.get(f"/api/v1/scans/meals/{result['scan_id']}")
    assert fetched.status_code == 200
    assert fetched.json()["meal_name"] == "Rice"

    diary = client.get(
        "/api/v1/scans/meals",
        params={"date": result["created_at"][:10]},
    )
    assert diary.status_code == 200
    assert diary.json()["date"] == result["created_at"][:10]
    assert len(diary.json()["meals"]) == 1
    assert diary.json()["meals"][0]["meal_type"] == "lunch"


def test_meal_confirm_rejects_inconsistent_piece_weight(client):
    response = client.post(
        "/api/v1/scans/meals/confirm",
        json={
            "meal_name": "Roti",
            "components": [
                {
                    "fdc_id": 123,
                    "food_name": "Roti",
                    "portion_g": 100,
                    "portion_pieces": 2,
                    "grams_per_piece": 40,
                    "cooking_method": "baked",
                }
            ],
        },
    )

    assert response.status_code == 422


def test_packaged_scan_rejects_missing_nutrition_values(client):
    response = client.post(
        "/api/v1/scans/packaged",
        json={
            "product_name": "Example bar",
            "serving_size_g": 40,
            "nutrition_basis": "per_100g",
            "ingredients": ["Oats"],
        },
    )

    assert response.status_code == 422


def test_packaged_scan_rejects_unknown_basis_and_negative_values(client):
    payload = {
        "product_name": "Example bar",
        "serving_size_g": 40,
        "nutrition_basis": "per_pack",
        "energy_kcal": -1,
    }
    response = client.post("/api/v1/scans/packaged", json=payload)

    assert response.status_code == 422


def test_scan_not_found_returns_404(client):
    response = client.get(f"/api/v1/scans/{uuid4()}")

    assert response.status_code == 404
