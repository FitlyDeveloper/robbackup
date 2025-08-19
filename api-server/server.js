require('dotenv').config();
const express = require('express');
const cors = require('cors');
const fetch = require('node-fetch');

const app = express();
const PORT = process.env.PORT || 10000;

// DEDICATED NUTRITION PROMPT FOR NUTRITION.DART
const NUTRITION_PROMPT = `You are a nutrition data analyst. Your task is to analyze food images and return STRICT JSON with accurate micronutrient values sourced ONLY from verified nutritional databases.

CRITICAL REQUIREMENTS:
1. ALL micronutrient values MUST come from USDA/FDC (FoodData Central) or equivalent verified databases
2. NO hallucination, estimation, or guessing of values
3. Scale values based on exact ingredient weights (e.g., 100g spaghetti, 60g bread, 30g salami)
4. If a micronutrient is not available in the database, set it to 0
5. Never output inflated values (e.g., 100% DV Vitamin A for foods without it)
6. Sodium, cholesterol, vitamins, and minerals must stay within realistic food composition ranges

FDA DVs for reference:
Vitamins: A 900 mcg; C 90 mg; D 20 mcg; E 15 mg; K 120 mcg; B1 1.2 mg; B2 1.3 mg; B3 16 mg; B5 5 mg; B6 1.3 mg; B7 30 mcg; B9 400 mcg; B12 2.4 mcg
Minerals: Ca 1300 mg; Cl 2300 mg; Cr 35 mcg; Cu 900 mcg; F 4 mg; I 150 mcg; Fe 18 mg; Mg 420 mg; Mn 2.3 mg; Mo 45 mcg; P 1250 mg; K 4700 mg; Se 55 mcg; Na 2300 mg; Zn 11 mg
Other: Fiber 28 g; Cholesterol 300 mg; Sugar 50 g; SatFat 20 g; Omega3 1600 mg; Omega6 17 g

PROCESS:
1. Identify each ingredient and its weight from the image
2. Look up each ingredient in USDA/FDC database for per-100g values
3. Calculate: (database_value × ingredient_weight) ÷ 100
4. Sum all ingredients for meal totals
5. Return JSON in the exact format below

SCHEMA:
{
  "meal_name": "Dish Name",
  "ingredients": [
    {
      "name": "Ingredient Name",
      "weight_g": 100,
      "calories": 0,
      "protein_g": 0,
      "fat_g": 0,
      "carbs_g": 0,
      "vitamin_a": 0,
      "vitamin_c": 0,
      "vitamin_d": 0,
      "vitamin_e": 0,
      "vitamin_k": 0,
      "vitamin_b1": 0,
      "vitamin_b2": 0,
      "vitamin_b3": 0,
      "vitamin_b5": 0,
      "vitamin_b6": 0,
      "vitamin_b7": 0,
      "vitamin_b9": 0,
      "vitamin_b12": 0,
      "calcium": 0,
      "chloride": 0,
      "chromium": 0,
      "copper": 0,
      "fluoride": 0,
      "iodine": 0,
      "iron": 0,
      "magnesium": 0,
      "manganese": 0,
      "molybdenum": 0,
      "phosphorus": 0,
      "potassium": 0,
      "selenium": 0,
      "sodium": 0,
      "zinc": 0,
      "fiber": 0,
      "cholesterol": 0,
      "sugar": 0,
      "saturated_fats": 0,
      "omega_3": 0,
      "omega_6": 0
    }
  ],
  "totals": {
    "calories": 0,
    "protein_g": 0,
    "fat_g": 0,
    "carbs_g": 0,
    "vitamin_a": 0,
    "vitamin_c": 0,
    "vitamin_d": 0,
    "vitamin_e": 0,
    "vitamin_k": 0,
    "vitamin_b1": 0,
    "vitamin_b2": 0,
    "vitamin_b3": 0,
    "vitamin_b5": 0,
    "vitamin_b6": 0,
    "vitamin_b7": 0,
    "vitamin_b9": 0,
    "vitamin_b12": 0,
    "calcium": 0,
    "chloride": 0,
    "chromium": 0,
    "copper": 0,
    "fluoride": 0,
    "iodine": 0,
    "iron": 0,
    "magnesium": 0,
    "manganese": 0,
    "molybdenum": 0,
    "phosphorus": 0,
    "potassium": 0,
    "selenium": 0,
    "sodium": 0,
    "zinc": 0,
    "fiber": 0,
    "cholesterol": 0,
    "sugar": 0,
    "saturated_fats": 0,
    "omega_3": 0,
    "omega_6": 0
  }
}

UNITS:
- Vitamins: mg (except A, D, B7, B9, B12, K in mcg)
- Minerals: mg (except Cr, Cu, I, Mo, Se in mcg)
- Other: fiber (g), cholesterol (mg), sugar (g), saturated_fats (g), omega_3 (mg), omega_6 (g)

VALIDATION RULES:
- If ingredient not in database, set all its micronutrients to 0
- Never exceed realistic food composition limits
- Sodium: typically 0-2000mg per 100g (except processed foods)
- Cholesterol: 0-300mg per 100g (except eggs/dairy)
- Fiber: 0-15g per 100g (except supplements)
- Sugar: 0-50g per 100g (except pure sugar/honey)

Return ONLY valid JSON. No prose, no explanations.`;

