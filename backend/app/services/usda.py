from decimal import Decimal, InvalidOperation
import re
from typing import Any

import httpx

from app.core.config import settings

_FDC_API = "https://api.nal.usda.gov/fdc/v1"
_NUTRIENT_NUMBERS = {
    "1008": "energy_kcal",
    "2047": "energy_kcal",
    "208": "energy_kcal",
    "1003": "protein_g",
    "203": "protein_g",
    "1005": "carbohydrates_g",
    "205": "carbohydrates_g",
    "1004": "total_fat_g",
    "204": "total_fat_g",
    "1093": "sodium_mg",
    "307": "sodium_mg",
}


class UsdaServiceError(Exception):
    def __init__(self, message: str, *, status_code: int = 502) -> None:
        super().__init__(message)
        self.status_code = status_code


async def search_foods(query: str) -> list[dict[str, Any]]:
    key = _api_key()
    request_query = query.strip()
    params = {"api_key": key}
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(20.0)) as client:
            response = await client.post(
                f"{_FDC_API}/foods/search",
                params=params,
                json={
                    "query": request_query,
                    "pageSize": 20,
                    "dataType": [
                        "Foundation",
                        "SR Legacy",
                        "Survey (FNDDS)",
                        "Branded",
                    ],
                },
            )
            if response.status_code == 400:
                simplified_query = _simplify_search_query(request_query)
                if simplified_query and simplified_query != request_query:
                    response = await client.post(
                        f"{_FDC_API}/foods/search",
                        params=params,
                        json={
                            "query": simplified_query,
                            "pageSize": 20,
                            "dataType": [
                                "Foundation",
                                "SR Legacy",
                                "Survey (FNDDS)",
                                "Branded",
                            ],
                        },
                    )
    except httpx.TimeoutException as error:
        raise UsdaServiceError("USDA FoodData Central timed out.") from error
    except httpx.RequestError as error:
        raise UsdaServiceError("Could not connect to USDA FoodData Central.") from error

    _raise_for_response(response)
    try:
        foods = response.json()["foods"]
    except (ValueError, KeyError, TypeError) as error:
        raise UsdaServiceError("USDA returned an invalid food-search response.") from error

    return [
        {
            "fdc_id": food["fdcId"],
            "description": food["description"],
            "data_type": food.get("dataType"),
        }
        for food in foods
        if isinstance(food.get("fdcId"), int)
        and isinstance(food.get("description"), str)
    ]


async def get_food_nutrition(fdc_id: int) -> dict[str, Any]:
    key = _api_key()
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(20.0)) as client:
            response = await client.get(
                f"{_FDC_API}/food/{fdc_id}",
                params={"api_key": key},
            )
    except httpx.TimeoutException as error:
        raise UsdaServiceError("USDA FoodData Central timed out.") from error
    except httpx.RequestError as error:
        raise UsdaServiceError("Could not connect to USDA FoodData Central.") from error

    if response.status_code == 404:
        raise UsdaServiceError("The selected USDA food record was not found.", status_code=404)
    _raise_for_response(response)
    try:
        data = response.json()
        nutrients = _extract_nutrients(data)
        description = data["description"]
        data_type = data.get("dataType", "USDA FoodData Central")
    except (ValueError, KeyError, TypeError) as error:
        raise UsdaServiceError("USDA returned an invalid food detail response.") from error
    return {
        "fdc_id": fdc_id,
        "description": description,
        "data_type": data_type,
        "nutrition_per_100g": nutrients,
    }


def _extract_nutrients(data: dict[str, Any]) -> dict[str, Decimal]:
    result: dict[str, Decimal] = {}
    for entry in data.get("foodNutrients", []):
        nutrient = entry.get("nutrient") or entry
        number = str(nutrient.get("number", nutrient.get("nutrientNumber", "")))
        name = _NUTRIENT_NUMBERS.get(number)
        amount = entry.get("amount", nutrient.get("amount", nutrient.get("value")))
        if name is None or amount is None or name in result:
            continue
        try:
            result[name] = Decimal(str(amount))
        except InvalidOperation:
            continue
    return result


def _api_key() -> str:
    if settings.usda_api_key is None:
        raise UsdaServiceError(
            "USDA is not configured. Add USDA_API_KEY to backend/.env and restart the API.",
            status_code=503,
        )
    return settings.usda_api_key.get_secret_value()


def _simplify_search_query(query: str) -> str:
    words = re.sub(r"[^\w\s]", " ", query, flags=re.UNICODE).split()
    return " ".join(words)


def _raise_for_response(response: httpx.Response) -> None:
    if not response.is_error:
        return

    if response.status_code == 400:
        message = (
            "USDA could not process that food search. Try the main food name, "
            "such as “carrot” or “lentils”."
        )
    elif response.status_code == 403:
        message = (
            "USDA did not accept the API key. Check USDA_API_KEY in "
            "backend/.env, then restart the backend."
        )
    elif response.status_code == 429:
        message = "USDA search is temporarily rate-limited. Wait a little and try again."
    elif response.status_code >= 500:
        message = "USDA is temporarily unavailable. Please try again shortly."
    else:
        message = "USDA could not complete the food search. Please try again."

    raise UsdaServiceError(message)
