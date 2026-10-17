from collections import deque
from copy import deepcopy
from decimal import Decimal, InvalidOperation
from time import monotonic
from typing import Any
from urllib.parse import urlsplit, urlunsplit

import httpx

_SEARCH_URL = "https://world.openfoodfacts.org/cgi/search.pl"
_USER_AGENT = "Bitewise/1.0"
_NUTRIENTS = {
    "energy_kcal": "energy-kcal_100g",
    "protein_g": "proteins_100g",
    "carbohydrates_g": "carbohydrates_100g",
    "fat_g": "fat_100g",
}
_CACHE_TTL_SECONDS = 6 * 60 * 60
_MAX_SEARCHES_PER_MINUTE = 9
_MAX_CACHE_ENTRIES = 256
_search_cache: dict[str, tuple[float, dict[str, Any] | None]] = {}
_search_times: deque[float] = deque()


class OpenFoodFactsError(Exception):
    pass


async def find_alternative_product(
    query: str,
    goal: str | None,
    *,
    exclude_name: str | None = None,
) -> dict[str, Any] | None:
    search_terms = query.strip()
    if not search_terms:
        return None
    cache_key = "|".join(
        (
            _normalize_name(search_terms[:120]),
            goal or "",
            _normalize_name(exclude_name or ""),
        )
    )
    now = monotonic()
    cached_result = _search_cache.get(cache_key)
    if cached_result is not None:
        expiry, cached_product = cached_result
        if expiry > now:
            return deepcopy(cached_product)
        del _search_cache[cache_key]

    while _search_times and now - _search_times[0] >= 60:
        _search_times.popleft()
    if len(_search_times) >= _MAX_SEARCHES_PER_MINUTE:
        raise OpenFoodFactsError(
            "Open Food Facts search is temporarily limited. Try again later."
        )
    _search_times.append(now)

    params = {
        "search_terms": search_terms[:120],
        "search_simple": 1,
        "action": "process",
        "json": 1,
        "fields": (
            "product_name,brands,image_front_url,image_front_small_url,"
            "nutriments,code"
        ),
        "page_size": 30,
    }
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(8.0)) as client:
            response = await client.get(
                _SEARCH_URL,
                params=params,
                headers={"User-Agent": _USER_AGENT},
            )
    except httpx.TimeoutException as error:
        raise OpenFoodFactsError("Open Food Facts product search timed out.") from error
    except httpx.RequestError as error:
        raise OpenFoodFactsError(
            "Could not connect to Open Food Facts."
        ) from error

    if response.is_error:
        raise OpenFoodFactsError(
            f"Open Food Facts returned HTTP {response.status_code}."
        )

    try:
        payload = response.json()
    except ValueError as error:
        raise OpenFoodFactsError(
            "Open Food Facts returned an invalid response."
        ) from error
    if not isinstance(payload, dict):
        raise OpenFoodFactsError("Open Food Facts returned an invalid response.")

    raw_products = payload.get("products")
    if not isinstance(raw_products, list):
        raise OpenFoodFactsError(
            "Open Food Facts returned an invalid product list."
        )

    candidates = [
        candidate
        for raw_product in raw_products
        if isinstance(raw_product, dict)
        and (candidate := _normalize_product(raw_product)) is not None
        and (
            not exclude_name
            or _normalize_name(candidate["product_name"])
            != _normalize_name(exclude_name)
        )
    ]
    result = (
        max(candidates, key=lambda product: _goal_score(product, goal))
        if candidates
        else None
    )
    if len(_search_cache) >= _MAX_CACHE_ENTRIES:
        oldest_key = next(iter(_search_cache))
        del _search_cache[oldest_key]
    _search_cache[cache_key] = (now + _CACHE_TTL_SECONDS, result)
    return deepcopy(result)


def _normalize_product(product: dict[str, Any]) -> dict[str, Any] | None:
    product_name = product.get("product_name")
    image_url = product.get("image_front_url") or product.get(
        "image_front_small_url"
    )
    if not isinstance(product_name, str) or not product_name.strip():
        return None
    if not isinstance(image_url, str):
        return None
    parsed_image_url = urlsplit(image_url)
    image_host = parsed_image_url.hostname or ""
    if (
        parsed_image_url.scheme not in {"http", "https"}
        or not any(
            image_host == domain or image_host.endswith(f".{domain}")
            for domain in ("openfoodfacts.org", "openfoodfacts.net")
        )
    ):
        return None
    if parsed_image_url.scheme == "http":
        image_url = urlunsplit(
            ("https", parsed_image_url.netloc, parsed_image_url.path, "", "")
        )

    raw_nutrients = product.get("nutriments")
    if not isinstance(raw_nutrients, dict):
        return None
    nutrition: dict[str, str] = {}
    for output_name, source_name in _NUTRIENTS.items():
        value = raw_nutrients.get(source_name)
        if value is None:
            return None
        try:
            amount = Decimal(str(value))
        except (InvalidOperation, ValueError):
            return None
        maximum = (
            Decimal("100000")
            if output_name == "energy_kcal"
            else Decimal("10000")
        )
        if not amount.is_finite() or amount < 0 or amount > maximum:
            return None
        try:
            nutrition[output_name] = str(amount.quantize(Decimal("0.1")))
        except InvalidOperation:
            return None

    code = product.get("code")
    product_url = (
        f"https://world.openfoodfacts.org/product/{code}"
        if isinstance(code, str) and code.isdigit()
        else None
    )
    brand_value = product.get("brands")
    brand = brand_value.strip() if isinstance(brand_value, str) else None
    return {
        "product_name": product_name.strip(),
        "brand": brand or None,
        "image_url": image_url,
        "product_url": product_url,
        "nutrition_per_100g": nutrition,
    }


def _goal_score(product: dict[str, Any], goal: str | None) -> tuple[Decimal, ...]:
    nutrition = product["nutrition_per_100g"]
    energy = Decimal(nutrition["energy_kcal"])
    protein = Decimal(nutrition["protein_g"])
    if goal == "muscle_gain":
        return protein, -energy
    if goal == "fat_loss":
        return -energy, protein
    return (Decimal("0"),)


def _normalize_name(value: str) -> str:
    return " ".join(value.casefold().split())
