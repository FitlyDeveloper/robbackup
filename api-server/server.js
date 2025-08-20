require('dotenv').config();
const express = require('express');
const cors = require('cors');
const OpenAI = require('openai');

// Import nutrition functions
const { 
  makeZeroTotals, 
  calculateDVPct, 
  roundTotals,
  searchFDC,
  fetchFDCData,
  extractPer100
} = require('./nutrition');

const app = express();
const PORT = process.env.PORT || 10000;

// Server hardening - handle large payloads
app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true, limit: "10mb" }));
app.use(cors());

// Initialize OpenAI
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

// Name normalization for deterministic FDC matching
const NORMALIZE = [
  [/^dark\s*bread$/i, "bread, whole wheat"],
  [/^bread$/i, "bread, wheat"],
  [/^spaghetti$/i, "spaghetti, cooked"],
  [/^grated\s*cheese$/i, "cheese, parmesan, grated"],
  [/^salami$/i, "salami"],
  [/^coleslaw.*$/i, "coleslaw"],
  [/^chicken breast$/i, "chicken, breast, roasted"],
  [/^greek yogurt$/i, "yogurt, Greek, plain, nonfat"],
  [/^sour cream$/i, "sour cream"],
  [/^sweet potato$/i, "sweet potato, baked, flesh only"],
  [/^pineapple$/i, "pineapple, raw"],
  [/^watermelon$/i, "watermelon, raw"],
  [/^apple$/i, "apple, raw, with skin"],
  [/^banana$/i, "banana, raw"],
  [/^orange$/i, "orange, raw"],
  [/^tomato$/i, "tomato, raw"],
  [/^lettuce$/i, "lettuce, raw"],
  [/^carrot$/i, "carrot, raw"],
  [/^broccoli$/i, "broccoli, raw"],
  [/^spinach$/i, "spinach, raw"],
  [/^rice$/i, "rice, white, cooked"],
  [/^pasta$/i, "pasta, cooked"],
  [/^beef$/i, "beef, ground, cooked"],
  [/^pork$/i, "pork, ground, cooked"],
  [/^salmon$/i, "salmon, raw"],
  [/^tuna$/i, "tuna, raw"],
  [/^egg$/i, "egg, whole, raw"],
  [/^milk$/i, "milk, whole"],
  [/^cheese$/i, "cheese, cheddar"],
  [/^butter$/i, "butter, salted"],
  [/^oil$/i, "oil, olive"],
  [/^salt$/i, "salt, table"],
  [/^pepper$/i, "pepper, black"],
  [/^garlic$/i, "garlic, raw"],
  [/^onion$/i, "onion, raw"],
  [/^potato$/i, "potato, raw"],
  [/^corn$/i, "corn, sweet, raw"],
  [/^peas$/i, "peas, green, raw"],
  [/^beans$/i, "beans, black, raw"],
  [/^lentils$/i, "lentils, raw"],
  [/^quinoa$/i, "quinoa, raw"],
  [/^oatmeal$/i, "oats, raw"],
  [/^almonds$/i, "almonds, raw"],
  [/^peanuts$/i, "peanuts, raw"],
  [/^walnuts$/i, "walnuts, raw"],
  [/^honey$/i, "honey"],
  [/^sugar$/i, "sugar, granulated"],
  [/^flour$/i, "flour, wheat, all-purpose"],
  [/^vinegar$/i, "vinegar, distilled"],
  [/^soy sauce$/i, "soy sauce"],
  [/^mustard$/i, "mustard, prepared"],
  [/^ketchup$/i, "ketchup"],
  [/^mayonnaise$/i, "mayonnaise"],
  [/^hot sauce$/i, "hot sauce"],
  [/^salsa$/i, "salsa"],
  [/^guacamole$/i, "guacamole"],
  [/^hummus$/i, "hummus"],
  [/^tahini$/i, "tahini"],
  [/^olives$/i, "olives, ripe"],
  [/^pickles$/i, "pickles, cucumber"],
  [/^cucumber$/i, "cucumber, raw"],
  [/^bell pepper$/i, "peppers, sweet, raw"],
  [/^jalapeno$/i, "peppers, jalapeno, raw"],
  [/^mushroom$/i, "mushrooms, raw"],
  [/^zucchini$/i, "squash, summer, raw"],
  [/^eggplant$/i, "eggplant, raw"],
  [/^cauliflower$/i, "cauliflower, raw"],
  [/^cabbage$/i, "cabbage, raw"],
  [/^kale$/i, "kale, raw"],
  [/^arugula$/i, "arugula, raw"],
  [/^basil$/i, "basil, fresh"],
  [/^cilantro$/i, "cilantro, raw"],
  [/^parsley$/i, "parsley, raw"],
  [/^mint$/i, "mint, fresh"],
  [/^oregano$/i, "oregano, fresh"],
  [/^thyme$/i, "thyme, fresh"],
  [/^rosemary$/i, "rosemary, fresh"],
  [/^sage$/i, "sage, fresh"],
  [/^bay leaf$/i, "bay leaf"],
  [/^cinnamon$/i, "cinnamon, ground"],
  [/^nutmeg$/i, "nutmeg, ground"],
  [/^ginger$/i, "ginger, raw"],
  [/^turmeric$/i, "turmeric, ground"],
  [/^cumin$/i, "cumin, ground"],
  [/^paprika$/i, "paprika"],
  [/^chili powder$/i, "chili powder"],
  [/^oregano$/i, "oregano, dried"],
  [/^basil$/i, "basil, dried"],
  [/^thyme$/i, "thyme, dried"],
  [/^rosemary$/i, "rosemary, dried"],
  [/^sage$/i, "sage, dried"],
  [/^bay leaf$/i, "bay leaf, dried"],
  [/^cinnamon$/i, "cinnamon, ground"],
  [/^nutmeg$/i, "nutmeg, ground"],
  [/^ginger$/i, "ginger, ground"],
  [/^turmeric$/i, "turmeric, ground"],
  [/^cumin$/i, "cumin, ground"],
  [/^paprika$/i, "paprika"],
  [/^chili powder$/i, "chili powder"],
  [/^cayenne$/i, "cayenne pepper"],
  [/^black pepper$/i, "pepper, black"],
  [/^white pepper$/i, "pepper, white"],
  [/^salt$/i, "salt, table"],
  [/^sea salt$/i, "salt, sea"],
  [/^kosher salt$/i, "salt, kosher"],
  [/^himalayan salt$/i, "salt, pink"],
  [/^garlic powder$/i, "garlic, powder"],
  [/^onion powder$/i, "onion, powder"],
  [/^celery salt$/i, "celery salt"],
  [/^lemon pepper$/i, "lemon pepper"],
  [/^cajun seasoning$/i, "cajun seasoning"],
  [/^italian seasoning$/i, "italian seasoning"],
  [/^herbs de provence$/i, "herbs de provence"],
  [/^curry powder$/i, "curry powder"],
  [/^garam masala$/i, "garam masala"],
  [/^cardamom$/i, "cardamom, ground"],
  [/^cloves$/i, "cloves, ground"],
  [/^allspice$/i, "allspice, ground"],
  [/^star anise$/i, "star anise"],
  [/^fennel$/i, "fennel, ground"],
  [/^coriander$/i, "coriander, ground"],
  [/^fenugreek$/i, "fenugreek, ground"],
  [/^saffron$/i, "saffron"],
  [/^vanilla$/i, "vanilla extract"],
  [/^almond extract$/i, "almond extract"],
  [/^lemon extract$/i, "lemon extract"],
  [/^orange extract$/i, "orange extract"],
  [/^mint extract$/i, "mint extract"],
  [/^peppermint extract$/i, "peppermint extract"],
  [/^rose water$/i, "rose water"],
  [/^orange blossom water$/i, "orange blossom water"],
  [/^almond milk$/i, "almond milk, unsweetened"],
  [/^soy milk$/i, "soy milk, unsweetened"],
  [/^oat milk$/i, "oat milk, unsweetened"],
  [/^coconut milk$/i, "coconut milk"],
  [/^cashew milk$/i, "cashew milk, unsweetened"],
  [/^rice milk$/i, "rice milk, unsweetened"],
  [/^hemp milk$/i, "hemp milk, unsweetened"],
  [/^flax milk$/i, "flax milk, unsweetened"],
  [/^macadamia milk$/i, "macadamia milk, unsweetened"],
  [/^hazelnut milk$/i, "hazelnut milk, unsweetened"],
  [/^pistachio milk$/i, "pistachio milk, unsweetened"],
  [/^walnut milk$/i, "walnut milk, unsweetened"],
  [/^pecan milk$/i, "pecan milk, unsweetened"],
  [/^brazil nut milk$/i, "brazil nut milk, unsweetened"],
  [/^pumpkin seed milk$/i, "pumpkin seed milk, unsweetened"],
  [/^sunflower seed milk$/i, "sunflower seed milk, unsweetened"],
  [/^sesame milk$/i, "sesame milk, unsweetened"],
  [/^quinoa milk$/i, "quinoa milk, unsweetened"],
  [/^amaranth milk$/i, "amaranth milk, unsweetened"],
  [/^teff milk$/i, "teff milk, unsweetened"],
  [/^sorghum milk$/i, "sorghum milk, unsweetened"],
  [/^millet milk$/i, "millet milk, unsweetened"],
  [/^buckwheat milk$/i, "buckwheat milk, unsweetened"],
  [/^kamut milk$/i, "kamut milk, unsweetened"],
  [/^spelt milk$/i, "spelt milk, unsweetened"],
  [/^emmer milk$/i, "emmer milk, unsweetened"],
  [/^einkorn milk$/i, "einkorn milk, unsweetened"],
  [/^farro milk$/i, "farro milk, unsweetened"],
  [/^freekeh milk$/i, "freekeh milk, unsweetened"],
  [/^bulgur milk$/i, "bulgur milk, unsweetened"],
  [/^couscous milk$/i, "couscous milk, unsweetened"],
  [/^polenta milk$/i, "polenta milk, unsweetened"],
  [/^grits milk$/i, "grits milk, unsweetened"],
  [/^cornmeal milk$/i, "cornmeal milk, unsweetened"],
  [/^semolina milk$/i, "semolina milk, unsweetened"],
  [/^durum wheat milk$/i, "durum wheat milk, unsweetened"],
  [/^hard wheat milk$/i, "hard wheat milk, unsweetened"],
  [/^soft wheat milk$/i, "soft wheat milk, unsweetened"],
  [/^red wheat milk$/i, "red wheat milk, unsweetened"],
  [/^white wheat milk$/i, "white wheat milk, unsweetened"],
  [/^winter wheat milk$/i, "winter wheat milk, unsweetened"],
  [/^spring wheat milk$/i, "spring wheat milk, unsweetened"],
  [/^durum wheat milk$/i, "durum wheat milk, unsweetened"],
  [/^hard wheat milk$/i, "hard wheat milk, unsweetened"],
  [/^soft wheat milk$/i, "soft wheat milk, unsweetened"],
  [/^red wheat milk$/i, "red wheat milk, unsweetened"],
  [/^white wheat milk$/i, "white wheat milk, unsweetened"],
  [/^winter wheat milk$/i, "winter wheat milk, unsweetened"],
  [/^spring wheat milk$/i, "spring wheat milk, unsweetened"],
];

