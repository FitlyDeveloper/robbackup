require('dotenv').config();
// FORCE DEPLOY: Latest version with critical FDC match fixes
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

// Comprehensive name normalization - map to consistent FDC entries
const NORMALIZE = [
  // Proteins - cooked variants
  [/^chicken( breast)?$/i, "chicken, breast, cooked, roasted, skinless"],
  [/^chicken thighs$/i, "chicken, thigh, cooked, roasted, skinless"],
  [/^chicken thigh$/i, "chicken, thigh, cooked, roasted, skinless"],
  [/^beef$/i, "beef, ground, cooked"],
  [/^pork$/i, "pork, ground, cooked"],
  [/^salmon$/i, "salmon, cooked"],
  [/^tuna$/i, "tuna, cooked"],
  [/^egg$/i, "egg, whole, cooked"],
  [/^meat filling$/i, "beef, ground, cooked"],
  [/^ground meat$/i, "beef, ground, cooked"],
  [/^minced meat$/i, "beef, ground, cooked"],
  
  // Starches - cooked variants
  [/^sweet potato(s)?$/i, "sweet potato, baked, flesh only"],
  [/^sweet potatoe(s)?$/i, "sweet potato, baked, flesh only"],
  [/^yam(s)?$/i, "sweet potato, baked, flesh only"],
  [/^potato(s)?$/i, "potato, baked, flesh only"],
  [/^rice$/i, "rice, white, cooked"],
  [/^white rice$/i, "rice, white, cooked"],
  [/^brown rice$/i, "rice, brown, cooked"],
  [/^spaghetti$/i, "spaghetti, cooked"],
  [/^pasta$/i, "pasta, cooked"],
  [/^noodles$/i, "noodles, cooked"],
  [/^bread|dark bread$/i, "bread, wheat"],
  [/^whole grain bread$/i, "bread, whole wheat"],
  [/^whole wheat bread$/i, "bread, whole wheat"],
  [/^oatmeal$/i, "oats, cooked"],
  
  // Dairy
  [/^sour cream$/i, "sour cream, cultured"],
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
  [/^snow peas$/i, "peas, green, raw"],
  [/^snap peas$/i, "snap peas, raw"],
  [/^bean sprouts$/i, "bean sprouts, raw"],
  [/^cilantro$/i, "cilantro, raw"],
  [/^parsley$/i, "parsley, raw"],
  [/^lime$/i, "lime, raw"],
  [/^red chili$/i, "peppers, hot chili, red, raw"],
  [/^hot chili$/i, "peppers, hot chili, red, raw"],
  [/^onion$/i, "onion, raw"],
  [/^yellow onion$/i, "onion, raw"],
  [/^white onion$/i, "onion, raw"],
  
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
  [/^vegetable broth$/i, "vegetable broth"],
  [/^turmeric$/i, "turmeric, ground"],
  
  // Spices & seasonings
  [/^salt$/i, "salt, table"],
  [/^pepper$/i, "pepper, black"],
  [/^garlic$/i, "garlic, raw"],
  // NEW NORMALIZATION FOR CURRENT ISSUES
  [/^coconut$/i, "coconut, raw"],
  [/^gelatin$/i, "gelatin, prepared"],
  [/^mint leaf$/i, "mint, fresh"],
  [/^mint$/i, "mint, fresh"],
  [/^cookie base$/i, "cookie, plain"],
  [/^cookie crust$/i, "cookie, plain"]
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

// Robust FDC search with multiple strategies
async function searchFDCWithFiltering(ingredientName) {
  console.log(`🔍🔍🔍 STARTING FDC SEARCH FOR: "${ingredientName}"`);
  
  if (!process.env.FDC_API_KEY) {
    console.log('❌❌❌ FDC_API_KEY not configured - THIS IS THE PROBLEM!');
    return null;
  }
  
  console.log(`✅ FDC_API_KEY is configured (length: ${process.env.FDC_API_KEY.length})`);

  const normalizedName = normalizeName(ingredientName);
  console.log(`🔍 Searching FDC for: "${ingredientName}" → "${normalizedName}"`);

  // Strategy 1: Try normalized search first
  console.log(`🔄 Strategy 1: Normalized search for "${normalizedName}"`);
  let match = await searchFDCStrategy(normalizedName, 'normalized');
  
  // Strategy 2: If no match, try original name
  if (!match) {
    console.log(`🔄 Strategy 2: Original name search for "${ingredientName}"`);
    match = await searchFDCStrategy(ingredientName, 'original');
  }
  
  // Strategy 3: If still no match, try simplified search
  if (!match) {
    const simplifiedName = simplifyIngredientName(ingredientName);
    console.log(`🔄 Strategy 3: Simplified search for "${simplifiedName}"`);
    match = await searchFDCStrategy(simplifiedName, 'simplified');
  }
  
  // Strategy 4: Last resort - try category-based search
  if (!match) {
    const categorySearch = getCategorySearchTerm(ingredientName);
    if (categorySearch) {
      console.log(`🔄 Strategy 4: Category search for "${categorySearch}"`);
      match = await searchFDCStrategy(categorySearch, 'category');
    }
  }

  // Strategy 5: Fallback to estimated values for common ingredients
  if (!match) {
    const fallbackMatch = getFallbackNutrition(ingredientName);
    if (fallbackMatch) {
      console.log(`🔄 Strategy 5: Using fallback nutrition for "${ingredientName}"`);
      return fallbackMatch;
    }
  }

  if (match) {
    console.log(`✅✅✅ FOUND FDC MATCH: ${match.description} (score: ${match.score.toFixed(2)}, type: ${match.dataType})`);
  } else {
    console.log(`❌❌❌ NO FDC MATCH FOUND for: ${ingredientName}`);
  }
  
  return match;
}

// Individual search strategy
async function searchFDCStrategy(searchTerm, strategy) {
  console.log(`🔍🔍🔍 SEARCH STRATEGY "${strategy}" for "${searchTerm}"`);
  
  try {
    const searchParams = new URLSearchParams({
      query: searchTerm,
      api_key: process.env.FDC_API_KEY,
      dataType: 'Foundation,SR Legacy,Survey (FNDDS)',
      pageSize: 50,
      sortBy: 'dataType.keyword',
      sortOrder: 'asc'
    });
    
    const url = `https://api.nal.usda.gov/fdc/v1/foods/search?${searchParams}`;
    console.log(`🌐 Making FDC API call to: ${url.substring(0, 100)}...`);
    
    const response = await fetch(url);
    
    if (!response.ok) {
      console.log(`❌❌❌ FDC API ERROR: ${response.status} ${response.statusText}`);
      return null;
    }

    const data = await response.json();
    console.log(`📊 FDC API Response: ${data.foods?.length || 0} foods found`);
    
    if (!data.foods || data.foods.length === 0) {
      console.log(`❌ No FDC results for: ${searchTerm}`);
      return null;
    }

    // Score and filter candidates with strategy-specific thresholds
    const scoredCandidates = data.foods.slice(0, 20).map(food => {
      const score = calculateFDCMatchScore(food, searchTerm, strategy);
      return { ...food, score };
    }).filter(food => food.score > getMinScoreForStrategy(strategy));

    console.log(`📊 After scoring: ${scoredCandidates.length} candidates with score > ${getMinScoreForStrategy(strategy)}`);

    if (scoredCandidates.length === 0) {
      console.log(`❌ No good FDC matches for: ${searchTerm}`);
      return null;
    }

    // Sort by score (highest first), then by data type preference
    scoredCandidates.sort((a, b) => {
      if (Math.abs(a.score - b.score) < 0.1) {
        const aType = a.dataType?.toLowerCase() || '';
        const bType = b.dataType?.toLowerCase() || '';
        if (aType.includes('foundation') && !bType.includes('foundation')) return -1;
        if (bType.includes('foundation') && !aType.includes('foundation')) return 1;
        if (aType.includes('sr legacy') && !bType.includes('sr legacy')) return -1;
        if (bType.includes('sr legacy') && !bType.includes('sr legacy')) return 1;
      }
      return b.score - a.score;
    });

    const bestMatch = scoredCandidates[0];
    console.log(`✅ Best match: ${bestMatch.description} (score: ${bestMatch.score.toFixed(2)})`);
    
    return {
      fdcId: bestMatch.fdcId,
      description: bestMatch.description,
      dataType: bestMatch.dataType,
      score: bestMatch.score
    };

  } catch (error) {
    console.log(`❌❌❌ FDC search error for ${searchTerm}:`, error.message);
    return null;
  }
}

// Get minimum score threshold based on search strategy
function getMinScoreForStrategy(strategy) {
  switch (strategy) {
    case 'normalized': return 15;  // Strict for normalized names
    case 'original': return 10;    // Medium for original names
    case 'simplified': return 5;   // Lenient for simplified names
    case 'category': return 3;     // Very lenient for category searches
    default: return 10;
  }
}

// Simplify ingredient name for broader matching
function simplifyIngredientName(name) {
  return name
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim()
    .split(' ')[0]; // Take first word only
}

// Get category-based search term with specific mappings
function getCategorySearchTerm(name) {
  const lowerName = name.toLowerCase();
  
  // Specific mappings to prevent wrong matches
  if (lowerName.includes('snap pea')) return 'snap peas';
  if (lowerName.includes('bean sprout')) return 'bean sprouts';
  if (lowerName.includes('cilantro') || lowerName.includes('coriander')) return 'cilantro';
  if (lowerName.includes('red chili') || lowerName.includes('hot chili')) return 'hot chili peppers';
  if (lowerName.includes('lime')) return 'lime';
  if (lowerName.includes('lemon')) return 'lemon';
  if (lowerName.includes('noodle') || lowerName.includes('pasta')) return 'pasta';
  if (lowerName.includes('rice') && !lowerName.includes('sweet')) return 'rice'; // Rice ≠ Flour
  if (lowerName.includes('onion') && !lowerName.includes('yellow') && !lowerName.includes('white')) return 'onion'; // Onion ≠ Green Onion
  if (lowerName.includes('cilantro') && !lowerName.includes('parsley')) return 'cilantro'; // Cilantro ≠ Blackberries
  
  // Generic fallbacks only for very common items
  if (lowerName.includes('pea') && !lowerName.includes('snap')) return 'peas';
  if (lowerName.includes('chili') && !lowerName.includes('red') && !lowerName.includes('hot')) return 'peppers';
  
  return null;
}

// Calculate FDC match score with strategy-based filtering
function calculateFDCMatchScore(food, searchTerm, strategy) {
  let score = 0;
  const description = food.description.toLowerCase();
  const dataType = food.dataType?.toLowerCase() || '';
  
  // CRITICAL: Check for major category mismatches - instant disqualification
  const searchWords = searchTerm.split(/\s+/).filter(w => w.length > 2);
  const descWords = description.split(/\s+/).filter(w => w.length > 2);
  
  // Check for major category mismatches - instant disqualification
  const isProtein = searchTerm.includes('chicken') || searchTerm.includes('beef') || searchTerm.includes('pork') || searchTerm.includes('salmon') || searchTerm.includes('tuna') || searchTerm.includes('meat');
  const isStarch = searchTerm.includes('potato') || searchTerm.includes('sweet potato') || searchTerm.includes('rice') || searchTerm.includes('pasta') || searchTerm.includes('bread') || searchTerm.includes('noodle');
  const isDairy = searchTerm.includes('cream') || searchTerm.includes('milk') || searchTerm.includes('yogurt') || searchTerm.includes('cheese');
  const isProduce = searchTerm.includes('apple') || searchTerm.includes('banana') || searchTerm.includes('carrot') || searchTerm.includes('broccoli') || searchTerm.includes('tomato') || searchTerm.includes('cilantro') || searchTerm.includes('pea') || searchTerm.includes('sprout') || searchTerm.includes('lime') || searchTerm.includes('chili');
  
  const descIsProtein = description.includes('chicken') || description.includes('beef') || description.includes('pork') || description.includes('salmon') || description.includes('tuna') || description.includes('meat');
  const descIsStarch = description.includes('potato') || description.includes('rice') || description.includes('pasta') || description.includes('bread') || description.includes('noodle');
  const descIsDairy = description.includes('cream') || description.includes('milk') || description.includes('yogurt') || description.includes('cheese');
  const descIsProduce = description.includes('apple') || description.includes('banana') || description.includes('carrot') || description.includes('broccoli') || description.includes('tomato') || description.includes('cilantro') || description.includes('pea') || description.includes('sprout') || description.includes('lime') || description.includes('pepper');
  
  // Instant disqualification for major category mismatches
  if ((isProtein && descIsStarch) || (isProtein && descIsDairy) || (isProtein && descIsProduce)) {
    return -1000;
  }
  if ((isStarch && descIsProtein) || (isStarch && descIsDairy)) {
    return -1000;
  }
  if ((isDairy && descIsProtein) || (isDairy && descIsStarch)) {
    return -1000;
  }
  if ((isProduce && descIsProtein) || (isProduce && descIsDairy)) {
    return -1000;
  }
  
  // CRITICAL: Specific ingredient mismatches - instant disqualification
  if (searchTerm.includes('bean sprout') && description.includes('brussels sprout')) {
    return -1000; // Bean sprouts ≠ Brussels sprouts
  }
  if (searchTerm.includes('cilantro') && description.includes('beet')) {
    return -1000; // Cilantro ≠ Beets
  }
  if (searchTerm.includes('lime') && description.includes('beet')) {
    return -1000; // Lime ≠ Beets
  }
  if (searchTerm.includes('hot chili') && description.includes('bell pepper')) {
    return -1000; // Hot chili ≠ Bell pepper
  }
  if (searchTerm.includes('snap pea') && !description.includes('snap')) {
    return -1000; // Snap peas must contain "snap"
  }
  
  // NEW CRITICAL MISMATCHES
  if (searchTerm.includes('rice') && description.includes('flour')) {
    return -1000; // Rice ≠ Rice flour
  }
  if (searchTerm.includes('rice') && description.includes('raw') && !searchTerm.includes('raw')) {
    return -1000; // Rice ≠ Raw rice (should be cooked)
  }
  if (searchTerm.includes('cilantro') && description.includes('blackberr')) {
    return -1000; // Cilantro ≠ Blackberries
  }
  if (searchTerm.includes('cilantro') && description.includes('blueberr')) {
    return -1000; // Cilantro ≠ Blueberries
  }
  if (searchTerm.includes('onion') && description.includes('green onion') && !searchTerm.includes('green')) {
    return -1000; // Onion ≠ Green onion
  }
  if (searchTerm.includes('onion') && description.includes('scallion') && !searchTerm.includes('scallion')) {
    return -1000; // Onion ≠ Scallion
  }
  // NEW FIXES FOR CURRENT ISSUES
  if (searchTerm.includes('coconut') && description.includes('flour') && !searchTerm.includes('flour')) {
    return -1000; // Coconut ≠ Coconut flour (should be coconut meat)
  }
  if (searchTerm.includes('gelatin') && description.includes('dry powder') && !searchTerm.includes('dry')) {
    return -1000; // Gelatin ≠ Dry powder (should be prepared gelatin)
  }
  if (searchTerm.includes('mint') && description.includes('lettuce') && !searchTerm.includes('lettuce')) {
    return -1000; // Mint ≠ Lettuce
  }
  if (searchTerm.includes('cookie base') && description.includes('oatmeal') && !searchTerm.includes('oatmeal')) {
    return -1000; // Cookie base ≠ Oatmeal cookies
  }
  
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
      score -= 50;
    }
  }
  
  // Token overlap scoring with strategy-based weights
  const searchTokens = searchTerm.split(/\s+/).filter(t => t.length > 2);
  const descTokens = description.split(/\s+/).filter(t => t.length > 2);
  
  let matches = 0;
  for (const searchToken of searchTokens) {
    if (descTokens.some(descToken => descToken.includes(searchToken) || searchToken.includes(descToken))) {
      matches++;
    }
  }
  
  // Base score from token overlap with strategy-based multiplier
  const tokenScore = (matches / searchTokens.length) * 20;
  const strategyMultiplier = strategy === 'normalized' ? 1.5 : strategy === 'original' ? 1.0 : strategy === 'simplified' ? 0.8 : 0.6;
  score += tokenScore * strategyMultiplier;
  
  // Bonus for exact phrase match
  if (description.includes(searchTerm)) {
    score += strategy === 'normalized' ? 30 : 15;
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
  if ((isProtein || isStarch) && (description.includes('cooked') || description.includes('baked') || description.includes('roasted'))) {
    score += 3;
  }
  
  // Prefer raw for fruits/vegetables
  if (isProduce && description.includes('raw')) {
    score += 2;
  }
  
  return Math.max(0, score);
}

