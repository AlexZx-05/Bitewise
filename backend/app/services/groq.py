import base64
import json
import re
from decimal import Decimal
from typing import Any

import httpx
from pydantic import ValidationError

from app.core.config import settings
from app.models import PackagedScanDetails, ScanFinding
from app.schemas.meal import MealVisionExtraction
from app.schemas.scan import PackagedLabelExtraction

_GROQ_CHAT_COMPLETIONS_URL = (
    "https://api.groq.com/openai/v1/chat/completions"
)


class GroqServiceError(Exception):
    def __init__(self, message: str, *, status_code: int = 502) -> None:
        super().__init__(message)
        self.status_code = status_code


async def extract_packaged_label(
    images: list[tuple[str, bytes]],
) -> PackagedLabelExtraction:
    prompt = """
Read the uploaded packaged-food label photos and extract only text and numeric
facts that are visibly printed. Return one JSON object with these keys:
product_name, brand, serving_size_g, nutrition_basis, nutrition, ingredients,
declared_allergens, precautionary_allergen_statement, missing_fields, uncertain_fields,
extraction_note.

nutrition must contain energy_kcal, protein_g, carbohydrates_g, total_fat_g,
and sodium_mg. Use null for every value that is absent or unreadable. Set
nutrition_basis to per_serving or per_100g only when the label clearly says so;
otherwise null. Do not convert units, infer missing facts, use outside product
knowledge, or silently resolve ambiguous digits. Include low-confidence field
names in uncertain_fields and fields not visible/readable in missing_fields.
Keep ingredients as the visible ingredient list, not a guessed list. Return allergens explicitly declared on the label as declared_allergens, and
keep precautionary "may contain" warnings in precautionary_allergen_statement.
""".strip()
    parts: list[dict[str, Any]] = [{"text": prompt}]
    for mime_type, content in images:
        parts.append(
            {
                "inline_data": {
                    "mime_type": mime_type,
                    "data": base64.b64encode(content).decode("ascii"),
                }
            }
        )

    payload = await _generate_json(parts, max_output_tokens=2048)
    try:
        return PackagedLabelExtraction.model_validate(payload)
    except ValidationError as error:
        invalid_fields = sorted(
            {
                ".".join(str(part) for part in issue["loc"])
                for issue in error.errors(
                    include_input=False,
                    include_context=False,
                )
            }
        )
        field_list = ", ".join(invalid_fields[:6])
        raise GroqServiceError(
            "Groq returned label details that could not be validated"
            f"{f' ({field_list})' if field_list else ''}. "
            "Retake a clear photo or use OCR/manual entry to continue."
        ) from error


async def extract_meal(
    mime_type: str,
    image: bytes,
) -> MealVisionExtraction:
    prompt = """
Identify visible foods in this meal photo and return JSON with meal_name,
components, uncertain_fields, extraction_note. Each component has food_name,
estimated_portion_g, possible_ingredients, suggested_cooking_method, and
uncertain_fields. List up to 10 distinct visible components. Portion size,
hidden ingredients, and cooking method cannot be reliably known from a photo:
use null or an empty list when unknown, and mark those fields uncertain. Never
claim an ingredient or preparation method is certain unless visually evident.
Do not estimate nutrition. Ask the user to confirm all suggestions.
""".strip()
    payload = await _generate_json(
        [
            {"text": prompt},
            {
                "inline_data": {
                    "mime_type": mime_type,
                    "data": base64.b64encode(image).decode("ascii"),
                }
            },
        ],
        max_output_tokens=1536,
    )
    try:
        return MealVisionExtraction.model_validate(payload)
    except ValidationError as error:
        invalid_fields = sorted(
            {
                ".".join(str(part) for part in issue["loc"])
                for issue in error.errors(
                    include_input=False,
                    include_context=False,
                )
            }
        )
        field_list = ", ".join(invalid_fields[:6])
        raise GroqServiceError(
            "Groq returned meal details that could not be validated"
            f"{f' ({field_list})' if field_list else ''}. "
            "Retake the photo or review the meal details manually."
        ) from error


