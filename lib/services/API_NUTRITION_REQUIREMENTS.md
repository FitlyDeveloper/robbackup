# Nutrition API Requirements

## Overview
This document outlines the specific requirements for the food analysis API to ensure consistent handling of nutrition data. 
Our app tracks a comprehensive set of nutrients with specific units, and we require the API to return values in these formats.

## Required Nutrients with Units

### Vitamins
| Nutrient Name | API Key | Required Unit |
|---------------|---------|--------------|
| Vitamin A | vitamin_a | mcg |
| Vitamin C | vitamin_c | mg |
| Vitamin D | vitamin_d | mcg |
| Vitamin E | vitamin_e | mg |
| Vitamin K | vitamin_k | mcg |
| Vitamin B1 (Thiamine) | vitamin_b1 | mg |
| Vitamin B2 (Riboflavin) | vitamin_b2 | mg |
| Vitamin B3 (Niacin) | vitamin_b3 | mg |
| Vitamin B5 (Pantothenic Acid) | vitamin_b5 | mg |
| Vitamin B6 (Pyridoxine) | vitamin_b6 | mg |
| Vitamin B7 (Biotin) | vitamin_b7 | mcg |
| Vitamin B9 (Folate) | vitamin_b9 | mcg |
| Vitamin B12 (Cobalamin) | vitamin_b12 | mcg |

### Minerals
| Nutrient Name | API Key | Required Unit |
|---------------|---------|--------------|
| Calcium | calcium | mg |
| Chloride | chloride | mg |
| Chromium | chromium | mcg |
| Copper | copper | mcg |
| Fluoride | fluoride | mg |
| Iodine | iodine | mcg |
| Iron | iron | mg |
| Magnesium | magnesium | mg |
| Manganese | manganese | mg |
| Molybdenum | molybdenum | mcg |
| Phosphorus | phosphorus | mg |
| Potassium | potassium | mg |
| Selenium | selenium | mcg |
| Sodium | sodium | mg |
| Zinc | zinc | mg |

### Other Nutrients
| Nutrient Name | API Key | Required Unit |
|---------------|---------|--------------|
| Fiber | fiber | g |
| Cholesterol | cholesterol | mg |
| Sugar | sugar | g |
| Saturated Fats | saturated_fats | g |
| Omega-3 | omega_3 | mg |
| Omega-6 | omega_6 | g |

## Response Format

The API should return a structured JSON response with these sections:

```json
{
  "success": true,
  "data": {
    "meal_name": "Example Meal",
    "calories": 450,
    "protein": 25,
    "fat": 18,
    "carbs": 45,
    "health_score": "7/10",
    "ingredients": ["Ingredient 1", "Ingredient 2"],
    "ingredient_macros": [
      {
        "name": "Ingredient 1",
        "amount": "100g",
        "calories": 200,
        "protein": 10,
        "fat": 8,
        "carbs": 20,
        "vitamins": {
          "vitamin_a": "150 mcg",
          "vitamin_c": "20 mg"
          // Include all available vitamins with correct units
        },
        "minerals": {
          "calcium": "120 mg",
          "iron": "2 mg"
          // Include all available minerals with correct units
        },
        "other": {
          "fiber": "3 g",
          "cholesterol": "15 mg"
          // Include all available other nutrients with correct units
        }
      }
      // Repeat for each ingredient
    ],
    "vitamins": {
      "vitamin_a": "300 mcg",
      "vitamin_c": "45 mg"
      // Include all vitamins with correct units
    },
    "minerals": {
      "calcium": "250 mg",
      "iron": "4 mg"
      // Include all minerals with correct units
    },
    "other": {
      "fiber": "8 g",
      "cholesterol": "30 mg"
      // Include all other nutrients with correct units
    }
  }
}
```

## Important Requirements

1. **Strict Unit Compliance**: All nutrient values must be returned in the exact units specified above.
   
2. **Complete Nutrient Coverage**: The API should attempt to analyze and return values for all nutrients listed.
   
3. **API Request Parameters**: Our API requests will include these parameters:
   ```json
   {
     "detail_level": "high",
     "include_ingredient_macros": true,
     "return_ingredient_nutrition": true,
     "include_additional_nutrition": true,
     "include_vitamins_minerals": true,
     "expected_nutrients": {
       "vitamins": ["vitamin_a", "vitamin_c", ...],
       "minerals": ["calcium", "iron", ...],
       "other": ["fiber", "cholesterol", ...]
     },
     "nutrient_units": {
       "vitamins": {"vitamin_a": "mcg", ...},
       "minerals": {"calcium": "mg", ...},
       "other": {"fiber": "g", ...}
     },
     "unit_requirements": "strict",
     "nutrient_format": "app_compatible"
   }
   ```

4. **Format Guidelines**:
   - Numeric values should be sent as numbers, not strings (e.g., `"vitamin_c": 45`)
   - Units should be attached consistently (e.g., `"vitamin_c": "45 mg"`)
   - If a nutrient cannot be detected, use a value of 0 with the correct unit rather than omitting it

## Notes for API Developers

- The app uses these specific units to track user's nutrient intake consistently
- Converting between units in the API is preferred over client-side conversion
- Zero values should be returned for nutrients that aren't detected rather than omitting them
- New nutrients may be added in the future, and the API should handle unknown nutrient requests gracefully 