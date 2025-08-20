require('dotenv').config();
const express = require('express');
const cors = require('cors');
const multer = require('multer');
const OpenAI = require('openai');
const fs = require('fs');
const path = require('path');

const {
  DV,
  makeZeroTotals,
  calculateTotalsFromFDC,
  calculateDVPct,
  roundTotals,
  convertToNutritionFormat,
  runFDCTest,
  searchFDC,
  fetchFDCData,
  extractPer100
} = require('./nutrition.js');

const app = express();
const port = process.env.PORT || 3000;

// Configure OpenAI
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
});

// Configure multer for file uploads
const upload = multer({ dest: 'uploads/' });

console.log('Starting FDC-based nutrition server with enhanced reliability...');
console.log('OpenAI API Key present:', process.env.OPENAI_API_KEY ? 'Yes' : 'No');
console.log('FDC API Key present:', process.env.FDC_API_KEY ? 'Yes' : 'No');

// Run FDC test on startup
runFDCTest();

app.use(cors());

// BEFORE any routes - increase body limits for base64 JSON payloads
app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true, limit: "10mb" }));

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

// Root endpoint for basic connectivity
app.get('/', (req, res) => {
  res.json({ 
    status: 'OK', 
    message: 'FDC Nutrition Server is running',
    timestamp: new Date().toISOString() 
  });
});

// Warmup endpoint for Flutter app
app.get('/api/warmup', (req, res) => {
  res.json({ 
    status: 'OK', 
    message: 'API server warmed up',
    timestamp: new Date().toISOString() 
  });
});

// Main nutrition analysis endpoint
app.post('/analyze-nutrition', upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image file provided' });
    }

    console.log('📸 Processing image:', req.file.originalname);

    // Read the image file
    const imageBuffer = fs.readFileSync(req.file.path);
    const base64Image = imageBuffer.toString('base64');

    // Clean up the uploaded file
    fs.unlinkSync(req.file.path);

    // Extract ingredients using OpenAI Vision (ONLY name and grams)
    const ingredients = await extractIngredientsFromImage(base64Image);
    
    if (!ingredients || ingredients.length === 0) {
      return res.status(400).json({ error: 'No ingredients detected in image' });
    }

    console.log('🔍 Extracted ingredients:', ingredients);

    // Calculate nutrition using FDC
    const totals = await calculateTotalsFromFDC(ingredients);
    const dvPct = calculateDVPct(totals);

    // Format response for nutrition.dart
    const nutritionData = convertToNutritionFormat(totals, dvPct);

    // Create ingredients list for nutrition.dart
    const ingredientsList = ingredients.map(ing => ({
      name: ing.name,
      weight_g: ing.grams || 100,
      amount: `${ing.grams || 100}g`,
      protein: ((ing.grams || 0) / 100) * (totals.protein_g / ingredients.length), // Approximate per ingredient
      fat: ((ing.grams || 0) / 100) * (totals.fat_g / ingredients.length),
      carbs: ((ing.grams || 0) / 100) * (totals.carbs_g / ingredients.length)
    }));

    // Detailed verification logging
    console.log('\n📊 INGREDIENT BREAKDOWN:');
    for (const i of ingredients) {
      console.log(`${i.name}: ${i.grams}g`);
    }

    console.log('\n📊 FINAL TOTALS:');
    console.log('Macros:', {
      'Calories': `${totals.calories_kcal} kcal`,
      'Protein': `${totals.protein_g} g`,
      'Fat': `${totals.fat_g} g`,
      'Carbs': `${totals.carbs_g} g`
    });
    console.log('Key Vitamins:', {
      'Vit A': `${totals.vitamins.A_mcg} mcg (${dvPct.vitamins.A_mcg}% DV)`,
      'Vit C': `${totals.vitamins.C_mg} mg (${dvPct.vitamins.C_mg}% DV)`,
      'Vit K': `${totals.vitamins.K_mcg} mcg (${dvPct.vitamins.K_mcg}% DV)`,
      'B12': `${totals.vitamins.B12_mcg} mcg (${dvPct.vitamins.B12_mcg}% DV)`
    });
    console.log('Key Minerals:', {
      'Iron': `${totals.minerals.Fe_mg} mg (${dvPct.minerals.Fe_mg}% DV)`,
      'Sodium': `${totals.minerals.Na_mg} mg (${dvPct.minerals.Na_mg}% DV)`,
      'Calcium': `${totals.minerals.Ca_mg} mg (${dvPct.minerals.Ca_mg}% DV)`
    });

    // Return nutrition.dart format
    const response = {
      meal_name: "Food",
      ingredients: ingredientsList,
      calories: nutritionData.calories,
      protein: nutritionData.protein,
      fat: nutritionData.fat,
      carbs: nutritionData.carbs,
      ...nutritionData
    };

    res.json(response);

  } catch (error) {
    console.error('❌ Error processing nutrition analysis:', error);
    res.status(500).json({ error: 'Failed to analyze nutrition', details: error.message });
  }
});