async def explain_packaged_label(
    details: PackagedScanDetails,
    findings: list[ScanFinding],
    goal_insight: str,
    goal: str | None,
    daily_calorie_goal: int | None,
) -> str:
    basis_factor = (
        Decimal("1")
        if details.nutrition_basis == "per_serving"
        else details.serving_size_g / Decimal("100")
    )
    per_serving = {
        "energy_kcal": _scale(details.energy_kcal, basis_factor),
        "protein_g": _scale(details.protein_g, basis_factor),
        "carbohydrates_g": _scale(details.carbohydrates_g, basis_factor),
        "total_fat_g": _scale(details.total_fat_g, basis_factor),
        "sodium_mg": _scale(details.sodium_mg, basis_factor),
    }
    per_serving_energy = (
        details.energy_kcal * basis_factor
        if details.energy_kcal is not None
        else None
    )
    facts = {
        "product": details.product_name,
        "brand": details.brand,
        "serving_size_g": str(details.serving_size_g),
        "label_basis": details.nutrition_basis,
        "confirmed_label_values": {
            "energy_kcal": _string(details.energy_kcal),
            "protein_g": _string(details.protein_g),
            "carbohydrates_g": _string(details.carbohydrates_g),
            "total_fat_g": _string(details.total_fat_g),
            "sodium_mg": _string(details.sodium_mg),
        },
        "calculated_values_for_confirmed_serving": per_serving,
        "confirmed_ingredients": details.ingredients,
        "confirmed_declared_allergens": details.declared_allergens,
        "confirmed_precautionary_statement": details.precautionary_allergen_statement,
        "deterministic_label_findings": [
            {"label": item.label, "details": item.details} for item in findings
        ],
        "goal": goal,
        "daily_calorie_goal_kcal": daily_calorie_goal,
        "serving_percent_of_daily_calorie_goal": (
            str(
                (per_serving_energy / Decimal(daily_calorie_goal) * 100).quantize(
                    Decimal("0.1")
                )
            )
            if per_serving_energy is not None and daily_calorie_goal
            else None
        ),
        "deterministic_goal_context": goal_insight,
    }
    prompt = f"""
Explain this confirmed packaged-food label for the user's selected goal.
Use only supplied facts. Per-serving values are deterministic calculations
from the confirmed label and serving size. Be balanced and non-judgmental.
Mention relevant declared ingredients/allergen findings without diagnosing
allergy safety. Call out important missing data. Do not invent health benefits,
medical advice, product facts, alternatives, or safety guarantees. For an
alternative, give only comparison criteria (same taste/texture and serving,
then compare verified energy/protein/sodium labels); do not name an unverified
product. Keep the response to 3-5 concise sentences. Return a JSON object with
one string field named explanation.

Confirmed data:
{json.dumps(facts, ensure_ascii=False)}
""".strip()
    result = await _generate_json(
        [{"text": prompt}],
        max_output_tokens=512,
    )
    explanation = result.get("explanation")
    if not isinstance(explanation, str) or not explanation.strip():
        raise GroqServiceError("Groq returned an empty label explanation.")
    return explanation.strip()[:2000]


async def explain_meal(
    meal_name: str,
    components: list[dict[str, Any]],
    totals: dict[str, Decimal],
    goal: str | None,
    daily_calorie_goal: int | None,
) -> str:
    prompt = f"""
Explain this user-confirmed meal estimate in 3-5 concise, balanced sentences.
Nutrients came from USDA FoodData Central matches selected by the user and are
scaled deterministically by confirmed portions. Explain that database matches
may not represent the exact recipe, oil, salt, or preparation. Use the selected
goal only as general context; do not diagnose, prescribe, or promise safety.
Offer one practical similar-meal comparison idea without inventing nutrient
values or naming a specific unverified food. State uncertainty plainly. Return
a JSON object with one string field named explanation.

Data:
{json.dumps({
    "meal_name": meal_name,
    "goal": goal,
    "daily_calorie_goal_kcal": daily_calorie_goal,
    "components": components,
    "total_nutrition": {key: str(value) for key, value in totals.items()},
}, ensure_ascii=False)}
""".strip()
    result = await _generate_json(
        [{"text": prompt}],
        max_output_tokens=512,
    )
    explanation = result.get("explanation")
    if not isinstance(explanation, str) or not explanation.strip():
        raise GroqServiceError("Groq returned an empty meal explanation.")
    return explanation.strip()[:2000]


def _scale(value: Decimal | None, factor: Decimal) -> str | None:
    if value is None:
        return None
    return str((value * factor).quantize(Decimal("0.1")))


