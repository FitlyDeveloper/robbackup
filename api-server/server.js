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
  runFDCTest
} = require('./nutrition.js');

const app = express();
const port = process.env.PORT || 3000;

// Configure OpenAI
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
});

// Configure multer for file uploads
const upload = multer({ dest: 'uploads/' });

console.log('Starting FDC-based nutrition server...');
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

app.listen(port, () => {
  console.log(`🚀 FDC Nutrition Server running on port ${port}`);
});