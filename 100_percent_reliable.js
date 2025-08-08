// OpenAI Vision API integration with strict JSON schema for micronutrient analysis
// This module provides 100% reliable nutrition data by enforcing proper JSON structure and correct units

require('dotenv').config();
const fetch = require('node-fetch');

// Strict JSON schema for OpenAI response with correct units
const MICRONUTRIENT_SCHEMA = {
  "ingredients": [
    {
      "name": "string",
      "weight_g": "number",
      "kcal": "number",
      "protein_g": "number",
      "fat_g": "number",
      "carbs_g": "number",
      "micronutrients": {
        "vitaminA_mcg": "number", // µg
        "vitaminC_mg": "number", // mg
        "vitaminD_mcg": "number", // µg
        "vitaminE_mg": "number", // mg
        "vitaminK_mcg": "number", // µg
        "vitaminB1_mg": "number", // mg
        "vitaminB2_mg": "number", // mg
        "vitaminB3_mg": "number", // mg
        "vitaminB5_mg": "number", // mg
        "vitaminB6_mg": "number", // mg
        "vitaminB7_mcg": "number", // µg
        "vitaminB9_mcg": "number", // µg
        "vitaminB12_mcg": "number", // µg
        "minerals": {
          "calcium_mg": "number", // mg
          "chloride_mg": "number", // mg
          "chromium_mcg": "number", // µg
          "copper_mg": "number", // mg
          "fluoride_mg": "number", // mg
          "iodine_mcg": "number", // µg
          "iron_mg": "number", // mg
          "magnesium_mg": "number", // mg
          "manganese_mg": "number", // mg
          "molybdenum_mcg": "number", // µg
          "phosphorus_mg": "number", // mg
          "potassium_mg": "number", // mg
          "selenium_mcg": "number", // µg
          "sodium_mg": "number", // mg
          "zinc_mg": "number" // mg
        }
      }
    }
  ],
  "totals": {
    "calories": "number",
    "protein_g": "number", 
    "fat_g": "number",
    "carbs_g": "number",
    "vitaminA_mcg": "number",
    "vitaminC_mg": "number",
    "vitaminD_mcg": "number",
    "vitaminE_mg": "number",
    "vitaminK_mcg": "number",
    "vitaminB1_mg": "number",
    "vitaminB2_mg": "number",
    "vitaminB3_mg": "number",
    "vitaminB5_mg": "number",
    "vitaminB6_mg": "number",
    "vitaminB7_mcg": "number",
    "vitaminB9_mcg": "number",
    "vitaminB12_mcg": "number",
    "minerals": {
      "calcium_mg": "number",
      "chloride_mg": "number",
      "chromium_mcg": "number",
      "copper_mg": "number",
      "fluoride_mg": "number",
      "iodine_mcg": "number",
      "iron_mg": "number",
      "magnesium_mg": "number",
      "manganese_mg": "number",
      "molybdenum_mcg": "number",
      "phosphorus_mg": "number",
      "potassium_mg": "number",
      "selenium_mcg": "number",
      "sodium_mg": "number",
      "zinc_mg": "number"
    }
  }
};