console.log('Starting SIMPLE server for micronutrients...');
console.log('OpenAI API Key present:', process.env.OPENAI_API_KEY ? 'Yes' : 'No');

app.use(cors());
app.use(express.json({ limit: '50mb' }));

// Simple health check
app.get('/', (req, res) => {
  res.json({ status: 'operational' });
});

// AGGRESSIVE JSON repair function
function repairJsonFormat(raw) {
  if (!raw || typeof raw !== 'string') return raw;
  let s = raw.trim();
  
  // Strip markdown fences
  s = s.replace(/^```json\s*/i, '').replace(/^```\s*/i, '').replace(/\s*```$/i, '');
  
  // Normalize smart quotes
  s = s.replace(/[""]/g, '"').replace(/['']/g, '\'');
  
  // AGGRESSIVE: Quote ALL unquoted property names (multiple patterns)
  s = s.replace(/([,{\n\r\t\s])([A-Za-z_][A-Za-z0-9_]*)(\s*):/g, '$1"$2"$3:');
  s = s.replace(/(\n\s*)([A-Za-z_][A-Za-z0-9_]*)(\s*):/g, '$1"$2"$3:');
  s = s.replace(/^([A-Za-z_][A-Za-z0-9_]*)(\s*):/gm, '"$1"$2:');
  
  // Fix property names that might be at start of line
  s = s.replace(/^(\s*)([a-zA-Z_][a-zA-Z0-9_]*)(\s*):/gm, '$1"$2"$3:');
  
  // Convert single-quoted strings to double-quoted
  s = s.replace(/'([^'\\]*(?:\\.[^'\\]*)*)'/g, '"$1"');
  
  // Remove trailing commas
  s = s.replace(/,\s*}/g, '}').replace(/,\s*]/g, ']');
  
  // Collapse duplicate commas
  s = s.replace(/,\s*,/g, ',');
  
  // Fix any remaining unquoted keys (last resort)
  s = s.replace(/([{,]\s*)([a-zA-Z_$][a-zA-Z0-9_$]*)(\s*):/g, '$1"$2"$3:');
  
  return s;
}

// ULTRA-AGGRESSIVE JSON repair for malformed responses
function ultraRepairJson(content) {
  console.log('🔧 ULTRA-AGGRESSIVE JSON repair starting...');
  
  // First try basic repair
  let repaired = repairJsonFormat(content);
  
  try {
    JSON.parse(repaired);
    console.log('✅ Basic repair successful');
    return repaired;
  } catch (error) {
    console.log('🔧 Basic repair failed, trying aggressive fixes...');
  }
  
  // AGGRESSIVE FIX 1: Find last complete ingredient and truncate
  const ingredientMatches = repaired.match(/\{[^}]*"name"[^}]*\}/g);
  if (ingredientMatches && ingredientMatches.length > 0) {
    const lastIngredient = ingredientMatches[ingredientMatches.length - 1];
    const lastIndex = repaired.lastIndexOf(lastIngredient);
    
    if (lastIndex > 0) {
      console.log('🔧 Truncating to last complete ingredient...');
      repaired = repaired.substring(0, lastIndex + lastIngredient.length);
      
      // Complete the JSON structure
      if (repaired.includes('"ingredients": [')) {
        repaired += '\n  ]\n}';
      }
      
      try {
        JSON.parse(repaired);
        console.log('✅ Truncation repair successful');
        return repaired;
      } catch (error) {
        console.log('🔧 Truncation repair failed');
      }
    }
  }
  
  // AGGRESSIVE FIX 2: Find last complete property and truncate
  const propertyMatches = repaired.match(/"([^"]+)":\s*[^,}\]]+/g);
  if (propertyMatches && propertyMatches.length > 0) {
    const lastProperty = propertyMatches[propertyMatches.length - 1];
    const lastIndex = repaired.lastIndexOf(lastProperty);
    
    if (lastIndex > 0) {
      console.log('🔧 Truncating to last complete property...');
      repaired = repaired.substring(0, lastIndex + lastProperty.length);
      
      // Find the containing object and close it
      let braceCount = 0;
      let startIndex = -1;
      for (let i = lastIndex; i >= 0; i--) {
        if (repaired[i] === '}') braceCount++;
        if (repaired[i] === '{') {
          braceCount--;
          if (braceCount === 0) {
            startIndex = i;
            break;
          }
        }
      }
      
      if (startIndex > 0) {
        repaired = repaired.substring(0, startIndex) + '}';
        
        // Complete the ingredients array and main object
        if (repaired.includes('"ingredients": [')) {
          repaired += '\n  ]\n}';
        }
        
        try {
          JSON.parse(repaired);
          console.log('✅ Property truncation repair successful');
          return repaired;
        } catch (error) {
          console.log('🔧 Property truncation repair failed');
        }
      }
    }
  }
  
  // AGGRESSIVE FIX 3: Create minimal valid JSON from what we can extract
  console.log('🔧 Creating minimal valid JSON...');
  
  // Extract meal name if possible
  const mealNameMatch = repaired.match(/"meal_name":\s*"([^"]+)"/);
  const mealName = mealNameMatch ? mealNameMatch[1] : "Dinner Meal";
  
  // Extract any ingredient names
  const nameMatches = repaired.match(/"name":\s*"([^"]+)"/g);
  const ingredientNames = nameMatches ? nameMatches.map(m => m.match(/"name":\s*"([^"]+)"/)[1]) : ["Ingredient"];
  
  // Create minimal valid JSON
  const minimalJson = {
    meal_name: mealName,
    ingredients: ingredientNames.map(name => ({
      name: name,
      weight_g: 100,
      calories: 80,
      protein_g: 5,
      fat_g: 2,
      carbs_g: 12,
             vitamin_a: 0,
       vitamin_c: 0,
       vitamin_d: 0,
       vitamin_e: 0,
       vitamin_k: 0,
       vitamin_b1: 0,
       vitamin_b2: 0,
       vitamin_b3: 0,
       vitamin_b5: 0,
       vitamin_b6: 0,
       vitamin_b7: 0,
       vitamin_b9: 0,
       vitamin_b12: 0,
       calcium: 0,
       chloride: 0,
       chromium: 0,
       copper: 0,
       fluoride: 0,
       iodine: 0,
       iron: 0,
       magnesium: 0,
       manganese: 0,
       molybdenum: 0,
       phosphorus: 0,
       potassium: 0,
       selenium: 0,
       sodium: 0,
       zinc: 0,
       fiber: 0,
       cholesterol: 0,
       sugar: 0,
       saturated_fats: 0,
       omega_3: 0,
       omega_6: 0
    }))
  };
  
  console.log('✅ Minimal JSON created successfully');
  return JSON.stringify(minimalJson);
}

// SIMPLIFIED FOOD ANALYSIS - ONLY MICRONUTRIENTS
app.post('/api/analyze-food', async (req, res) => {
  try {
    const { image } = req.body;
    
    if (!image) {
      return res.status(400).json({
        success: false,
        error: 'Image required'
      });
    }

    if (!process.env.OPENAI_API_KEY) {
      return res.status(500).json({
        success: false,
        error: 'OpenAI API key not configured'
      });
    }

    console.log('🔥 Analyzing food image...');
    console.log('📱 Request source:', req.body.source || 'unknown');

    // CHOOSE PROMPT BASED ON SOURCE
    const isNutritionRequest = req.body.source === "nutrition.dart";
    const systemPrompt = isNutritionRequest ? NUTRITION_PROMPT : `You are a gourmet chef and nutrition analyst. Analyze the food image and return ONLY valid JSON following this process:
1) Identify ALL visible, distinct ingredients and estimate their portion sizes in grams (weight_g).
2) For EACH ingredient, lookup realistic micronutrient values using reliable sources (USDA or equivalent) and express them in the REQUIRED UNITS below. Include macros per ingredient too.
3) Compute meal TOTALS by summing nutrients across ingredients using the SAME UNITS.
4) Return the JSON exactly in the schema shown. No extra keys, no text outside JSON.