function normalizeName(s) {
  const t = String(s || "").trim().toLowerCase();
  for (const [re, out] of NORMALIZE) if (re.test(t)) return out;
  return t;
}

// Robust FDC search with scoring
async function searchFDCWithScoring(ingredientName) {
  if (!process.env.FDC_API_KEY) {
    console.log('❌ FDC_API_KEY not configured');
    return null;
  }

  const normalizedName = normalizeName(ingredientName);
  console.log(`🔍 Searching FDC for: "${ingredientName}" → "${normalizedName}"`);

  try {
    // Search with Foundation/SR Legacy/Survey data only
    const searchParams = new URLSearchParams({
      query: normalizedName,
      api_key: process.env.FDC_API_KEY,
      dataType: 'Foundation,SR Legacy,Survey (FNDDS)',
      pageSize: 50,
      sortBy: 'dataType.keyword',
      sortOrder: 'asc'
    });
    
    const url = `https://api.nal.usda.gov/fdc/v1/foods/search?${searchParams}`;
    const response = await fetch(url);
    
    if (!response.ok) {
      console.log(`❌ FDC search failed: ${response.status}`);
      return null;
    }

    const data = await response.json();
    
    if (!data.foods || data.foods.length === 0) {
      console.log(`❌ No FDC results for: ${normalizedName}`);
      return null;
    }

    // Score candidates
    const scoredCandidates = data.foods.slice(0, 20).map(food => {
      const score = calculateFDCMatchScore(food, normalizedName);
      return { ...food, score };
    });

    // Sort by score (highest first)
    scoredCandidates.sort((a, b) => b.score - a.score);

    const bestMatch = scoredCandidates[0];
    
    if (bestMatch && bestMatch.score > 0) {
      console.log(`✅ Found FDC match: ${bestMatch.description} (score: ${bestMatch.score.toFixed(2)})`);
      return {
        fdcId: bestMatch.fdcId,
        description: bestMatch.description,
        dataType: bestMatch.dataType,
        score: bestMatch.score
      };
    } else {
      console.log(`❌ No good FDC match found for: ${normalizedName}`);
      return null;
    }

  } catch (error) {
    console.log(`❌ FDC search error for ${normalizedName}:`, error.message);
    return null;
  }
}

