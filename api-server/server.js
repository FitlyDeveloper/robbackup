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
    const systemPrompt = `You are a nutritionist. Analyze the food image and return ONLY valid JSON with realistic micronutrient values.

{
  "meal_name": "Food Name",
  "ingredients": [
    {
      "name": "Food Item",
      "weight_g": 100,
      "calories": 80,
      "protein_g": 5,
      "fat_g": 2,
      "carbs_g": 12,
      "vitamin_a": 250,
      "vitamin_c": 8,
      "vitamin_d": 1,
      "vitamin_e": 0.8,
      "vitamin_k": 5,
      "vitamin_b1": 0.05,
      "vitamin_b2": 0.08,
      "vitamin_b3": 1.2,
      "vitamin_b5": 0.4,
      "vitamin_b6": 0.1,
      "vitamin_b7": 2,
      "vitamin_b9": 15,
      "vitamin_b12": 0.2,
      "calcium": 30,
      "chloride": 80,
      "chromium": 1,
      "copper": 0.1,
      "fluoride": 0.5,
      "iodine": 5,
      "iron": 0.8,
      "magnesium": 25,
      "manganese": 0.3,
      "molybdenum": 3,
      "phosphorus": 40,
      "potassium": 180,
      "selenium": 1.5,
      "sodium": 50,
      "zinc": 0.5,
      "fiber": 1.8,
      "cholesterol": 10,
      "sugar": 5,
      "saturated_fats": 0.4,
      "omega_3": 80,
      "omega_6": 1.2
    }
  ]
}

CRITICAL: Use realistic USDA values. NO zeros. Valid JSON only.`;

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
                text: "Analyze this food image and provide COMPLETE nutritional data with REALISTIC values for ALL 34 micronutrients. DO NOT return zeros - use actual USDA nutritional values."
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
      
      // SIMPLE JSON REPAIR
      let repairedContent = content.trim()
        .replace(/^```json\s*/, '').replace(/\s*```$/, '')
        .replace(/,\s*}/g, '}')
        .replace(/,\s*]/g, ']');
      
      try {
        const jsonResponse = JSON.parse(repairedContent);
        
        if (jsonResponse.ingredients && jsonResponse.ingredients.length > 0) {
          console.log('✅ JSON repair successful!');
          
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
        console.log('🔧 JSON repair failed:', repairError.message);
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