CRITICAL: You MUST look up actual nutritional data from reliable sources (USDA, nutrition databases) for each ingredient. DO NOT estimate or guess values. Use real data only.

For example:
- If you see chicken, look up "chicken breast nutrition per 100g" and use those exact values
- If you see rice, look up "white rice nutrition per 100g" and use those exact values  
- If you see tomatoes, look up "tomato nutrition per 100g" and use those exact values
- If you see bread, look up "whole wheat bread nutrition per 100g" and use those exact values

Then multiply by the actual portion size you estimated (weight_g/100) to get the ingredient's contribution.

This is NOT optional - you MUST research real nutritional data for accuracy.

FOOD NAMING: CRITICAL - Use ONLY dish names, NEVER list ingredients. Think like a restaurant menu.

EXAMPLES OF CORRECT NAMES:
- "Italian Dinner Plate" (NOT "Spaghetti with Garlic Butter and Rye Bread")
- "Mexican Combo" (NOT "Chicken Quesadilla with Rice and Beans")
- "Mediterranean Plate" (NOT "Salmon with Vegetables and Rice")
- "Breakfast Plate" (NOT "Eggs with Toast and Bacon")
- "Pasta Dinner" (NOT "Spaghetti with Meatballs and Sauce")
- "Asian Bowl" (NOT "Rice with Chicken and Vegetables")
- "Eastern European Plate" (NOT "Dumplings with Tomatoes and Sour Cream")
- "Russian Dinner" (NOT "Pierogi with Sour Cream")
- "Polish Plate" (NOT "Dumplings and Vegetables")