def _string(value: Decimal | None) -> str | None:
    return None if value is None else str(value)


async def _generate_json(
    parts: list[dict[str, Any]],
    *,
    max_output_tokens: int,
) -> dict[str, Any]:
    if settings.groq_api_key is None:
        raise GroqServiceError(
            "Groq is not configured. Add GROQ_API_KEY to backend/.env and restart the API.",
            status_code=503,
        )
    api_key = settings.groq_api_key.get_secret_value()
    content: list[dict[str, Any]] = []
    for part in parts:
        if isinstance(part.get("text"), str):
            content.append({"type": "text", "text": part["text"]})
        elif isinstance(part.get("inline_data"), dict):
            image_data = part["inline_data"]
            mime_type = image_data.get("mime_type")
            if mime_type not in {"image/jpeg", "image/png"}:
                raise GroqServiceError(
                    "Groq vision accepts JPEG and PNG photos. Choose a JPEG or PNG image.",
                    status_code=415,
                )
            content.append(
                {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:{mime_type};base64,{image_data['data']}"
                    },
                }
            )
    request_data: dict[str, Any] = {
        "model": settings.groq_model,
        "messages": [{"role": "user", "content": content}],
        "max_completion_tokens": max_output_tokens,
        "response_format": {"type": "json_object"},
    }
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(60.0)) as client:
            response = await client.post(
                _GROQ_CHAT_COMPLETIONS_URL,
                headers={
                    "Authorization": f"Bearer {api_key}"
                },
                json=request_data,
            )
    except httpx.TimeoutException as error:
        raise GroqServiceError(
            "Groq did not respond before the request timed out.",
            status_code=504,
        ) from error
    except httpx.RequestError as error:
        raise GroqServiceError("Could not connect to the Groq service.") from error

    if response.is_error:
        if response.status_code == 429:
            raise GroqServiceError(
                "Groq API rate or usage limit reached. Check Groq account usage "
                "and billing or wait before retrying. For label scans, use "
                "local OCR or enter the details manually.",
                status_code=503,
            )
        if response.status_code in {401, 403}:
            raise GroqServiceError(
                "Groq rejected the API credentials or account access. "
                "Check GROQ_API_KEY and Groq account access.",
                status_code=503,
            )
        provider_message = _provider_error_message(response)
        if response.status_code == 400 and provider_message:
            raise GroqServiceError(
                f"Groq rejected the request: {provider_message} "
                "Check that GROQ_MODEL is available to your account and "
                "that the image is supported.",
                status_code=502,
            )
        status_code = 503 if response.status_code in {500, 502, 503, 504} else 502
        raise GroqServiceError(
            f"Groq returned HTTP {response.status_code} for model "
            f"{settings.groq_model}. Check Groq service status and model access.",
            status_code=status_code,
        )
    try:
        response_data = response.json()
        if not isinstance(response_data, dict):
            raise TypeError("Groq response must be a JSON object.")
        text = _response_text(response_data)
        result = json.loads(text)
    except (ValueError, KeyError, IndexError, TypeError, AttributeError) as error:
        raise GroqServiceError("Groq returned an invalid JSON response.") from error
    if not isinstance(result, dict):
        raise GroqServiceError("Groq returned JSON in an unexpected format.")
    return result


def _provider_error_message(response: httpx.Response) -> str | None:
    try:
        payload = response.json()
    except ValueError:
        return None

    if not isinstance(payload, dict):
        return None

    error = payload.get("error")
    if isinstance(error, dict):
        message = error.get("message") or error.get("detail")
    elif isinstance(error, str):
        message = error
    else:
        message = payload.get("message") or payload.get("detail")

    if not isinstance(message, str) or not message.strip():
        return None

    safe_message = re.sub(
        r"(?i)\b(?:xai-|gsk_)[A-Za-z0-9_-]+",
        "[redacted key]",
        message,
    )
    safe_message = re.sub(r"data:image/[^;]+;base64,[A-Za-z0-9+/=]+", "[image]", safe_message)
    return safe_message.strip()[:300]


def _response_text(response_data: dict[str, Any]) -> str:
    choices = response_data.get("choices")
    if isinstance(choices, list) and choices and isinstance(choices[0], dict):
        message = choices[0].get("message")
        if isinstance(message, dict) and isinstance(message.get("content"), str):
            return message["content"]
    raise ValueError("Groq response did not contain message content.")