// New endpoint for the updated API format
app.post('/analyze-nutrition-v2', upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image file provided' });
    }

    console.log('📸 Processing image (v2):', req.file.originalname);

    // Read the image file
    const imageBuffer = fs.readFileSync(req.file.path);
    const base64Image = imageBuffer.toString('base64');

    // Clean up the uploaded file
    fs.unlinkSync(req.file.path);

    // Extract ingredients using OpenAI Vision (ONLY name and grams)
    const ingredients = await extractIngredientsFromImage(base64Image);
    
    if (!ingredients || ingredients.length === 0) {
      return res.status(400).json({ error: 'No ingredients detected in image' });
    }

    console.log('🔍 Extracted ingredients:', ingredients);

    // Calculate nutrition using FDC
    const totals = await calculateTotalsFromFDC(ingredients);
    const dvPct = calculateDVPct(totals);

    // Return new API format
    const response = {
      ingredients: ingredients,
      macros: {
        calories_kcal: totals.calories_kcal,
        protein_g: totals.protein_g,
        fat_g: totals.fat_g,
        carbs_g: totals.carbs_g
      },
      vitamins: totals.vitamins,
      minerals: totals.minerals,
      other: totals.other,
      dv_pct: dvPct
    };

    res.json(response);

  } catch (error) {
    console.error('❌ Error processing nutrition analysis (v2):', error);
    res.status(500).json({ error: 'Failed to analyze nutrition', details: error.message });
  }
});

// New endpoint that accepts either imageUrl or imageBase64
app.post('/api/analyze-food', async (req, res) => {
  try {
    const { imageUrl, imageBase64, source } = req.body || {};
    
    if (!imageUrl && !imageBase64) {
      return res.status(400).json({ error: "Provide imageUrl or imageBase64" });
    }

    let base64Image;
    
    if (imageBase64) {
      // Use provided base64 image
      base64Image = imageBase64;
      console.log('📸 Processing base64 image (size:', Math.round(imageBase64.length / 1024), 'KB)');
    } else if (imageUrl) {
      // Fetch image from URL
      console.log('📸 Processing image URL:', imageUrl);
      try {
        const response = await fetch(imageUrl);
        if (!response.ok) {
          return res.status(400).json({ error: 'Failed to fetch image from URL' });
        }
        const imageBuffer = await response.arrayBuffer();
        base64Image = Buffer.from(imageBuffer).toString('base64');
      } catch (error) {
        return res.status(400).json({ error: 'Failed to fetch image from URL', details: error.message });
      }
    }

    // Extract ingredients using OpenAI Vision (ONLY name and grams)
    const ingredients = await extractIngredientsFromImage(base64Image);
    
    if (!ingredients || ingredients.length === 0) {
      return res.status(400).json({ error: 'No ingredients detected in image' });
    }

    console.log('🔍 Extracted ingredients:', ingredients);

    // Calculate nutrition using FDC with per-ingredient data
    const { totals, perIngredient } = await calculateTotalsFromFDCWithPerIngredient(ingredients);
    const dvPct = calculateDVPct(totals);

    // Return new API format with per-ingredient data
    const response = {
      food_name: "Analyzed Food", // Add food name for Flutter compatibility
      ingredients: ingredients, // Now augmented with kcal/macros
      macros: {
        calories_kcal: totals.calories_kcal,
        protein_g: totals.protein_g,
        fat_g: totals.fat_g,
        carbs_g: totals.carbs_g
      },
      vitamins: totals.vitamins,
      minerals: totals.minerals,
      other: totals.other,
      dv_pct: dvPct,
      perIngredient: perIngredient // Detailed list for the flip side UI
    };

    console.log('📤 Sending response to Flutter app with', Object.keys(response).length, 'keys');
    console.log('📊 Response summary: calories=', totals.calories_kcal, 'protein=', totals.protein_g, 'ingredients=', ingredients.length);

    res.json(response);

  } catch (error) {
    console.error('❌ Error processing nutrition analysis:', error);
    res.status(500).json({ error: 'Failed to analyze nutrition', details: error.message });
  }
});