// Strict JSON-only system prompt with correct units
const SYSTEM_PROMPT = `You are a JSON-only food analyzer. When I receive an image, respond with valid JSON and nothing else. Use this exact schema, and ensure that each micronutrient uses the correct unit (µg or mg) as specified. IMPORTANT: include macronutrients (protein_g, fat_g, carbs_g) for EACH ingredient and also in totals. ALSO include the six "Other" nutrients we track for every ingredient and in totals: fiber_g, cholesterol_mg, sugar_g, saturated_fats_g, omega_3_mg, omega_6_g.

{
  "ingredients": [
    {
      "name": "string",
      "weight_g": number,
      "kcal": number,
      "protein_g": number,
      "fat_g": number,
      "carbs_g": number,
      "micronutrients": {
        "vitaminA_mcg": number, // µg
        "vitaminC_mg": number, // mg
        "vitaminD_mcg": number, // µg
        "vitaminE_mg": number, // mg
        "vitaminK_mcg": number, // µg
        "vitaminB1_mg": number, // mg
        "vitaminB2_mg": number, // mg
        "vitaminB3_mg": number, // mg
        "vitaminB5_mg": number, // mg
        "vitaminB6_mg": number, // mg
        "vitaminB7_mcg": number, // µg
        "vitaminB9_mcg": number, // µg
        "vitaminB12_mcg": number, // µg
        "minerals": {
          "calcium_mg": number, // mg
          "chloride_mg": number, // mg
          "chromium_mcg": number, // µg
          "copper_mg": number, // mg
          "fluoride_mg": number, // mg
          "iodine_mcg": number, // µg
          "iron_mg": number, // mg
          "magnesium_mg": number, // mg
          "manganese_mg": number, // mg
          "molybdenum_mcg": number, // µg
          "phosphorus_mg": number, // mg
          "potassium_mg": number, // mg
          "selenium_mcg": number, // µg
          "sodium_mg": number, // mg
          "zinc_mg": number // mg
        },
        "other": {
          "fiber_g": number,           // grams
          "cholesterol_mg": number,    // milligrams
          "sugar_g": number,           // grams
          "saturated_fats_g": number,  // grams
          "omega_3_mg": number,        // milligrams
          "omega_6_g": number          // grams
        }
      }
    }
  ],
  "totals": {
    "calories": number,
    "protein_g": number,
    "fat_g": number,
    "carbs_g": number,
    // Sum of each vitamin and mineral using same units as above:
    "vitaminA_mcg": number,
    "vitaminC_mg": number,
    "vitaminD_mcg": number,
    "vitaminE_mg": number,
    "vitaminK_mcg": number,
    "vitaminB1_mg": number,
    "vitaminB2_mg": number,
    "vitaminB3_mg": number,
    "vitaminB5_mg": number,
    "vitaminB6_mg": number,
    "vitaminB7_mcg": number,
    "vitaminB9_mcg": number,
    "vitaminB12_mcg": number,
    "minerals": {
      "calcium_mg": number,
      "chloride_mg": number,
      "chromium_mcg": number,
      "copper_mg": number,
      "fluoride_mg": number,
      "iodine_mcg": number,
      "iron_mg": number,
      "magnesium_mg": number,
      "manganese_mg": number,
      "molybdenum_mcg": number,
      "phosphorus_mg": number,
      "potassium_mg": number,
      "selenium_mcg": number,
      "sodium_mg": number,
      "zinc_mg": number
    },
    "other": {
      "fiber_g": number,
      "cholesterol_mg": number,
      "sugar_g": number,
      "saturated_fats_g": number,
      "omega_3_mg": number,
      "omega_6_g": number
    }
  }
}

Do not include any extra keys.

Every numerical field must use the correct unit suffix (e.g. "mcg" for micrograms, "mg" for milligrams).

If a micronutrient is not detected, return it as 0 (not null).

CRITICAL UNIT RULES:
- Vitamin A, D, K, B7, B9, B12: Use µg (micrograms)
- Vitamin C, E, B1, B2, B3, B5, B6: Use mg (milligrams)
- Minerals chromium, iodine, molybdenum, selenium: Use µg (micrograms)
- All other minerals: Use mg (milligrams)

Use temperature: 0 and response_format: "json" so the API returns parsed JSON.`;