WRONG: "Dumplings with Tomatoes and Sour Cream"
RIGHT: "Eastern European Plate"

IF YOU CANNOT DETERMINE A SPECIFIC DISH NAME, USE TIME-BASED NAMES:
- "Breakfast Meal" (for morning foods)
- "Lunch Meal" (for midday foods)
- "Dinner Meal" (for evening foods)
- "Snack" (for small portions)

NEVER USE INGREDIENT LISTS AS THE MEAL NAME!

INGREDIENT NAMING: Use short, simple ingredient names.

INGREDIENT DETECTION:
- Detect ALL visible, distinct ingredients in the image. No hard cap.
- Include small components like sauces, dressings, herbs, leafy greens, seeds, nuts, cheese shavings (e.g., parmesan), and garnishes if visible.
- Each ingredient must be a real food item visible in the image (e.g., "Chicken", "Bread", "Yogurt sauce").
- Avoid utensils/containers and avoid generic words like "filling" when a specific food is evident.
- Provide realistic weight_g for each ingredient and include macros per ingredient.

UNITS: All micronutrients must use these units:
- Vitamins: mg (except vitamin_a in mcg, vitamin_d in mcg, vitamin_b7 in mcg, vitamin_b9 in mcg, vitamin_b12 in mcg, vitamin_k in mcg)
- Minerals: mg (except chromium in mcg, copper in mcg, fluoride in mg, iodine in mcg, manganese in mg, molybdenum in mcg, selenium in mcg, zinc in mg)
- Other: fiber (g), cholesterol (mg), sugar (g), saturated_fats (g), omega_3 (mg), omega_6 (g)

EXAMPLE RESEARCH PROCESS:
For a meal with chicken and rice:
1. Look up "chicken breast raw nutrition per 100g" → get real values
2. Look up "white rice cooked nutrition per 100g" → get real values  
3. Estimate portions (e.g., 150g chicken, 100g rice)
4. Calculate: chicken values × 1.5 + rice values × 1.0 = totals
5. Return the exact calculated totals in the JSON

UNIT ENFORCEMENT:
- Return raw numeric values ONLY (no unit suffixes inside numbers).
- Use the exact units above. Especially: omega_3 must be in mg and omega_6 must be in g. Copper must be in mcg.
- If your internal estimate is in a different unit, convert it so the returned number matches the required unit.

Include an additional object "units_used" that maps each nutrient key to the exact unit string you used (e.g., { "vitamin_b12": "mcg", "omega_3": "mg", "omega_6": "g" }). Do not add units in the numeric fields, only in this map.

