import re

from app.models import PackagedScanDetails, ScanFinding, UserProfile

ALLERGEN_TERMS = {
    "milk": ("milk", "whey", "casein", "lactose"),
    "peanut": ("peanut", "peanuts", "groundnut", "groundnuts"),
    "tree nuts": (
        "almond",
        "almonds",
        "cashew",
        "cashews",
        "walnut",
        "walnuts",
        "pistachio",
        "pistachios",
        "hazelnut",
        "hazelnuts",
        "pecan",
        "pecans",
    ),
    "wheat/gluten": ("wheat", "gluten", "barley", "rye"),
    "soy": ("soy", "soya", "soybean", "soybeans"),
    "sesame": ("sesame", "til"),
    "mustard": ("mustard",),
    "egg": ("egg",),
    "fish": ("fish",),
    "crustaceans": ("crustacean", "shrimp", "prawn", "crab", "lobster"),
}

ADDED_SWEETENER_TERMS = (
    "sugar",
    "jaggery",
    "honey",
    "glucose syrup",
    "corn syrup",
    "dextrose",
    "fructose",
)


def _contains_term(text: str, terms: tuple[str, ...]) -> bool:
    normalized = text.casefold()
    return any(
        re.search(rf"(?<!\w){re.escape(term)}(?!\w)", normalized)
        for term in terms
    )


def analyze_confirmed_label(
    details: PackagedScanDetails, profile: UserProfile
) -> tuple[list[ScanFinding], str]:
    ingredient_text = ", ".join(details.ingredients)
    declared_allergen_text = ", ".join(details.declared_allergens or [])
    findings: list[ScanFinding] = []

    for allergen, terms in ALLERGEN_TERMS.items():
        if _contains_term(ingredient_text, terms) or _contains_term(
            declared_allergen_text, terms
        ):
            findings.append(
                ScanFinding(
                    category="declared_allergen",
                    label=f"Label lists {allergen}",
                    details=(
                        "Matched in the confirmed ingredient or allergen "
                        "declaration. Check the package label yourself, "
                        "especially if you have an allergy."
                    ),
                )
            )
        if details.precautionary_allergen_statement and _contains_term(
            details.precautionary_allergen_statement, terms
        ):
            findings.append(
                ScanFinding(
                    category="precautionary_allergen",
                    label=f"May contain {allergen}",
                    details=(
                        "Matched in the precautionary statement you confirmed. "
                        "This is separate from the listed ingredients."
                    ),
                )
            )

    if _contains_term(ingredient_text, ADDED_SWEETENER_TERMS):
        findings.append(
            ScanFinding(
                category="ingredient_fact",
                label="Added sweetener listed",
                details=(
                    "A named sweetener appears in the confirmed ingredients; "
                    "this is not a health rating."
                ),
            )
        )

    basis = "per serving" if details.nutrition_basis == "per_serving" else "per 100 g"
    if profile.goal == "fat_loss":
        if details.energy_kcal is None:
            insight = (
                "Your fat-loss goal is selected. Energy was not entered from "
                "the confirmed label; no value has been estimated."
            )
        else:
            insight = (
                f"Your fat-loss goal is selected. The confirmed label lists "
                f"{details.energy_kcal} kcal {basis}. This is label information, "
                "not a dietary recommendation."
            )
    elif profile.goal == "muscle_gain":
        if details.protein_g is None:
            insight = (
                "Your muscle-gain goal is selected. Protein was not entered "
                "from the confirmed label; no value has been estimated."
            )
        else:
            insight = (
                f"Your muscle-gain goal is selected. The confirmed label lists "
                f"{details.protein_g} g protein {basis}. This is label "
                "information, not a dietary recommendation."
            )
    else:
        insight = (
            f"Nutrition values are shown {basis}. Compare products using the "
            "same serving basis and size."
        )

    return findings, insight