// Extract ingredients from image using OpenAI Vision
async function extractIngredientsFromImage(base64Image) {
  try {
    console.log('🤖 Calling OpenAI Vision for ingredient extraction...');

    // Extract base64 data from data URI if present
    let cleanBase64 = base64Image;
    if (base64Image.startsWith('data:image/')) {
      const commaIndex = base64Image.indexOf(',');
      if (commaIndex !== -1) {
        cleanBase64 = base64Image.substring(commaIndex + 1);
        console.log('📸 Extracted base64 data from data URI (length:', cleanBase64.length, ')');
      }
    }

    const response = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: `You are a food ingredient extractor. Your ONLY job is to identify ingredients and their weights from food images.

RULES:
- Extract ONLY ingredient names and weights in grams
- Do NOT calculate any nutrients, calories, or nutrition facts
- Do NOT provide any nutritional analysis
- Output ONLY valid JSON in this exact format: {"ingredients": [{"name": "Ingredient Name", "grams": weight_in_grams}]}
- If you can't determine the weight, estimate based on typical serving sizes
- Be specific with ingredient names (e.g., "chicken breast" not just "chicken")
- If multiple ingredients are visible, list them all
- If no ingredients are visible, return {"ingredients": []}`

        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: "Extract the ingredients and their weights from this food image. Return ONLY the JSON with ingredients array."
            },
            {
              type: "image_url",
              image_url: {
                url: `data:image/jpeg;base64,${cleanBase64}`
              }
            }
          ]
        }
      ],
      response_format: { type: "json_object" },
      max_tokens: 500
    });

    const content = response.choices[0].message.content;
    console.log('🤖 OpenAI response:', content);

    // Parse JSON response
    let jsonResponse;
    try {
      jsonResponse = JSON.parse(content);
    } catch (parseError) {
      console.log('❌ Failed to parse OpenAI JSON, attempting repair...');
      jsonResponse = repairJSON(content);
    }

    if (!jsonResponse || !jsonResponse.ingredients) {
      console.log('❌ Invalid response format from OpenAI');
      return [];
    }

    // Validate and clean ingredients
    const validIngredients = jsonResponse.ingredients
      .filter(ing => ing && ing.name && ing.grams)
      .map(ing => ({
        name: ing.name.trim(),
        grams: Math.round(parseFloat(ing.grams) || 0)
      }))
      .filter(ing => ing.grams > 0);

    console.log('✅ Validated ingredients:', validIngredients);
    return validIngredients;

  } catch (error) {
    console.error('❌ OpenAI Vision error:', error);
    throw new Error(`Failed to extract ingredients: ${error.message}`);
  }
}

// JSON repair function
function repairJSON(content) {
  try {
    // Try to extract JSON from the response
    const jsonMatch = content.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      return JSON.parse(jsonMatch[0]);
    }
    
    // If no JSON found, try to construct it from the text
    const lines = content.split('\n').filter(line => line.trim());
    const ingredients = [];
    
    for (const line of lines) {
      const match = line.match(/(.+?)\s*[:\-]\s*(\d+)\s*g/i);
      if (match) {
        ingredients.push({
          name: match[1].trim(),
          grams: parseInt(match[2])
        });
      }
    }
    
    return { ingredients };
  } catch (error) {
    console.log('❌ JSON repair failed:', error);
    return { ingredients: [] };
  }
}