// Fallback nutrition for ingredients not in FDC
function getFallbackNutrition(ingredientName) {
  const lowerName = ingredientName.toLowerCase();
  
  // Common fallback values
  const fallbacks = {
    'vegetable broth': {
      fdcId: 'fallback_vegetable_broth',
      description: 'Vegetable broth (estimated)',
      dataType: 'Fallback',
      score: 100,
      calories_kcal: 15, // ~15 kcal per 100g
      protein_g: 0.5,
      fat_g: 0.1,
      carbs_g: 2.5
    },
    'chicken broth': {
      fdcId: 'fallback_chicken_broth',
      description: 'Chicken broth (estimated)',
      dataType: 'Fallback',
      score: 100,
      calories_kcal: 20, // ~20 kcal per 100g
      protein_g: 2.0,
      fat_g: 0.5,
      carbs_g: 1.0
    }
  };
  
  return fallbacks[lowerName] || null;
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

    // Generate gourmet food name from ingredients
    const foodName = generateFoodName(ingredients);

    // Build response
    const response = {
      ingredients: perIngredient,
      perIngredient,
      macros: {
        calories_kcal: round1(totals.calories_kcal),
        protein_g: round1(totals.protein_g),
        fat_g: round1(totals.fat_g),
        carbs_g: round1(totals.carbs_g)
      },
      totals,
      dv_pct: dvPct,
      food_name: foodName, // Use food_name to match Flutter expectations
      source: { 
        nutrition: "USDA FDC", 
        vision: "OpenAI GPT-4o-mini",
        timestamp: new Date().toISOString()
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
    
    // Calculate scaled macros
    const scaledProtein = (per100.protein_g || 0) * f;
    const scaledFat = (per100.fat_g || 0) * f;
    const scaledCarbs = (per100.carbs_g || 0) * f;
    
    // Calculate calories - use FDC calories if available, otherwise calculate from macros
    let calories = (per100.calories_kcal || 0) * f;
    if (calories === 0 && (scaledProtein > 0 || scaledFat > 0 || scaledCarbs > 0)) {
      // Calculate calories from macros: (Protein × 4) + (Fat × 9) + (Carbs × 4)
      calories = (scaledProtein * 4) + (scaledFat * 9) + (scaledCarbs * 4);
      console.log(`🔢 Calculated calories from macros for ${name}: ${calories.toFixed(1)} kcal`);
    }
    
    // Build per-ingredient record with FDC metadata
    const item = {
      name: titleCase(name),
      grams: Math.round(grams),
      fdcId: match.fdcId,
      fdcTitle: match.description,
      dataType: match.dataType,
      calories_kcal: round1(calories),
      protein_g: round1(scaledProtein),
      fat_g: round1(scaledFat),
      carbs_g: round1(scaledCarbs),
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
    totals.calories_kcal += calories;
    totals.protein_g += scaledProtein;
    totals.fat_g += scaledFat;
    totals.carbs_g += scaledCarbs;
    
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

// Generate gourmet food name from ingredients
function generateFoodName(ingredients) {
  if (!ingredients || ingredients.length === 0) {
    return "Analyzed Food";
  }
  
  // Sort ingredients by grams (heaviest first)
  const sortedIngredients = [...ingredients].sort((a, b) => (b.grams || 0) - (a.grams || 0));
  
  // Get top 3 ingredients by weight
  const topIngredients = sortedIngredients.slice(0, 3).map(i => i.name);
  
  // Generate descriptive name based on ingredients
  if (topIngredients.length === 1) {
    return `${titleCase(topIngredients[0])} Dish`;
  } else if (topIngredients.length === 2) {
    return `${titleCase(topIngredients[0])} with ${titleCase(topIngredients[1])}`;
  } else {
    return `${titleCase(topIngredients[0])} with ${titleCase(topIngredients[1])} and ${titleCase(topIngredients[2])}`;
  }
}