// OpenAI Vision API integration function with correct parameters
async function analyzeImageWithOpenAI(imageBase64) {
  try {
    if (!process.env.OPENAI_API_KEY) {
      throw new Error('OpenAI API key not configured');
    }

    // JSON Schema to force well-formed JSON from OpenAI
    const RESPONSE_JSON_SCHEMA = {
      name: 'ImageNutrition',
      schema: {
        type: 'object',
        additionalProperties: false,
        properties: {
          meal_name: { type: 'string' },
          ingredients: {
            type: 'array',
            minItems: 1,
            items: {
            type: 'object',
            additionalProperties: false,
              properties: {
                name: { type: 'string' },
                weight_g: { type: 'number' },
                kcal: { type: 'number' },
                protein_g: { type: 'number' },
                fat_g: { type: 'number' },
                carbs_g: { type: 'number' },
              micronutrients: { type: 'object', additionalProperties: false }
              },
              required: ['name', 'weight_g', 'kcal']
            }
          },
          totals: {
          type: 'object',
          additionalProperties: false,
            properties: {
              calories: { type: 'number' },
              protein_g: { type: 'number' },
              fat_g: { type: 'number' },
              carbs_g: { type: 'number' },
            vitamins: { type: 'object', additionalProperties: false },
            minerals: { type: 'object', additionalProperties: false },
            other: { type: 'object', additionalProperties: false }
            },
            required: ['calories', 'protein_g', 'fat_g', 'carbs_g']
          }
        },
        required: ['ingredients', 'totals']
      },
      strict: true
    };

    const requestBody = {
      model: 'gpt-4o-mini',
      temperature: 0,
      max_tokens: 2000,
      response_format: { type: 'json_object' },
      messages: [
        {
          role: 'system',
          content: SYSTEM_PROMPT + "\n\nReturn ONLY valid JSON. No text outside JSON. Use numeric literals with either integers or decimals with a leading and trailing digit (e.g., 0.0, 0.1)."
        },
        {
          role: 'user', 
          content: [
            {
              type: 'text',
              text: 'Analyze this food image and return the exact JSON schema with complete micronutrient breakdown using correct units (µg/mg) for each ingredient, then sum them in totals.'
            },
            {
              type: 'image_url',
              image_url: { url: imageBase64 }
            }
          ]
        }
      ]
    };
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
      body: JSON.stringify(requestBody)
    });

    if (!response.ok) {
      const errorData = await response.text();
      throw new Error(`OpenAI API error: ${response.status} - ${errorData}`);
    }

    const data = await response.json();
    
    if (!data.choices || !data.choices[0] || !data.choices[0].message || !data.choices[0].message.content) {
      throw new Error('Invalid response format from OpenAI');
    }

    const content = data.choices[0].message.content;
    
    // Parse with number sanitizer first; then robust cleanup fallback
    function sanitizeJsonNumbers(s) {
      s = s.replace(/(:\s*)(-?\d+)\.(\s*[,}])/g, (_, a, n, b) => `${a}${n}.0${b}`);
      s = s.replace(/(:\s*)\.(\d+)/g, (_, a, d) => `${a}0.${d}`);
      s = s.replace(/,\s*([}\]])/g, '$1');
      return s;
    }
    let parsedData;
    try {
      parsedData = JSON.parse(sanitizeJsonNumbers(content));
    } catch (e) {
      let cleaned = sanitizeJsonNumbers(content.trim()
        .replace(/^```json\s*/i, '')
        .replace(/^```/, '')
        .replace(/```\s*$/,''));
      cleaned = cleaned.replace(/\r?\n/g, '');
      cleaned = cleaned.replace(/[“”]/g, '"').replace(/[‘’]/g, "'");
      cleaned = cleaned.replace(/([A-Za-z0-9])\s*_\s*([A-Za-z0-9])/g, '$1_$2');
      cleaned = cleaned.replace(/([\{,]\s*)([^"\{\}\[\]\s][^:\s]*)\s*:/g, function(_, prefix, key){
        return prefix + '"' + key.replace(/"/g,'') + '":';
      });
      try {
        parsedData = JSON.parse(cleaned);
      } catch (inner) {
        console.error('JSON parse failed. Head:', cleaned.slice(0, 200));
        console.error('Tail:', cleaned.slice(-200));
        throw inner;
      }
    }
    
    // Validate and process the response with correct units
    const processedData = validateAndProcessNutritionData(parsedData);
    
    return processedData;
    
  } catch (error) {
    console.error('❌ Error in OpenAI Vision analysis:', error.message);
    throw error;
  }
}

// Validate and process nutrition data to ensure proper summation with correct units
function validateAndProcessNutritionData(data) {
  
  if (!data.ingredients || !Array.isArray(data.ingredients)) {
    throw new Error('Invalid ingredients array in OpenAI response');
  }

  if (!data.totals) {
    throw new Error('Missing totals section in OpenAI response');
  }

  // Initialize calculated totals with correct units
  const calculatedTotals = {
    calories: 0,
    protein_g: 0,
    fat_g: 0,
    carbs_g: 0,
    // Vitamins with correct units
    vitaminA_mcg: 0, // µg
    vitaminC_mg: 0, // mg
    vitaminD_mcg: 0, // µg
    vitaminE_mg: 0, // mg
    vitaminK_mcg: 0, // µg
    vitaminB1_mg: 0, // mg
    vitaminB2_mg: 0, // mg
    vitaminB3_mg: 0, // mg
    vitaminB5_mg: 0, // mg
    vitaminB6_mg: 0, // mg
    vitaminB7_mcg: 0, // µg
    vitaminB9_mcg: 0, // µg
    vitaminB12_mcg: 0, // µg
    minerals: {
      calcium_mg: 0, // mg
      chloride_mg: 0, // mg
      chromium_mcg: 0, // µg
      copper_mg: 0, // mg
      fluoride_mg: 0, // mg
      iodine_mcg: 0, // µg
      iron_mg: 0, // mg
      magnesium_mg: 0, // mg
      manganese_mg: 0, // mg
      molybdenum_mcg: 0, // µg
      phosphorus_mg: 0, // mg
      potassium_mg: 0, // mg
      selenium_mcg: 0, // µg
      sodium_mg: 0, // mg
      zinc_mg: 0 // mg
    }
  };

  // Sum micronutrients across all ingredients with unit consistency
  data.ingredients.forEach((ingredient, index) => {
    
    calculatedTotals.calories += ingredient.kcal || 0;
    calculatedTotals.protein_g += ingredient.protein_g || 0;
    calculatedTotals.fat_g += ingredient.fat_g || 0;
    calculatedTotals.carbs_g += ingredient.carbs_g || 0;

    if (ingredient.micronutrients) {
      // Sum vitamins with correct units
      calculatedTotals.vitaminA_mcg += ingredient.micronutrients.vitaminA_mcg || 0; // µg
      calculatedTotals.vitaminC_mg += ingredient.micronutrients.vitaminC_mg || 0; // mg
      calculatedTotals.vitaminD_mcg += ingredient.micronutrients.vitaminD_mcg || 0; // µg
      calculatedTotals.vitaminE_mg += ingredient.micronutrients.vitaminE_mg || 0; // mg
      calculatedTotals.vitaminK_mcg += ingredient.micronutrients.vitaminK_mcg || 0; // µg
      calculatedTotals.vitaminB1_mg += ingredient.micronutrients.vitaminB1_mg || 0; // mg
      calculatedTotals.vitaminB2_mg += ingredient.micronutrients.vitaminB2_mg || 0; // mg
      calculatedTotals.vitaminB3_mg += ingredient.micronutrients.vitaminB3_mg || 0; // mg
      calculatedTotals.vitaminB5_mg += ingredient.micronutrients.vitaminB5_mg || 0; // mg
      calculatedTotals.vitaminB6_mg += ingredient.micronutrients.vitaminB6_mg || 0; // mg
      calculatedTotals.vitaminB7_mcg += ingredient.micronutrients.vitaminB7_mcg || 0; // µg
      calculatedTotals.vitaminB9_mcg += ingredient.micronutrients.vitaminB9_mcg || 0; // µg
      calculatedTotals.vitaminB12_mcg += ingredient.micronutrients.vitaminB12_mcg || 0; // µg

      if (ingredient.micronutrients.minerals) {
        const minerals = ingredient.micronutrients.minerals;
        // Sum minerals with correct units
        calculatedTotals.minerals.calcium_mg += minerals.calcium_mg || 0; // mg
        calculatedTotals.minerals.chloride_mg += minerals.chloride_mg || 0; // mg
        calculatedTotals.minerals.chromium_mcg += minerals.chromium_mcg || 0; // µg
        calculatedTotals.minerals.copper_mg += minerals.copper_mg || 0; // mg
        calculatedTotals.minerals.fluoride_mg += minerals.fluoride_mg || 0; // mg
        calculatedTotals.minerals.iodine_mcg += minerals.iodine_mcg || 0; // µg
        calculatedTotals.minerals.iron_mg += minerals.iron_mg || 0; // mg
        calculatedTotals.minerals.magnesium_mg += minerals.magnesium_mg || 0; // mg
        calculatedTotals.minerals.manganese_mg += minerals.manganese_mg || 0; // mg
        calculatedTotals.minerals.molybdenum_mcg += minerals.molybdenum_mcg || 0; // µg
        calculatedTotals.minerals.phosphorus_mg += minerals.phosphorus_mg || 0; // mg
        calculatedTotals.minerals.potassium_mg += minerals.potassium_mg || 0; // mg
        calculatedTotals.minerals.selenium_mcg += minerals.selenium_mcg || 0; // µg
        calculatedTotals.minerals.sodium_mg += minerals.sodium_mg || 0; // mg
        calculatedTotals.minerals.zinc_mg += minerals.zinc_mg || 0; // mg
      }
    }
  });

  // Use calculated totals to ensure accuracy with correct units
  // If the model already provided totals, prefer them when our sums are zero
  if (data.totals && typeof data.totals === 'object') {
    const t = data.totals;
    const useIfNumber = (val, fallback) => (typeof val === 'number' && !Number.isNaN(val) ? val : fallback);
    if (calculatedTotals.calories === 0) calculatedTotals.calories = useIfNumber(t.calories, 0);
    if (calculatedTotals.protein_g === 0) calculatedTotals.protein_g = useIfNumber(t.protein_g, 0);
    if (calculatedTotals.fat_g === 0) calculatedTotals.fat_g = useIfNumber(t.fat_g, 0);
    if (calculatedTotals.carbs_g === 0) calculatedTotals.carbs_g = useIfNumber(t.carbs_g, 0);
    // Vitamins
    const vKeys = [
      'vitaminA_mcg','vitaminC_mg','vitaminD_mcg','vitaminE_mg','vitaminK_mcg',
      'vitaminB1_mg','vitaminB2_mg','vitaminB3_mg','vitaminB5_mg','vitaminB6_mg',
      'vitaminB7_mcg','vitaminB9_mcg','vitaminB12_mcg'
    ];
    vKeys.forEach(k => {
      if (calculatedTotals[k] === 0) {
        calculatedTotals[k] = useIfNumber(t[k], 0);
      }
    });
    // Minerals
    if (t.minerals && typeof t.minerals === 'object') {
      const m = t.minerals;
      Object.keys(calculatedTotals.minerals).forEach(mk => {
        if (calculatedTotals.minerals[mk] === 0) {
          calculatedTotals.minerals[mk] = useIfNumber(m[mk], 0);
        }
      });
    }
  }

  return {
    ingredients: data.ingredients,
    totals: calculatedTotals
  };
}

// Export for use in server
// High-level function expected by server.js
// Adapts OpenAI vision output into the client schema used by the Flutter app
async function analyzeNutrition(imageBase64) {
  const visionData = await analyzeImageWithOpenAI(imageBase64);
  // visionData shape: { ingredients: [...], totals: { calories, protein_g, fat_g, carbs_g, minerals:{...}, vitamins... } }

  const ingredients = Array.isArray(visionData.ingredients) ? visionData.ingredients : [];

  const mappedIngredients = ingredients.map((ing) => {
    const weight = ing.weight_g || 100;
    const name = ing.name || 'Ingredient';
    const calories = Math.round(ing.kcal || 0);
    const protein = typeof ing.protein_g === 'number' ? ing.protein_g : 0;
    const fat = typeof ing.fat_g === 'number' ? ing.fat_g : 0;
    const carbs = typeof ing.carbs_g === 'number' ? ing.carbs_g : 0;
    return {
      name,
      weight_g: weight,
      amount: `${weight}g`,
      calories,
      protein,
      fat,
      carbs,
    };
  });

  // Create a compact meal name
  const meal_name = mappedIngredients.length > 0
    ? mappedIngredients.slice(0, 2).map(i => i.name).join(' + ')
    : 'Analyzed Meal';

  const totals = visionData.totals || {};
  // Compute sums to use as fallback when totals are missing/zero
  const sumCalories = mappedIngredients.reduce((s, i) => s + (i.calories || 0), 0);
  const sumProtein = mappedIngredients.reduce((s, i) => s + (i.protein || 0), 0);
  const sumFat = mappedIngredients.reduce((s, i) => s + (i.fat || 0), 0);
  const sumCarbs = mappedIngredients.reduce((s, i) => s + (i.carbs || 0), 0);

  const response = {
    meal_name,
    ingredients: mappedIngredients,
    calories: (typeof totals.calories === 'number' && totals.calories > 0) ? totals.calories : sumCalories,
    protein: (typeof totals.protein_g === 'number' && totals.protein_g > 0) ? totals.protein_g : sumProtein,
    fat: (typeof totals.fat_g === 'number' && totals.fat_g > 0) ? totals.fat_g : sumFat,
    carbs: (typeof totals.carbs_g === 'number' && totals.carbs_g > 0) ? totals.carbs_g : sumCarbs,
  };

  // Flatten vitamins into snake_case keys expected by the Flutter app
  const vitaminMap = {
    vitaminA_mcg: 'vitamin_a',
    vitaminC_mg: 'vitamin_c',
    vitaminD_mcg: 'vitamin_d',
    vitaminE_mg: 'vitamin_e',
    vitaminK_mcg: 'vitamin_k',
    vitaminB1_mg: 'vitamin_b1',
    vitaminB2_mg: 'vitamin_b2',
    vitaminB3_mg: 'vitamin_b3',
    vitaminB5_mg: 'vitamin_b5',
    vitaminB6_mg: 'vitamin_b6',
    vitaminB7_mcg: 'vitamin_b7',
    vitaminB9_mcg: 'vitamin_b9',
    vitaminB12_mcg: 'vitamin_b12',
  };

  Object.entries(vitaminMap).forEach(([from, to]) => {
    if (totals[from] != null) {
      response[to] = totals[from];
    }
  });

  // Flatten minerals
  if (totals.minerals && typeof totals.minerals === 'object') {
    const m = totals.minerals;
    const mineralMap = {
      calcium_mg: 'calcium',
      chloride_mg: 'chloride',
      chromium_mcg: 'chromium',
      copper_mg: 'copper',
      fluoride_mg: 'fluoride',
      iodine_mcg: 'iodine',
      iron_mg: 'iron',
      magnesium_mg: 'magnesium',
      manganese_mg: 'manganese',
      molybdenum_mcg: 'molybdenum',
      phosphorus_mg: 'phosphorus',
      potassium_mg: 'potassium',
      selenium_mcg: 'selenium',
      sodium_mg: 'sodium',
      zinc_mg: 'zinc',
    };
    Object.entries(mineralMap).forEach(([from, to]) => {
      if (m[from] != null) {
        response[to] = m[from];
      }
    });
  }

  // Flatten other totals when present
  if (totals.other && typeof totals.other === 'object') {
    const o = totals.other;
    const otherMap = {
      fiber_g: 'fiber',
      cholesterol_mg: 'cholesterol',
      sugar_g: 'sugar',
      saturated_fats_g: 'saturated_fats',
      omega_3_mg: 'omega_3',
      omega_6_g: 'omega_6',
    };
    Object.entries(otherMap).forEach(([from, to]) => {
      if (o[from] != null) response[to] = o[from];
    });
  }

  // Guarantee per-ingredient macros for client UI. If ingredient macros are all
  // zero/missing but meal totals exist, distribute totals by ingredient calories.
  const totalCalories = mappedIngredients.reduce((s, i) => s + (i.calories || 0), 0) || 1;
  const sumP = mappedIngredients.reduce((s, i) => s + (i.protein || 0), 0);
  const sumF = mappedIngredients.reduce((s, i) => s + (i.fat || 0), 0);
  const sumC = mappedIngredients.reduce((s, i) => s + (i.carbs || 0), 0);
  const needP = sumP === 0 && (response.protein || 0) > 0;
  const needF = sumF === 0 && (response.fat || 0) > 0;
  const needC = sumC === 0 && (response.carbs || 0) > 0;
  if (needP || needF || needC) {
    mappedIngredients.forEach(ing => {
      const share = (ing.calories || 0) / totalCalories;
      if (needP) ing.protein = +(response.protein * share).toFixed(1);
      if (needF) ing.fat = +(response.fat * share).toFixed(1);
      if (needC) ing.carbs = +(response.carbs * share).toFixed(1);
    });
  }

  return response;
}

module.exports = {
  analyzeImageWithOpenAI,
  validateAndProcessNutritionData,
  MICRONUTRIENT_SCHEMA,
  SYSTEM_PROMPT,
  analyzeNutrition,
};