// Helper functions
function titleCase(s) { 
  return String(s||'').replace(/\w\S*/g, w => w[0].toUpperCase()+w.slice(1)); 
}

function round1(x) { 
  return Math.round((x||0)*10)/10; 
}

// Calculate totals from FDC with per-ingredient data
async function calculateTotalsFromFDCWithPerIngredient(ingredients) {
  const totals = makeZeroTotals();
  const perIngredient = [];
  
  for (let idx = 0; idx < ingredients.length; idx++) {
    const ing = ingredients[idx];
    const { name, grams } = ing;
    
    console.log(`🔍 Processing ingredient: ${name} (${grams}g)`);
    
    // Search FDC for this ingredient
    const fdcId = await searchFDC(name);
    if (!fdcId) {
      console.log(`❌ No FDC data found for: ${name}`);
      continue;
    }
    
    // Fetch nutrient data
    const fdcData = await fetchFDCData(fdcId);
    if (!fdcData) {
      console.log(`❌ Failed to fetch FDC data for: ${name}`);
      continue;
    }
    
    // Extract nutrients using the robust parser
    const per100 = extractPer100(fdcData);
    console.log('FDC per100 for', name, per100);
    
    if (!per100 || Object.keys(per100).length === 0) {
      console.log(`❌ Failed to extract nutrients for: ${name}`);
      continue;
    }
    
    // Scale by grams/100
    const f = (grams || 0) / 100;
    console.log('Factor', f.toFixed(2), 'Scaled protein_g=', ((per100.protein_g||0)*f).toFixed(2));
    
    // Build per-ingredient record
    const item = {
      name: titleCase(name),
      grams: Math.round(grams),
      calories_kcal: round1((per100.calories_kcal || 0) * f),
      protein_g: round1((per100.protein_g || 0) * f),
      fat_g: round1((per100.fat_g || 0) * f),
      carbs_g: round1((per100.carbs_g || 0) * f),
      // Optional micros shown in the flip card if needed
      vitamins: {
        A_mcg: Math.round((per100.A_mcg || 0) * f),
        C_mg: round1((per100.C_mg || 0) * f),
        K_mcg: Math.round((per100.K_mcg || 0) * f),
        B12_mcg: Math.round((per100.B12_mcg || 0) * f)
      },
      minerals: {
        Ca_mg: round1((per100.Ca_mg || 0) * f),
        Fe_mg: round1((per100.Fe_mg || 0) * f),
        K_mg: round1((per100.K_mg || 0) * f),
        Na_mg: round1((per100.Na_mg || 0) * f)
      }
    };
    
    perIngredient.push(item);
    
    // Augment the original ingredient element with nutrition data
    ingredients[idx].calories_kcal = item.calories_kcal;
    ingredients[idx].protein_g = item.protein_g;
    ingredients[idx].fat_g = item.fat_g;
    ingredients[idx].carbs_g = item.carbs_g;
    
    // Sum macronutrients for totals
    totals.calories_kcal += (per100.calories_kcal || 0) * f;
    totals.protein_g += (per100.protein_g || 0) * f;
    totals.fat_g += (per100.fat_g || 0) * f;
    totals.carbs_g += (per100.carbs_g || 0) * f;
    
    // Sum vitamins
    for (const k of Object.keys(totals.vitamins)) {
      totals.vitamins[k] += (per100[k] || 0) * f;
    }
    
    // Sum minerals
    for (const k of Object.keys(totals.minerals)) {
      totals.minerals[k] += (per100[k] || 0) * f;
    }
    
    // Sum other nutrients
    for (const k of Object.keys(totals.other)) {
      totals.other[k] += (per100[k] || 0) * f;
    }
  }
  
  // Log per-ingredient breakdown
  console.table(perIngredient.map(i => ({
    name: i.name, 
    g: i.grams, 
    kcal: i.calories_kcal, 
    P: i.protein_g, 
    F: i.fat_g, 
    C: i.carbs_g
  })));
  
  return { totals: roundTotals(totals), perIngredient };
}

app.listen(port, () => {
  console.log(`🚀 FDC Nutrition Server running on port ${port}`);
});