// Calculate FDC match score
function calculateFDCMatchScore(food, searchTerm) {
  let score = 0;
  const description = food.description.toLowerCase();
  const dataType = food.dataType?.toLowerCase() || '';
  
  // Banned tokens that indicate processed/branded foods
  const bannedTokens = [
    "reduced", "low-calorie", "baby", "formula", "supplement", 
    "meal kit", "filling", "mix", "frozen dinner", "snack", 
    "brand", "lite", "diet", "fat-free", "sugar-free", "organic",
    "premium", "gourmet", "artisan", "craft", "specialty"
  ];
  
  // Check for banned tokens
  for (const banned of bannedTokens) {
    if (description.includes(banned)) {
      score -= 10; // Heavy penalty
    }
  }
  
  // Token overlap scoring
  const searchTokens = searchTerm.split(/\s+/).filter(t => t.length > 2);
  const descTokens = description.split(/\s+/).filter(t => t.length > 2);
  
  let matches = 0;
  for (const searchToken of searchTokens) {
    if (descTokens.some(descToken => descToken.includes(searchToken) || searchToken.includes(descToken))) {
      matches++;
    }
  }
  
  // Base score from token overlap
  score += (matches / searchTokens.length) * 10;
  
  // Bonus for exact phrase match
  if (description.includes(searchTerm)) {
    score += 5;
  }
  
  // Data type preference
  if (dataType.includes('foundation')) {
    score += 3;
  } else if (dataType.includes('sr legacy')) {
    score += 2;
  } else if (dataType.includes('survey')) {
    score += 1;
  }
  
  // Prefer raw/fresh items
  if (description.includes('raw') || description.includes('fresh')) {
    score += 2;
  }
  
  return Math.max(0, score); // Don't return negative scores
}