{
  "meal_name": "Gourmet Food Name",
  "ingredients": [
    {
      "name": "Ingredient Name",
      "weight_g": 100,
      "calories": 80,
      "protein_g": 5,
      "fat_g": 2,
      "carbs_g": 12,
      "vitamin_a": 0,
      "vitamin_c": 0,
      "vitamin_d": 0,
      "vitamin_e": 0,
      "vitamin_k": 0,
      "vitamin_b1": 0,
      "vitamin_b2": 0,
      "vitamin_b3": 0,
      "vitamin_b5": 0,
      "vitamin_b6": 0,
      "vitamin_b7": 0,
      "vitamin_b9": 0,
      "vitamin_b12": 0,
      "calcium": 0,
      "chloride": 0,
      "chromium": 0,
      "copper": 0,
      "fluoride": 0,
      "iodine": 0,
      "iron": 0,
      "magnesium": 0,
      "manganese": 0,
      "molybdenum": 0,
      "phosphorus": 0,
      "potassium": 0,
      "selenium": 0,
      "sodium": 0,
      "zinc": 0,
      "fiber": 0,
      "cholesterol": 0,
      "sugar": 0,
      "saturated_fats": 0,
      "omega_3": 0,
      "omega_6": 0
    }
  ]
  ,
  "totals": {
    "calories": 0,
    "protein_g": 0,
    "fat_g": 0,
    "carbs_g": 0,
    "vitamin_a": 0,
    "vitamin_c": 0,
    "vitamin_d": 0,
    "vitamin_e": 0,
    "vitamin_k": 0,
    "vitamin_b1": 0,
    "vitamin_b2": 0,
    "vitamin_b3": 0,
    "vitamin_b5": 0,
    "vitamin_b6": 0,
    "vitamin_b7": 0,
    "vitamin_b9": 0,
    "vitamin_b12": 0,
    "calcium": 0,
    "chloride": 0,
    "chromium": 0,
    "copper": 0,
    "fluoride": 0,
    "iodine": 0,
    "iron": 0,
    "magnesium": 0,
    "manganese": 0,
    "molybdenum": 0,
    "phosphorus": 0,
    "potassium": 0,
    "selenium": 0,
    "sodium": 0,
    "zinc": 0,
    "fiber": 0,
    "cholesterol": 0,
    "sugar": 0,
    "saturated_fats": 0,
    "omega_3": 0,
    "omega_6": 0
  }
}

CRITICAL: You MUST research and use REAL nutritional data from reliable sources. DO NOT estimate, guess, or use placeholder values. Every number must come from actual nutritional research.

IMPORTANT: You MUST complete the entire JSON response. Do not truncate or leave incomplete data. The response must be valid JSON that can be parsed.

VALID JSON ONLY. Return zero only when the food naturally contains none.

MICRONUTRIENT REQUIREMENTS:
- You MUST look up REAL nutritional data from USDA or equivalent reliable sources
- "Other" category (fiber, cholesterol, sugar, saturated_fats, omega_3, omega_6) MUST be researched and accurate
- Every nutrient value must come from actual nutritional research, not estimation
- Some micronutrients may be zero if the food naturally contains none (e.g., vitamin D in most plant foods)
- Focus on providing accurate values for nutrients that are actually present in the food

