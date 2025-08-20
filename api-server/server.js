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

// Deterministic name normalization - map to consistent FDC entries
const NORMALIZE = [
  // Proteins - cooked variants
  [/^chicken( breast)?$/i, "chicken, breast, cooked, roasted, skinless"],
  [/^beef$/i, "beef, ground, cooked"],
  [/^pork$/i, "pork, ground, cooked"],
  [/^salmon$/i, "salmon, cooked"],
  [/^tuna$/i, "tuna, cooked"],
  [/^egg$/i, "egg, whole, cooked"],
  [/^meat filling$/i, "beef, ground, cooked"], // Generic meat filling → ground beef
  [/^ground meat$/i, "beef, ground, cooked"],
  [/^minced meat$/i, "beef, ground, cooked"],
  
  // Starches - cooked variants
  [/^sweet potato(s)?$/i, "sweet potato, baked, flesh only"],
  [/^potato(s)?$/i, "potato, baked, flesh only"],
  [/^rice$/i, "rice, white, cooked"],
  [/^spaghetti$/i, "spaghetti, cooked"],
  [/^pasta$/i, "pasta, cooked"],
  [/^bread|dark bread$/i, "bread, wheat"],
  [/^oatmeal$/i, "oats, cooked"],
  
  // Dairy - improved mappings
  [/^sour cream$/i, "sour cream, cultured"], // More specific mapping
  [/^greek yogurt$/i, "yogurt, Greek, plain, nonfat"],
  [/^yogurt$/i, "yogurt, plain, whole milk"],
  [/^milk$/i, "milk, whole"],
  [/^cheese$/i, "cheese, cheddar"],
  [/^grated cheese$/i, "cheese, parmesan, grated"],
  
  // Vegetables - raw variants
  [/^carrot(s)?$/i, "carrot, raw"],
  [/^broccoli$/i, "broccoli, raw"],
  [/^spinach$/i, "spinach, raw"],
  [/^lettuce$/i, "lettuce, raw"],
  [/^tomato(es)?$/i, "tomato, raw"],
  [/^cucumber$/i, "cucumber, raw"],
  [/^bell pepper$/i, "peppers, sweet, raw"],
  [/^cilantro$/i, "cilantro, raw"],
  [/^parsley$/i, "parsley, raw"],
  
  // Fruits - raw variants
  [/^apple(s)?$/i, "apple, raw, with skin"],
  [/^banana(s)?$/i, "banana, raw"],
  [/^orange(s)?$/i, "orange, raw"],
  [/^pineapple$/i, "pineapple, raw"],
  [/^watermelon$/i, "watermelon, raw"],
  
  // Fats & oils
  [/^butter$/i, "butter, salted"],
  [/^oil$/i, "oil, olive"],
  
  // Condiments & prepared foods
  [/^kimchi$/i, "kimchi"],
  [/^salami$/i, "salami"],
  [/^coleslaw.*$/i, "coleslaw"],
  [/^salsa$/i, "salsa"],
  [/^guacamole$/i, "guacamole"],
  [/^hummus$/i, "hummus"],
  
  // Spices & seasonings
  [/^salt$/i, "salt, table"],
  [/^pepper$/i, "pepper, black"],
  [/^garlic$/i, "garlic, raw"],
  [/^onion(s)?$/i, "onion, raw"],
];

function normalizeName(s) {
  const t = String(s || "").trim().toLowerCase();
  for (const [re, out] of NORMALIZE) {
    if (re.test(t)) {
      console.log(`🔄 Normalized: "${s}" → "${out}"`);
      return out;
    }
  }
  return s; // Return original if no match
}

