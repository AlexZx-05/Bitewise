from decimal import Decimal


def packaged_food_alternative(
    goal: str | None,
    energy_kcal: Decimal | None,
    protein_g: Decimal | None,
    nutrition_basis: str,
) -> str:
    if goal == "fat_loss":
        if energy_kcal is None:
            return (
                "For your fat-loss goal, compare similar products using the "
                "same serving size and choose an option with confirmed calorie "
                "information. This suggestion is general; the alternative's "
                "nutrition has not been verified."
            )
        return (
            "For your fat-loss goal, compare similar products on the same "
            f"{nutrition_basis.replace('_', ' ')} basis and choose one with "
            "fewer calories if available. This suggestion is general; the "
            "alternative's nutrition has not been verified."
        )

    if goal == "muscle_gain":
        if protein_g is None:
            return (
                "For your muscle-gain goal, compare similar products using the "
                "same serving size and choose an option with confirmed protein "
                "information. This suggestion is general; the alternative's "
                "nutrition has not been verified."
            )
        return (
            "For your muscle-gain goal, compare similar products on the same "
            f"{nutrition_basis.replace('_', ' ')} basis and choose one with "
            "more protein if available. This suggestion is general; the "
            "alternative's nutrition has not been verified."
        )

    if goal == "maintenance":
        return (
            "For your maintenance goal, compare similar products using the "
            "same serving size and choose one whose confirmed nutrition and "
            "ingredients better suit your preferences. The alternative's "
            "nutrition has not been verified."
        )

    return (
        "For a generally balanced choice, compare similar products using the "
        "same serving size and review their confirmed nutrition and ingredients. "
        "This suggestion is not personalized, and the alternative's nutrition "
        "has not been verified."
    )


def meal_alternative(goal: str | None) -> str:
    if goal == "fat_loss":
        return (
            "For your fat-loss goal, consider a slightly smaller portion of "
            "one meal component or adding a vegetable side if it suits you. "
            "This is general guidance; the change is not included in the "
            "nutrition estimate."
        )

    if goal == "muscle_gain":
        return (
            "For your muscle-gain goal, consider adding a protein-rich side "
            "that suits your preferences. Add it as a confirmed food and "
            "portion to include it in the nutrition estimate."
        )

    if goal == "maintenance":
        return (
            "For your maintenance goal, consider a vegetable or protein side "
            "that fits your preferences. Add it as a confirmed food and "
            "portion to include it in the nutrition estimate."
        )

    return (
        "For a generally balanced option, consider a vegetable or protein "
        "side that fits your preferences. Add it as a confirmed food and "
        "portion to include it in the nutrition estimate. This is not "
        "personalized guidance."
    )
