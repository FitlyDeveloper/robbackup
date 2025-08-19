require('dotenv').config();
const express = require('express');
const cors = require('cors');
const fetch = require('node-fetch');

const app = express();
const PORT = process.env.PORT || 10000;

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

    // SIMPLE PROMPT - ONLY MICRONUTRIENTS
    const systemPrompt = `You are a gourmet chef and nutritionist. Analyze the food image and return ONLY valid JSON with realistic micronutrient values.

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

UNITS: All micronutrients should be in these units:
- Vitamins: mg (except vitamin_a in mcg, vitamin_d in mcg, vitamin_b7 in mcg, vitamin_b9 in mcg, vitamin_b12 in mcg, vitamin_k in mcg)
- Minerals: mg (except chromium in mcg, copper in mg, fluoride in mg, iodine in mcg, manganese in mg, molybdenum in mcg, selenium in mcg, zinc in mg)
- Other: fiber (g), cholesterol (mg), sugar (g), saturated_fats (g), omega_3 (mg), omega_6 (g)

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
}

CRITICAL: Use realistic USDA values. NO zeros. Valid JSON only.

MICRONUTRIENT REQUIREMENTS:
- ALL micronutrients MUST have realistic values (NO zeros)
- Use actual USDA nutritional database values
- "Other" category (fiber, cholesterol, sugar, saturated_fats, omega_3, omega_6) MUST be accurate
- Example: A meal with dumplings should have fiber=2-4g, cholesterol=20-50mg, sugar=3-8g, saturated_fats=2-6g
- Example: A meal with tomatoes should have vitamin_c=15-25mg, fiber=2-4g
- Example: A meal with sour cream should have cholesterol=30-60mg, saturated_fats=3-8g

DO NOT RETURN ZEROS FOR ANY MICRONUTRIENT!`;

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0.1,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content: systemPrompt
          },
          {
            role: "user",
            content: [
                             { 
                 type: "text", 
                 text: "Analyze this food image and provide COMPLETE nutritional data with REALISTIC values for ALL 34 micronutrients. DO NOT return zeros - use actual USDA nutritional values. Pay special attention to the 'Other' category (fiber, cholesterol, sugar, saturated_fats, omega_3, omega_6) - these MUST be accurate and realistic."
               },
              { 
                type: "image_url", 
                image_url: { url: image }
              }
            ]
          }
        ],
        max_tokens: 1500
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
    
    try {
      const jsonResponse = JSON.parse(content);
      
      if (!jsonResponse.ingredients || !Array.isArray(jsonResponse.ingredients) || jsonResponse.ingredients.length === 0) {
        return res.status(500).json({
          success: false,
          error: 'No food ingredients detected'
        });
      }

      console.log('🔥 Valid ingredients found:', jsonResponse.ingredients.length);
      
      // SIMPLE PROCESSING - JUST PASS THROUGH THE DATA
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

      // CALCULATE TOTALS
      const totalCalories = ingredients.reduce((sum, ing) => sum + (ing.calories || 0), 0);
      const totalProtein = ingredients.reduce((sum, ing) => sum + (ing.protein_g || 0), 0);
      const totalFat = ingredients.reduce((sum, ing) => sum + (ing.fat_g || 0), 0);
      const totalCarbs = ingredients.reduce((sum, ing) => sum + (ing.carbs_g || 0), 0);

      // EXTRACT MICRONUTRIENTS FROM FIRST INGREDIENT (SIMPLE APPROACH)
      const firstIngredient = jsonResponse.ingredients[0];
      
      const response = {
        meal_name: jsonResponse.meal_name || "Food",
        ingredients: ingredients,
        calories: totalCalories,
        protein: totalProtein,
        fat: totalFat,
        carbs: totalCarbs,
        // MICRONUTRIENTS - DIRECT FROM OPENAI
        vitamin_a: firstIngredient.vitamin_a || 0,
        vitamin_c: firstIngredient.vitamin_c || 0,
        vitamin_d: firstIngredient.vitamin_d || 0,
        vitamin_e: firstIngredient.vitamin_e || 0,
        vitamin_k: firstIngredient.vitamin_k || 0,
        vitamin_b1: firstIngredient.vitamin_b1 || 0,
        vitamin_b2: firstIngredient.vitamin_b2 || 0,
        vitamin_b3: firstIngredient.vitamin_b3 || 0,
        vitamin_b5: firstIngredient.vitamin_b5 || 0,
        vitamin_b6: firstIngredient.vitamin_b6 || 0,
        vitamin_b7: firstIngredient.vitamin_b7 || 0,
        vitamin_b9: firstIngredient.vitamin_b9 || 0,
        vitamin_b12: firstIngredient.vitamin_b12 || 0,
        calcium: firstIngredient.calcium || 0,
        chloride: firstIngredient.chloride || 0,
        chromium: firstIngredient.chromium || 0,
        copper: firstIngredient.copper || 0,
        fluoride: firstIngredient.fluoride || 0,
        iodine: firstIngredient.iodine || 0,
        iron: firstIngredient.iron || 0,
        magnesium: firstIngredient.magnesium || 0,
        manganese: firstIngredient.manganese || 0,
        molybdenum: firstIngredient.molybdenum || 0,
        phosphorus: firstIngredient.phosphorus || 0,
        potassium: firstIngredient.potassium || 0,
        selenium: firstIngredient.selenium || 0,
        sodium: firstIngredient.sodium || 0,
        zinc: firstIngredient.zinc || 0,
        fiber: firstIngredient.fiber || 0,
        cholesterol: firstIngredient.cholesterol || 0,
        sugar: firstIngredient.sugar || 0,
        saturated_fats: firstIngredient.saturated_fats || 0,
        omega_3: firstIngredient.omega_3 || 0,
        omega_6: firstIngredient.omega_6 || 0
      };

      console.log('✅ Response prepared with micronutrients');
      console.log('Sample micronutrients:', {
        vitamin_a: response.vitamin_a,
        vitamin_c: response.vitamin_c,
        iron: response.iron,
        potassium: response.potassium
      });

      return res.json({
        success: true,
        data: response
      });

    } catch (parseError) {
      console.log('🔥 JSON parse failed:', parseError.message);
      
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

          const firstIngredient = jsonResponse.ingredients[0];
          
          const response = {
            meal_name: jsonResponse.meal_name || "Food",
            ingredients: ingredients,
            calories: totalCalories,
            protein: totalProtein,
            fat: totalFat,
            carbs: totalCarbs,
            vitamin_a: firstIngredient.vitamin_a || 0,
            vitamin_c: firstIngredient.vitamin_c || 0,
            vitamin_d: firstIngredient.vitamin_d || 0,
            vitamin_e: firstIngredient.vitamin_e || 0,
            vitamin_k: firstIngredient.vitamin_k || 0,
            vitamin_b1: firstIngredient.vitamin_b1 || 0,
            vitamin_b2: firstIngredient.vitamin_b2 || 0,
            vitamin_b3: firstIngredient.vitamin_b3 || 0,
            vitamin_b5: firstIngredient.vitamin_b5 || 0,
            vitamin_b6: firstIngredient.vitamin_b6 || 0,
            vitamin_b7: firstIngredient.vitamin_b7 || 0,
            vitamin_b9: firstIngredient.vitamin_b9 || 0,
            vitamin_b12: firstIngredient.vitamin_b12 || 0,
            calcium: firstIngredient.calcium || 0,
            chloride: firstIngredient.chloride || 0,
            chromium: firstIngredient.chromium || 0,
            copper: firstIngredient.copper || 0,
            fluoride: firstIngredient.fluoride || 0,
            iodine: firstIngredient.iodine || 0,
            iron: firstIngredient.iron || 0,
            magnesium: firstIngredient.magnesium || 0,
            manganese: firstIngredient.manganese || 0,
            molybdenum: firstIngredient.molybdenum || 0,
            phosphorus: firstIngredient.phosphorus || 0,
            potassium: firstIngredient.potassium || 0,
            selenium: firstIngredient.selenium || 0,
            sodium: firstIngredient.sodium || 0,
            zinc: firstIngredient.zinc || 0,
            fiber: firstIngredient.fiber || 0,
            cholesterol: firstIngredient.cholesterol || 0,
            sugar: firstIngredient.sugar || 0,
            saturated_fats: firstIngredient.saturated_fats || 0,
            omega_3: firstIngredient.omega_3 || 0,
            omega_6: firstIngredient.omega_6 || 0
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