// Robust FDC search with deterministic filtering
async function searchFDCWithFiltering(ingredientName) {
  if (!process.env.FDC_API_KEY) {
    console.log('❌ FDC_API_KEY not configured');
    return null;
  }

  const normalizedName = normalizeName(ingredientName);
  console.log(`🔍 Searching FDC for: "${ingredientName}" → "${normalizedName}"`);

  try {
    // Search with Foundation/SR Legacy/Survey data only (no brands)
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

    // Score and filter candidates
    const scoredCandidates = data.foods.slice(0, 20).map(food => {
      const score = calculateFDCMatchScore(food, normalizedName);
      return { ...food, score };
    }).filter(food => food.score > 0); // Only keep positive scores

    if (scoredCandidates.length === 0) {
      console.log(`❌ No good FDC matches for: ${normalizedName}`);
      return null;
    }

    // Sort by score (highest first), then by data type preference
    scoredCandidates.sort((a, b) => {
      if (Math.abs(a.score - b.score) < 0.1) {
        // If scores are close, prefer Foundation > SR Legacy > Survey
        const aType = a.dataType?.toLowerCase() || '';
        const bType = b.dataType?.toLowerCase() || '';
        if (aType.includes('foundation') && !bType.includes('foundation')) return -1;
        if (bType.includes('foundation') && !aType.includes('foundation')) return 1;
        if (aType.includes('sr legacy') && !bType.includes('sr legacy')) return -1;
        if (bType.includes('sr legacy') && !aType.includes('sr legacy')) return 1;
      }
      return b.score - a.score;
    });

    const bestMatch = scoredCandidates[0];
    console.log(`✅ Found FDC match: ${bestMatch.description} (score: ${bestMatch.score.toFixed(2)}, type: ${bestMatch.dataType})`);
    
    return {
      fdcId: bestMatch.fdcId,
      description: bestMatch.description,
      dataType: bestMatch.dataType,
      score: bestMatch.score
    };

  } catch (error) {
    console.log(`❌ FDC search error for ${normalizedName}:`, error.message);
    return null;
  }
}