// Helper functions
function titleCase(s) {
  return String(s || '').replace(/\w\S*/g, w => w[0].toUpperCase() + w.slice(1));
}

function round1(x) {
  return Math.round((x || 0) * 10) / 10;
}

// Health check endpoint
app.get("/health", (_, res) => res.json({ ok: true }));

// Root endpoint
app.get("/", (_, res) => res.json({ 
  service: "FDC Nutrition API", 
  status: "running",
  endpoints: ["/health", "/api/analyze-food"]
}));

// Main nutrition analysis endpoint
app.post("/api/analyze-food", async (req, res) => {
  try {
    const { imageBase64, imageUrl, ingredients: clientIngredients } = req.body || {};
    
    if (!imageBase64 && !imageUrl && !clientIngredients) {
      return res.status(400).json({ 
        error: "Provide imageUrl or imageBase64 or ingredients[]" 
      });
    }

    let ingredients = [];

    // Use client ingredients if provided, otherwise call Vision
    if (clientIngredients && Array.isArray(clientIngredients)) {
      ingredients = clientIngredients;
      console.log("📋 Using client-provided ingredients:", ingredients.length);
    } else {
      // Call OpenAI Vision for OCR
      const imageData = imageBase64 || imageUrl;
      if (!imageData) {
        return res.status(400).json({ error: "No image data provided" });
      }

      console.log("🔍 Calling OpenAI Vision for ingredient extraction...");
      
      // Clean base64 data from data URI if present
      let cleanImageData = imageData;
      if (imageData.startsWith('data:image/')) {
        const commaIndex = imageData.indexOf(',');
        if (commaIndex !== -1) {
          cleanImageData = imageData.substring(commaIndex + 1);
          console.log('📸 Extracted base64 data from data URI (length:', cleanImageData.length, ')');
        }
      }
      
      const visionResponse = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          {
            role: "system",
            content: `You are a food ingredient extractor. Analyze the image and extract ONLY ingredient names and weights in grams. 
            Return a JSON object with this exact format: {"ingredients": [{"name": "ingredient name", "grams": weight_in_grams}]}
            Do NOT calculate nutrition, calories, or macros. Only extract the ingredient list.
            If you can't determine the weight, estimate based on typical serving sizes.
            Be specific with ingredient names (e.g., "chicken breast" not just "chicken").
            If multiple ingredients are visible, list them all.
            If no ingredients are visible, return {"ingredients": []}`
          },
          {
            role: "user",
            content: [
              {
                type: "text",
                text: "Extract the ingredients from this food image. Return only the JSON with ingredient names and grams."
              },
              {
                type: "image_url",
                image_url: {
                  url: `data:image/jpeg;base64,${cleanImageData}`
                }
              }
            ]
          }
        ],
        response_format: { type: "json_object" },
        max_tokens: 500
      });

      const visionContent = visionResponse.choices[0]?.message?.content;
      if (!visionContent) {
        return res.status(500).json({ error: "Failed to extract ingredients from image" });
      }

      console.log("🤖 OpenAI Vision response:", visionContent);

      try {
        const parsed = JSON.parse(visionContent);
        ingredients = parsed.ingredients || [];
        console.log("📋 Extracted ingredients:", ingredients.length);
        
        // Validate and clean ingredients
        ingredients = ingredients
          .filter(ing => ing && ing.name && ing.grams)
          .map(ing => ({
            name: ing.name.trim(),
            grams: Math.round(parseFloat(ing.grams) || 0)
          }))
          .filter(ing => ing.grams > 0);
        
        console.log("✅ Validated ingredients:", ingredients);
        
      } catch (parseError) {
        console.error("❌ Failed to parse Vision response:", parseError);
        console.error("Raw response:", visionContent);
        
        // Try to repair JSON if parsing failed
        try {
          const jsonMatch = visionContent.match(/\{[\s\S]*\}/);
          if (jsonMatch) {
            const repaired = JSON.parse(jsonMatch[0]);
            ingredients = repaired.ingredients || [];
            console.log("🔧 Repaired JSON, extracted ingredients:", ingredients.length);
          } else {
            return res.status(500).json({ error: "Failed to parse ingredient extraction" });
          }
        } catch (repairError) {
          console.error("❌ JSON repair failed:", repairError);
          return res.status(500).json({ error: "Failed to parse ingredient extraction" });
        }
      }
    }

    if (ingredients.length === 0) {
      return res.status(400).json({ error: "No ingredients found" });
    }

    // Process ingredients with FDC
    const { totals, perIngredient } = await calculateTotalsFromFDCWithPerIngredient(ingredients);
    
    // Calculate DV percentages
    const dvPct = calculateDVPct(totals);

    // Build response
    const response = {
      ingredients, // augmented with nutrition data
      perIngredient, // detailed breakdown
      macros: {
        calories_kcal: totals.calories_kcal,
        protein_g: totals.protein_g,
        fat_g: totals.fat_g,
        carbs_g: totals.carbs_g
      },
      totals,
      dv_pct: dvPct,
      source: { 
        nutrition: "FDC", 
        vision: clientIngredients ? "Client-provided" : "OpenAI (OCR only)" 
      }
    };

    console.log("📤 Sending response to Flutter app");
    console.log("📊 Response summary:", {
      calories: totals.calories_kcal,
      protein: totals.protein_g,
      ingredients: ingredients.length
    });

    res.json(response);

  } catch (error) {
    console.error("❌ API error:", error);
    res.status(500).json({ 
      error: "Failed to analyze nutrition",
      details: error.message 
    });
  }
});