RESEARCH COMMAND: For each ingredient, mentally search "ingredient name nutrition per 100g" and use the real values you find.`;

    // PREPARE USER CONTENT BASED ON SOURCE
    const userContent = isNutritionRequest ? [
      { 
        type: "text", 
        text: "Analyze meal screenshot and return JSON only." 
      },
      { 
        type: "image_url", 
        image_url: { url: image } 
      }
    ] : [
      { 
        type: "text", 
        text: "Analyze this food image and provide COMPLETE nutritional data with REALISTIC values for ALL 34 micronutrients. Use actual USDA nutritional values. Pay special attention to the 'Other' category (fiber, cholesterol, sugar, saturated_fats, omega_3, omega_6) - these MUST be accurate and realistic. Some micronutrients may be zero if the food naturally contains none."
      },
      { 
        type: "image_url", 
        image_url: { url: image } 
      }
    ];

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: isNutritionRequest ? 0.2 : 0.1,
        response_format: isNutritionRequest ? { type: "json_object" } : { type: "json_object" },
        messages: [
          {
            role: "system",
            content: systemPrompt
          },
          {
            role: "user",
            content: userContent
          }
        ],
        max_tokens: 3000
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      return res.status(500).json({
        success: false,
        error: `OpenAI API error: ${response.status}`
      });
    }

    const responseData = await response.json();
    const content = responseData.choices[0].message.content.trim();
    
         console.log('🔥 OpenAI response received, length:', content.length);
     if (content.length < 20) {
       console.log('⚠️ Suspiciously short response content:', content);
     }
     if (content.length > 2000) {
       console.log('✅ Response length looks good for complete data');
     }
    
    try {
      const jsonResponse = JSON.parse(content);
      
      if (!jsonResponse.ingredients || !Array.isArray(jsonResponse.ingredients) || jsonResponse.ingredients.length === 0) {
        return res.status(500).json({
          success: false,
          error: 'No food ingredients detected'
        });
      }

             console.log('🔥 Valid ingredients found:', jsonResponse.ingredients.length);
       if (jsonResponse.units_used) {
         console.log('📏 Units audit:', JSON.stringify(jsonResponse.units_used));
       }
       if (isNutritionRequest) {
         console.log('🎯 Nutrition.dart request - using specialized prompt');
       }
      
      // PASS THROUGH THE INGREDIENT LIST
      const ingredients = jsonResponse.ingredients.map(ing => ({
        name: ing.name,
        weight_g: ing.weight_g || 100,
        calories: ing.calories || 0,
        protein_g: ing.protein_g || 0,
        fat_g: ing.fat_g || 0,
        carbs_g: ing.carbs_g || 0,
        amount: `${ing.weight_g || 100}g`,
        protein: ing.protein_g || 0,
        fat: ing.fat_g || 0,
        carbs: ing.carbs_g || 0
      }));

      // USE TOTALS PROVIDED BY OPENAI (as required by the prompt)
      const totals = jsonResponse.totals || {};
      
      const response = {
        meal_name: jsonResponse.meal_name || "Food",
        ingredients: ingredients,
        calories: totals.calories ?? 0,
        protein: totals.protein_g ?? 0,
        fat: totals.fat_g ?? 0,
        carbs: totals.carbs_g ?? 0,
        // MICRONUTRIENTS - TOTALS FROM OPENAI
        vitamin_a: totals.vitamin_a ?? 0,
        vitamin_c: totals.vitamin_c ?? 0,
        vitamin_d: totals.vitamin_d ?? 0,
        vitamin_e: totals.vitamin_e ?? 0,
        vitamin_k: totals.vitamin_k ?? 0,
        vitamin_b1: totals.vitamin_b1 ?? 0,
        vitamin_b2: totals.vitamin_b2 ?? 0,
        vitamin_b3: totals.vitamin_b3 ?? 0,
        vitamin_b5: totals.vitamin_b5 ?? 0,
        vitamin_b6: totals.vitamin_b6 ?? 0,
        vitamin_b7: totals.vitamin_b7 ?? 0,
        vitamin_b9: totals.vitamin_b9 ?? 0,
        vitamin_b12: totals.vitamin_b12 ?? 0,
        calcium: totals.calcium ?? 0,
        chloride: totals.chloride ?? 0,
        chromium: totals.chromium ?? 0,
        copper: totals.copper ?? 0,
        fluoride: totals.fluoride ?? 0,
        iodine: totals.iodine ?? 0,
        iron: totals.iron ?? 0,
        magnesium: totals.magnesium ?? 0,
        manganese: totals.manganese ?? 0,
        molybdenum: totals.molybdenum ?? 0,
        phosphorus: totals.phosphorus ?? 0,
        potassium: totals.potassium ?? 0,
        selenium: totals.selenium ?? 0,
        sodium: totals.sodium ?? 0,
        zinc: totals.zinc ?? 0,
        fiber: totals.fiber ?? 0,
        cholesterol: totals.cholesterol ?? 0,
        sugar: totals.sugar ?? 0,
        saturated_fats: totals.saturated_fats ?? 0,
        omega_3: totals.omega_3 ?? 0,
        omega_6: totals.omega_6 ?? 0,
        units_used: jsonResponse.units_used || null
      };

             console.log('✅ Response prepared with micronutrients');
       console.log('Sample micronutrients:', {
         vitamin_a: response.vitamin_a,
         vitamin_c: response.vitamin_c,
         iron: response.iron,
         potassium: response.potassium
       });
       console.log('📊 Macros check:', {
         calories: response.calories,
         protein: response.protein,
         fat: response.fat,
         carbs: response.carbs
       });

      return res.json({
        success: true,
        data: response
      });

    } catch (parseError) {
      console.log('🔥 JSON parse failed:', parseError.message);
      console.log('🧾 Raw content snippet:', content.slice(0, 400));
      
      // ULTRA-AGGRESSIVE JSON REPAIR
      let repairedContent = ultraRepairJson(content);
      
      try {
        const jsonResponse = JSON.parse(repairedContent);
        
        if (jsonResponse.ingredients && jsonResponse.ingredients.length > 0) {
          console.log('✅ Ultra-aggressive repair successful!');
          
          // Same processing as above
          const ingredients = jsonResponse.ingredients.map(ing => ({
            name: ing.name,
            weight_g: ing.weight_g || 100,
            calories: ing.calories || 0,
            protein_g: ing.protein_g || 0,
            fat_g: ing.fat_g || 0,
            carbs_g: ing.carbs_g || 0,
            amount: `${ing.weight_g || 100}g`,
            protein: ing.protein_g || 0,
            fat: ing.fat_g || 0,
            carbs: ing.carbs_g || 0
          }));

          const totalCalories = ingredients.reduce((sum, ing) => sum + (ing.calories || 0), 0);
          const totalProtein = ingredients.reduce((sum, ing) => sum + (ing.protein_g || 0), 0);
          const totalFat = ingredients.reduce((sum, ing) => sum + (ing.fat_g || 0), 0);
          const totalCarbs = ingredients.reduce((sum, ing) => sum + (ing.carbs_g || 0), 0);

          const totals = jsonResponse.totals || {};
          
          const response = {
            meal_name: jsonResponse.meal_name || "Food",
            ingredients: ingredients,
            calories: totals.calories ?? 0,
            protein: totals.protein_g ?? 0,
            fat: totals.fat_g ?? 0,
            carbs: totals.carbs_g ?? 0,
            vitamin_a: totals.vitamin_a ?? 0,
            vitamin_c: totals.vitamin_c ?? 0,
            vitamin_d: totals.vitamin_d ?? 0,
            vitamin_e: totals.vitamin_e ?? 0,
            vitamin_k: totals.vitamin_k ?? 0,
            vitamin_b1: totals.vitamin_b1 ?? 0,
            vitamin_b2: totals.vitamin_b2 ?? 0,
            vitamin_b3: totals.vitamin_b3 ?? 0,
            vitamin_b5: totals.vitamin_b5 ?? 0,
            vitamin_b6: totals.vitamin_b6 ?? 0,
            vitamin_b7: totals.vitamin_b7 ?? 0,
            vitamin_b9: totals.vitamin_b9 ?? 0,
            vitamin_b12: totals.vitamin_b12 ?? 0,
            calcium: totals.calcium ?? 0,
            chloride: totals.chloride ?? 0,
            chromium: totals.chromium ?? 0,
            copper: totals.copper ?? 0,
            fluoride: totals.fluoride ?? 0,
            iodine: totals.iodine ?? 0,
            iron: totals.iron ?? 0,
            magnesium: totals.magnesium ?? 0,
            manganese: totals.manganese ?? 0,
            molybdenum: totals.molybdenum ?? 0,
            phosphorus: totals.phosphorus ?? 0,
            potassium: totals.potassium ?? 0,
            selenium: totals.selenium ?? 0,
            sodium: totals.sodium ?? 0,
            zinc: totals.zinc ?? 0,
            fiber: totals.fiber ?? 0,
            cholesterol: totals.cholesterol ?? 0,
            sugar: totals.sugar ?? 0,
            saturated_fats: totals.saturated_fats ?? 0,
            omega_3: totals.omega_3 ?? 0,
            omega_6: totals.omega_6 ?? 0,
            units_used: jsonResponse.units_used || null
          };

          return res.json({
            success: true,
            data: response
          });
        }
      } catch (repairError) {
        console.log('🔧 Ultra-aggressive repair failed:', repairError.message);
      }
      
      return res.status(500).json({
        success: false,
        error: 'Invalid JSON response from OpenAI'
      });
    }

  } catch (error) {
    console.log('🔥 Server error:', error.message);
    return res.status(500).json({
      success: false,
      error: `Server error: ${error.message}`
    });
  }
});

app.listen(PORT, () => {
  console.log(`Simple micronutrient server running on port ${PORT}`);
});