// Calculate FDC match score with strict filtering
function calculateFDCMatchScore(food, searchTerm) {
  let score = 0;
  const description = food.description.toLowerCase();
  const dataType = food.dataType?.toLowerCase() || '';
  
  // Heavy penalties for unwanted items
  const bannedTokens = [
    "reduced", "low-calorie", "baby", "formula", "supplement", 
    "meal kit", "filling", "mix", "frozen dinner", "snack", 
    "brand", "lite", "diet", "fat-free", "sugar-free", "organic",
    "premium", "gourmet", "artisan", "craft", "specialty", "reduced fat",
    "low fat", "skim", "light", "diet", "sugar free", "no sugar"
  ];
  
  // Check for banned tokens - heavy penalty
  for (const banned of bannedTokens) {
    if (description.includes(banned)) {
      score -= 50; // Very heavy penalty
    }
  }
  
  // Token overlap scoring - improved for better matching
  const searchTokens = searchTerm.split(/\s+/).filter(t => t.length > 1); // Reduced minimum length
  const descTokens = description.split(/\s+/).filter(t => t.length > 1);
  
  let matches = 0;
  for (const searchToken of searchTokens) {
    if (descTokens.some(descToken => descToken.includes(searchToken) || searchToken.includes(descToken))) {
      matches++;
    }
  }
  
  // Base score from token overlap - more lenient
  if (searchTokens.length > 0) {
    score += (matches / searchTokens.length) * 25; // Increased from 20
  }
  
  // Bonus for exact phrase match
  if (description.includes(searchTerm)) {
    score += 15; // Increased from 10
  }
  
  // Partial phrase match bonus
  const searchWords = searchTerm.split(/\s+/);
  const descWords = description.split(/\s+/);
  const commonWords = searchWords.filter(word => descWords.some(descWord => descWord.includes(word) || word.includes(descWord)));
  if (commonWords.length >= Math.ceil(searchWords.length * 0.7)) { // 70% word match
    score += 8;
  }
  
  // Data type preference
  if (dataType.includes('foundation')) {
    score += 5;
  } else if (dataType.includes('sr legacy')) {
    score += 3;
  } else if (dataType.includes('survey')) {
    score += 1;
  }
  
  // Prefer cooked/processed items for proteins and starches
  const isProtein = searchTerm.includes('chicken') || searchTerm.includes('beef') || searchTerm.includes('pork') || searchTerm.includes('salmon') || searchTerm.includes('tuna') || searchTerm.includes('meat');
  const isStarch = searchTerm.includes('potato') || searchTerm.includes('rice') || searchTerm.includes('pasta') || searchTerm.includes('bread');
  
  if ((isProtein || isStarch) && (description.includes('cooked') || description.includes('baked') || description.includes('roasted'))) {
    score += 3;
  }
  
  // Prefer raw for fruits/vegetables
  const isProduce = searchTerm.includes('apple') || searchTerm.includes('banana') || searchTerm.includes('carrot') || searchTerm.includes('broccoli') || searchTerm.includes('tomato') || searchTerm.includes('cilantro');
  if (isProduce && description.includes('raw')) {
    score += 2;
  }
  
  // Lower threshold for acceptance - more lenient
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

// Test endpoint for debugging image processing
app.post("/api/test-vision", async (req, res) => {
  try {
    const { imageBase64 } = req.body || {};
    
    if (!imageBase64) {
      return res.status(400).json({ error: "Provide imageBase64" });
    }

    console.log("🧪 TEST VISION - Image data length:", imageBase64.length);
    
    // Clean base64 data
    let cleanImageData = imageBase64;
    if (imageBase64.startsWith('data:image/')) {
      const commaIndex = imageBase64.indexOf(',');
      if (commaIndex !== -1) {
        cleanImageData = imageBase64.substring(commaIndex + 1);
      }
    }
    
    console.log("🧪 TEST VISION - Clean data length:", cleanImageData.length);
    
    const visionResponse = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: "You are a food ingredient extractor. Return JSON: {\"ingredients\": [{\"name\": \"ingredient name\", \"grams\": weight}]}"
        },
        {
          role: "user",
          content: [
            { type: "text", text: "What ingredients do you see in this image?" },
            {
              type: "image_url",
              image_url: { url: `data:image/jpeg;base64,${cleanImageData}` }
            }
          ]
        }
      ],
      response_format: { type: "json_object" },
      max_tokens: 300
    });

    const content = visionResponse.choices[0]?.message?.content;
    
    res.json({
      success: true,
      content: content,
      parsed: content ? JSON.parse(content) : null
    });
    
  } catch (error) {
    console.error("🧪 TEST VISION ERROR:", error);
    res.status(500).json({ 
      error: "Test failed", 
      details: error.message 
    });
  }
});

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
      console.log("📸 Image data type:", typeof imageData);
      console.log("📸 Image data length:", imageData.length);
      
      // Clean base64 data from data URI if present
      let cleanImageData = imageData;
      if (typeof imageData === 'string' && imageData.startsWith('data:image/')) {
        const commaIndex = imageData.indexOf(',');
        if (commaIndex !== -1) {
          cleanImageData = imageData.substring(commaIndex + 1);
          console.log('📸 Extracted base64 data from data URI (length:', cleanImageData.length, ')');
        }
      }
      
      // Basic validation
      if (!cleanImageData || cleanImageData.length < 50) {
        console.error("❌ Invalid base64 data - too short");
        return res.status(400).json({ error: "Invalid image data" });
      }
      
      try {
        // Test base64 decode
        Buffer.from(cleanImageData, 'base64');
        console.log("✅ Base64 data is valid");
      } catch (base64Error) {
        console.error("❌ Invalid base64 data:", base64Error.message);
        return res.status(400).json({ error: "Invalid base64 image data" });
      }
      
      console.log("🤖 Preparing OpenAI Vision request...");
      
      try {
        // Add timeout wrapper to prevent hanging
        const visionPromise = openai.chat.completions.create({
          model: "gpt-4o-mini",
          messages: [
            {
              role: "system",
              content: `Extract food ingredients from image. Return JSON: {"ingredients": [{"name": "food name", "grams": weight}]}. Be quick and accurate.`
            },
            {
              role: "user",
              content: [
                {
                  type: "text",
                  text: "What food ingredients do you see? Return JSON with names and grams."
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
          max_tokens: 200,
          temperature: 0.1
        });

        // Add 30-second timeout
        const timeoutPromise = new Promise((_, reject) => {
          setTimeout(() => reject(new Error('OpenAI Vision timeout')), 30000);
        });

        const visionResponse = await Promise.race([visionPromise, timeoutPromise]);

        console.log("🤖 OpenAI Vision API call completed");
        console.log("🤖 Response status:", visionResponse.choices ? "success" : "failed");
        console.log("🤖 Number of choices:", visionResponse.choices?.length || 0);

        const visionContent = visionResponse.choices[0]?.message?.content;
        if (!visionContent) {
          console.error("❌ No content in OpenAI response");
          console.error("❌ Full response:", JSON.stringify(visionResponse, null, 2));
          return res.status(500).json({ error: "Failed to extract ingredients from image" });
        }

        console.log("🤖 OpenAI Vision response:", visionContent);
        console.log("🤖 Response length:", visionContent.length);

        try {
          const parsed = JSON.parse(visionContent);
          ingredients = parsed.ingredients || [];
          console.log("📋 Extracted ingredients:", ingredients.length);
          console.log("📋 Raw ingredients:", JSON.stringify(ingredients, null, 2));
          
          // Validate and clean ingredients
          ingredients = ingredients
            .filter(ing => ing && ing.name && ing.grams)
            .map(ing => ({
              name: ing.name.trim(),
              grams: Math.round(parseFloat(ing.grams) || 0)
            }))
            .filter(ing => ing.grams > 0);
          
          console.log("✅ Validated ingredients:", ingredients);
          console.log("✅ Final ingredient count:", ingredients.length);
          
          // If no ingredients found, try a more lenient approach
          if (ingredients.length === 0) {
            console.log("⚠️ No ingredients found, trying fallback approach...");
            
            // Try to extract any food items mentioned in the response
            const fallbackIngredients = [];
            const responseText = visionContent.toLowerCase();
            
            // Common food keywords to look for
            const foodKeywords = [
              'chicken', 'beef', 'pork', 'fish', 'salmon', 'tuna',
              'rice', 'pasta', 'bread', 'potato', 'sweet potato',
              'carrot', 'broccoli', 'spinach', 'lettuce', 'tomato',
              'apple', 'banana', 'orange', 'strawberry', 'blueberry',
              'yogurt', 'milk', 'cheese', 'egg', 'butter', 'oil'
            ];
            
            for (const keyword of foodKeywords) {
              if (responseText.includes(keyword)) {
                fallbackIngredients.push({
                  name: keyword,
                  grams: 100 // Default serving size
                });
                console.log(`🔍 Found fallback ingredient: ${keyword}`);
              }
            }
            
            if (fallbackIngredients.length > 0) {
              ingredients = fallbackIngredients;
              console.log("✅ Using fallback ingredients:", ingredients);
            }
          }
          
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
              console.error("❌ No JSON found in response");
              // Try fallback approach even if JSON parsing fails
              console.log("⚠️ Trying fallback ingredient detection...");
              const fallbackIngredients = [];
              const responseText = visionContent.toLowerCase();
              
              const foodKeywords = [
                'chicken', 'beef', 'pork', 'fish', 'salmon', 'tuna',
                'rice', 'pasta', 'bread', 'potato', 'sweet potato',
                'carrot', 'broccoli', 'spinach', 'lettuce', 'tomato',
                'apple', 'banana', 'orange', 'strawberry', 'blueberry',
                'yogurt', 'milk', 'cheese', 'egg', 'butter', 'oil'
              ];
              
              for (const keyword of foodKeywords) {
                if (responseText.includes(keyword)) {
                  fallbackIngredients.push({
                    name: keyword,
                    grams: 100
                  });
                }
              }
              
              if (fallbackIngredients.length > 0) {
                ingredients = fallbackIngredients;
                console.log("✅ Using fallback ingredients from text:", ingredients);
              } else {
                return res.status(500).json({ error: "Failed to parse ingredient extraction" });
              }
            }
          } catch (repairError) {
            console.error("❌ JSON repair failed:", repairError);
            return res.status(500).json({ error: "Failed to parse ingredient extraction" });
          }
        }
        
      } catch (openaiError) {
        console.error("❌ OpenAI Vision API error:", openaiError);
        return res.status(500).json({ 
          error: "OpenAI Vision API failed", 
          details: openaiError.message 
        });
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
        nutrition: "USDA FDC", 
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
    
    // Use the improved searchFDCWithFiltering function for better matches
    const match = await searchFDCWithFiltering(name);
    if (!match) {
      console.log(`❌ No FDC data found for: ${name}`);
      continue;
    }
    
    console.log(`✅ Found FDC match: ${match.description} (${match.dataType})`);
    
    // Fetch nutrient data
    const fdcData = await fetchFDCData(match.fdcId);
    if (!fdcData) {
      console.log(`❌ Failed to fetch FDC data for: ${name}`);
      continue;
    }
    
    console.log(`✅ FDC Data: ${fdcData.description} (${fdcData.dataType})`);
    
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