// Calculate totals from FDC with per-ingredient data
async function calculateTotalsFromFDCWithPerIngredient(ingredients) {
  const totals = makeZeroTotals();
  const perIngredient = [];
  
  for (let idx = 0; idx < ingredients.length; idx++) {
    const ing = ingredients[idx];
    const { name, grams } = ing;
    
    console.log(`🔍 Processing ingredient: ${name} (${grams}g)`);
    
    // Search FDC with robust scoring
    const match = await searchFDCWithScoring(name);
    if (!match) {
      console.log(`❌ No FDC data found for: ${name}`);
      continue;
    }
    
    // Fetch nutrient data
    const fdcData = await fetchFDCData(match.fdcId);
    if (!fdcData) {
      console.log(`❌ Failed to fetch FDC data for: ${name}`);
      continue;
    }
    
    // Extract nutrients
    const per100 = extractPer100(fdcData);
    console.log('FDC per100 for', name, per100);
    
    if (!per100 || Object.keys(per100).length === 0) {
      console.log(`❌ Failed to extract nutrients for: ${name}`);
      continue;
    }
    
    // Scale by grams/100
    const f = (grams || 0) / 100;
    console.log('Factor', f.toFixed(2), 'Scaled protein_g=', ((per100.protein_g||0)*f).toFixed(2));
    
    // Build per-ingredient record with FDC metadata
    const item = {
      name: titleCase(name),
      grams: Math.round(grams),
      fdcId: match.fdcId,
      fdcTitle: match.description,
      dataType: match.dataType,
      calories_kcal: round1((per100.calories_kcal || 0) * f),
      protein_g: round1((per100.protein_g || 0) * f),
      fat_g: round1((per100.fat_g || 0) * f),
      carbs_g: round1((per100.carbs_g || 0) * f),
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
    
    // Augment the original ingredient element
    ingredients[idx] = { ...ingredients[idx], ...item };
    
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
    C: i.carbs_g,
    fdcId: i.fdcId
  })));
  
  return { totals: roundTotals(totals), perIngredient };
}

// Warmup endpoint
app.get("/api/warmup", (_, res) => res.json({ status: "Server is ready" }));

app.listen(PORT, () => {
  console.log(`🚀 FDC Nutrition Server running on port ${PORT}`);
});