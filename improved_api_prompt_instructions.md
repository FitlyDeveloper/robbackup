# Improved API Prompt Instructions for Better Ingredient Detection

## Current Issue
The OpenAI vision API is sometimes only returning 1 ingredient instead of detecting all ingredients in complex meals with multiple components.

## Root Cause
The current API prompt is not explicitly optimized for multi-ingredient detection and precise nutrition values.

## Improved Server-Side Prompt

### Enhanced Prompt Template
```
You are a professional nutritionist and food analyst. Analyze this food image and identify ALL individual ingredients and food items visible in the meal.

CRITICAL REQUIREMENTS:
1. **Multiple Ingredient Detection**: For complex meals, identify EACH separate ingredient/component
2. **Precise Values**: Provide exact decimal values (e.g., 23.7g, not 24g)
3. **Comprehensive Analysis**: Include all visible food components

ANALYSIS STRUCTURE:
For each ingredient found, provide:
- Exact ingredient name
- Estimated weight in grams (precise to 1 decimal place)
- Detailed nutrition per ingredient:
  * Calories (precise to 1 decimal)
  * Protein (grams, 1 decimal precision)
  * Fat (grams, 1 decimal precision) 
  * Carbohydrates (grams, 1 decimal precision)
  * Vitamins (with precise values and units)
  * Minerals (with precise values and units)
  * Other nutrients (fiber, cholesterol, sugar, saturated fats, omega-3, omega-6)

INGREDIENT CATEGORIES TO DETECT:
- **Proteins**: meat, fish, eggs, dairy, legumes, nuts
- **Vegetables**: all visible vegetables, garnishes, herbs
- **Grains/Starches**: rice, bread, pasta, potatoes
- **Sauces/Condiments**: dressings, sauces, oils
- **Fruits**: any visible fruits or fruit components
- **Beverages**: if visible in the image

RESPONSE FORMAT:
```json
{
  "success": true,
  "meal_name": "Descriptive meal name",
  "total_calories": 456.7,
  "total_protein": 23.4,
  "total_fat": 18.9,
  "total_carbs": 45.2,
  "ingredients": [
    {
      "name": "Grilled Chicken Breast",
      "weight_g": 120.0,
      "calories": 198.0,
      "protein_g": 37.2,
      "fat_g": 4.3,
      "carbs_g": 0.0
    },
    {
      "name": "Steamed Broccoli", 
      "weight_g": 85.0,
      "calories": 28.9,
      "protein_g": 3.0,
      "fat_g": 0.3,
      "carbs_g": 5.5
    }
  ],
  "ingredient_nutrients": [
    {
      "vitamins": {
        "vitamin_a": 12.5,
        "vitamin_c": 89.2,
        "vitamin_d": 0.0
      },
      "minerals": {
        "calcium": 47.0,
        "iron": 0.7,
        "potassium": 316.0
      },
      "other": {
        "fiber": 2.6,
        "cholesterol": 85.0,
        "sugar": 1.5,
        "saturated_fats": 1.2,
        "omega_3": 0.1,
        "omega_6": 0.4
      }
    }
  ]
}
```

PRECISION REQUIREMENTS:
- All numeric values must include 1 decimal place minimum
- No rounding to whole numbers unless the actual value is whole
- Preserve exact nutritional precision from database lookups
- Use standard nutritional units (g, mg, mcg, kcal)

MULTI-INGREDIENT DETECTION RULES:
1. **Scan systematically**: Look at all areas of the plate/image
2. **Identify layers**: Check for ingredients that might be layered or mixed
3. **Consider garnishes**: Include herbs, spices, small vegetables
4. **Separate components**: Treat each distinct food item as separate ingredient
5. **Minimum threshold**: Always try to identify at least 2-3 ingredients unless it's genuinely a single-ingredient meal

QUALITY ASSURANCE:
- If only 1 ingredient detected, double-check the image for missed components
- Verify that nutrition values are realistic and precise
- Ensure all visible food components are accounted for
- Cross-reference nutrition values with standard food databases
```

## Implementation Notes

### Client-Side Improvements (Already Implemented)
1. **Image Quality Validation**: Ensure images are not too small (>100KB)
2. **Detection Logging**: Log when only 1 ingredient is detected vs multiple
3. **Precision Preservation**: Fixed numeric value extraction to preserve decimal places
4. **Error Handling**: Better error messages for single-ingredient detection

### Server-Side Requirements
1. **Update the OpenAI API call** in your server code to use the improved prompt above
2. **Validate responses** to ensure multiple ingredients when expected
3. **Implement retry logic** if only 1 ingredient is detected for complex meals
4. **Add response validation** to ensure precision requirements are met

### Expected Results After Implementation
- **Complex meals**: Should detect 3-6 ingredients typically
- **Simple meals**: May legitimately have 1-2 ingredients
- **Precision**: All values should have decimal precision (e.g., 23.7g not 24g)
- **Comprehensive nutrition**: Full vitamin, mineral, and other nutrient data

### Testing Guidelines
Test with various meal types:
- **Multi-component meals**: Stir-fries, salads, complete dinners
- **Simple meals**: Single protein + vegetable
- **Complex dishes**: Casseroles, mixed dishes, ethnic cuisines
- **Plated meals**: Multiple distinct items on one plate

### Monitoring Success
- Track ingredient detection rate (avg ingredients per meal)
- Monitor precision of nutrition values (decimal places preserved)
- Validate comprehensive nutrient data inclusion
- Check user satisfaction with detection accuracy 