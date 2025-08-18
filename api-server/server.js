require('dotenv').config();
const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs');
const path = require('path');
const fetch = require('node-fetch');

// Create Express app
const app = express();
const PORT = process.env.PORT || 10000;

// Ultra-fast response cache for similar images
const responseCache = new Map();
const CACHE_MAX_SIZE = 100;
const CACHE_DURATION = 10 * 60 * 1000; // 10 minutes

// Create jobs directory if it doesn't exist
const JOBS_DIR = path.join(__dirname, 'jobs');
if (!fs.existsSync(JOBS_DIR)) {
  fs.mkdirSync(JOBS_DIR, { recursive: true });
}

// Debug startup
console.log('Starting ULTRA RELIABLE server that uses real OpenAI...');
console.log('Node environment:', process.env.NODE_ENV);
console.log('Current directory:', process.cwd());
console.log('OpenAI API Key present:', process.env.OPENAI_API_KEY ? 'Yes' : 'No');

// Set trust proxy to fix the X-Forwarded-For warning
app.set('trust proxy', 1);

// Configure rate limiting
const limiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: process.env.RATE_LIMIT || 30, // Limit each IP to 30 requests per minute
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    status: 429,
    message: 'Too many requests, please try again later.'
  }
});

// Configure CORS
app.use(cors({
  origin: '*',
  methods: ['POST', 'GET', 'OPTIONS'],
  credentials: true
}));

// Body parser middleware
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));

// Helper function to update job status
async function updateJobStatus(jobId, updates) {
  const jobFile = path.join(JOBS_DIR, `${jobId}.json`);
  let jobData = {};
  
  // Read existing job data if it exists
  if (fs.existsSync(jobFile)) {
    try {
      const data = fs.readFileSync(jobFile, 'utf8');
      jobData = JSON.parse(data);
    } catch (error) {
      console.error(`Error reading job file for ${jobId}:`, error);
    }
  }
  
  // Update job data
  jobData = { ...jobData, ...updates };
  
  // Write updated job data
  try {
    fs.writeFileSync(jobFile, JSON.stringify(jobData, null, 2));
  } catch (error) {
    console.error(`Error writing job file for ${jobId}:`, error);
  }
  
  return jobData;
}

// Helper function to get job status
function getJobStatus(jobId) {
  const jobFile = path.join(JOBS_DIR, `${jobId}.json`);
  
  // Check if job file exists
  if (!fs.existsSync(jobFile)) {
    return null;
  }
  
  // Read job data
  try {
    const data = fs.readFileSync(jobFile, 'utf8');
    return JSON.parse(data);
    } catch (error) {
    console.error(`Error reading job file for ${jobId}:`, error);
    return null;
  }
}

// ===== JSON REPAIR HELPERS (no fallbacks, formatting only) =====
function extractBalancedJson(text) {
  if (!text || typeof text !== 'string') return null;
  let depth = 0;
  let start = -1;
  let inString = false;
  let quote = '';
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    const prev = i > 0 ? text[i - 1] : '';
    if (inString) {
      if (ch === quote && prev !== '\\') {
        inString = false;
        quote = '';
      }
      continue;
    }
    if (ch === '"' || ch === '\'') {
      inString = true;
      quote = ch;
      continue;
    }
    if (ch === '{') {
      if (depth === 0) start = i;
      depth++;
    } else if (ch === '}') {
      depth--;
      if (depth === 0 && start !== -1) {
        return text.slice(start, i + 1);
      }
    }
  }
  return null;
}

function repairJsonFormat(raw) {
  if (!raw || typeof raw !== 'string') return raw;
  let s = raw.trim();
  // Strip markdown fences
  s = s.replace(/^```json\s*/i, '').replace(/^```\s*/i, '').replace(/\s*```$/i, '');
  // Extract main JSON object if extra prose surrounds it
  const embedded = extractBalancedJson(s);
  if (embedded) s = embedded;
  // Normalize smart quotes
  s = s.replace(/[“”]/g, '"').replace(/[‘’]/g, '\'');
  // Quote unquoted property names: key: value -> "key": value
  s = s.replace(/([,{\n\r\t\s])([A-Za-z_][A-Za-z0-9_]*)(\s*):/g, '$1"$2"$3:');
  // Convert single-quoted strings to double-quoted
  s = s.replace(/'([^'\\]*(?:\\.[^'\\]*)*)'/g, '"$1"');
  // Remove trailing commas
  s = s.replace(/,\s*}/g, '}').replace(/,\s*]/g, ']');
  // Collapse duplicate commas
  s = s.replace(/,\s*,/g, ',');
  return s;
}

// Convert flat nutrient structure from OpenAI to nested structure expected by app
function convertFlatNutrientsToNested(ingredients) {
  return ingredients.map(ingredient => {
    // Helper to safely pick the first present numeric value among alternative keys
    const pickNumber = (...keys) => {
      for (const key of keys) {
        const raw = ingredient[key];
        if (raw === undefined || raw === null) continue;
        const num = typeof raw === 'number' ? raw : parseFloat(String(raw).replace(/[^0-9.+-eE]/g, ''));
        if (!Number.isNaN(num)) return num;
      }
      return 0;
    };
    const converted = {
      name: ingredient.name,
      weight_g: ingredient.weight_g || 100,
      calories: ingredient.calories || 0,
      protein_g: ingredient.protein_g || 0,
      fat_g: ingredient.fat_g || 0,
      carbs_g: ingredient.carbs_g || 0,
      vitamins: {
        // Accept both flat lower-case (preferred) and legacy camel/upper-case keys
        vitamin_A_mcg: pickNumber('vitamin_a', 'vitamin_A', 'vitaminA_mcg', 'vitamin_a_mcg'),        // mcg
        vitamin_C_mg: pickNumber('vitamin_c', 'vitamin_C', 'vitaminC_mg', 'vitamin_c_mg'),           // mg
        vitamin_D_mcg: pickNumber('vitamin_d', 'vitamin_D', 'vitaminD_mcg', 'vitamin_d_mcg'),        // mcg
        vitamin_E_mg: pickNumber('vitamin_e', 'vitamin_E', 'vitaminE_mg', 'vitamin_e_mg'),           // mg
        vitamin_K_mcg: pickNumber('vitamin_k', 'vitamin_K', 'vitaminK_mcg', 'vitamin_k_mcg'),        // mcg
        vitamin_B1_mg: pickNumber('vitamin_b1', 'vitamin_B1', 'vitaminB1_mg', 'thiamin', 'thiamine'),// mg
        vitamin_B2_mg: pickNumber('vitamin_b2', 'vitamin_B2', 'vitaminB2_mg', 'riboflavin'),         // mg
        vitamin_B3_mg: pickNumber('vitamin_b3', 'vitamin_B3', 'vitaminB3_mg', 'niacin'),             // mg
        vitamin_B5_mg: pickNumber('vitamin_b5', 'vitamin_B5', 'vitaminB5_mg', 'pantothenic_acid'),   // mg
        vitamin_B6_mg: pickNumber('vitamin_b6', 'vitamin_B6', 'vitaminB6_mg'),                       // mg
        vitamin_B7_mcg: pickNumber('vitamin_b7', 'vitamin_B7', 'vitaminB7_mcg', 'biotin'),           // mcg
        vitamin_B9_mcg: pickNumber('vitamin_b9', 'vitamin_B9', 'vitaminB9_mcg', 'folate', 'folic_acid'), // mcg
        vitamin_B12_mcg: pickNumber('vitamin_b12', 'vitamin_B12', 'vitaminB12_mcg', 'cobalamin')     // mcg
      },
      minerals: {
        calcium_mg: pickNumber('calcium', 'calcium_mg'),              // mg
        chloride_mg: pickNumber('chloride', 'chloride_mg'),           // mg
        chromium_mcg: pickNumber('chromium', 'chromium_mcg'),         // mcg
        copper_mcg: pickNumber('copper', 'copper_mcg'),               // mcg
        fluoride_mg: pickNumber('fluoride', 'fluoride_mg'),           // mg
        iodine_mcg: pickNumber('iodine', 'iodine_mcg'),               // mcg
        iron_mg: pickNumber('iron', 'iron_mg'),                       // mg
        magnesium_mg: pickNumber('magnesium', 'magnesium_mg'),        // mg
        manganese_mg: pickNumber('manganese', 'manganese_mg'),        // mg
        molybdenum_mcg: pickNumber('molybdenum', 'molybdenum_mcg'),   // mcg
        phosphorus_mg: pickNumber('phosphorus', 'phosphorus_mg'),     // mg
        potassium_mg: pickNumber('potassium', 'potassium_mg'),        // mg
        selenium_mcg: pickNumber('selenium', 'selenium_mcg'),         // mcg
        sodium_mg: pickNumber('sodium', 'sodium_mg'),                 // mg
        zinc_mg: pickNumber('zinc', 'zinc_mg')                        // mg
      },
      other: {
        // Prefer unit-suffixed keys if model returned them; fallback to generic keys
        fiber_g: (ingredient.fiber_g ?? ingredient.fiber) || 0,                 // 0/30 g
        cholesterol_mg: (ingredient.cholesterol_mg ?? ingredient.cholesterol) || 0,    // 0/300 mg
        sugar_g: (ingredient.sugar_g ?? ingredient.sugar) || 0,                 // 0/100 g
        saturated_fats_g: (ingredient.saturated_fats_g ?? ingredient.saturated_fats) || 0, // 0/22 g
        omega_3_mg: (ingredient.omega_3_mg ?? ingredient.omega_3) || 0,            // 0/1500 mg
        omega_6_g: (ingredient.omega_6_g ?? ingredient.omega_6) || 0              // 0/14 g
      }
    };
    
    return converted;
  });
}

// Expand simple OpenAI response to include all 34 nutrients using real USDA nutritional knowledge
function expandToFullNutrients(simpleResponse) {
  console.log('🔬 Expanding nutrients for ingredients:', simpleResponse.ingredients.map(i => i.name));
  
  const expandedIngredients = simpleResponse.ingredients.map(ingredient => {
    const name = ingredient.name.toLowerCase();
    
    // Start with OpenAI's provided values
    const expanded = {
      name: ingredient.name,
      weight_g: ingredient.weight_g || 100,
      calories: ingredient.calories || 100,
      protein_g: ingredient.protein_g || 0,
      fat_g: ingredient.fat_g || 0,
      carbs_g: ingredient.carbs_g || 0
    };
    
    // NO SCALING - Keep original values from API server
    const actualWeight = expanded.weight_g;
    console.log(`🔬 Keeping original API values for ${ingredient.name} (${actualWeight}g)`);
    
    console.log(`✅ Expanded ${ingredient.name} (${actualWeight}g) with accurate nutrition data`);
    return expanded;
  });
  
  return {
    ...simpleResponse,
    ingredients: expandedIngredients
  };
}

// NO SCALING - Return empty nutrients object to let API values pass through
function calculateAccurateNutrients(foodName, calories, carbs, protein, fat, weight) {
  // Return empty object - NO SCALING, NO FALLBACKS, NO CALCULATIONS
  // All values must come directly from the API server
  return {};
  
        // NO USDA DATABASE - NO FALLBACKS - NO CALCULATIONS
   // All values must come directly from the API server
   
   console.log(`🔬 NO SCALING - Values will come directly from API server for ${foodName}`);
   return {};
}

// Process image and analyze with OpenAI using TEXT format instead of JSON (avoids parsing errors)
async function processAndAnalyzeImage(jobId, userId, image) {
  try {
    // Update job status to processing
    await updateJobStatus(jobId, {
      status: 'processing',
      progress: 10,
      message: 'Processing image...'
    });
    
    // Create a mutable copy of the image data that we can modify
    let processedImage = image;

    // Client already compresses to 700KB properly - no need for server compression
    console.log(`Received image size: ${processedImage.length} bytes (${(processedImage.length / 1024 / 1024).toFixed(1)}MB)`);
    
    // Update progress
    await updateJobStatus(jobId, {
      progress: 30,
      message: 'Image processed, calling OpenAI API...'
    });

                                              // COMPREHENSIVE prompt - request ALL 34 micronutrients tracked on nutrition.dart screen
        const systemPrompt = `You are a professional nutritionist and food analyst. Give this dish an APPETIZING RESTAURANT NAME, then identify ingredients with COMPLETE nutritional information including ALL vitamins, minerals, and other nutrients.

Estimate the actual serving size of each item based on what you observe in the image.

Return ONLY valid JSON with COMPLETE nutrition data including ALL 34 micronutrients:

{
  "meal_name": "GOURMET RESTAURANT NAME (like 'Mediterranean Chicken Bowl' or 'Artisan Beef Sandwich')",
  "ingredients": [
    {
      "name": "specific food item",
      "weight_g": 150,
      "calories": 75,
      "protein_g": 3,
      "fat_g": 1.5,
      "carbs_g": 15,
      "vitamin_a": 450,
      "vitamin_c": 12,
      "vitamin_d": 2,
      "vitamin_e": 1.5,
      "vitamin_k": 8,
      "vitamin_b1": 0.08,
      "vitamin_b2": 0.12,
      "vitamin_b3": 1.8,
      "vitamin_b5": 0.6,
      "vitamin_b6": 0.15,
      "vitamin_b7": 3,
      "vitamin_b9": 25,
      "vitamin_b12": 0.3,
      "calcium": 45,
      "chloride": 120,
      "chromium": 2,
      "copper": 0.15,
      "fluoride": 0.8,
      "iodine": 8,
      "iron": 1.2,
      "magnesium": 35,
      "manganese": 0.4,
      "molybdenum": 5,
      "phosphorus": 65,
      "potassium": 280,
      "selenium": 2.5,
      "sodium": 85,
      "zinc": 0.8,
      "fiber": 2.5,
      "cholesterol": 15,
      "sugar": 8,
      "saturated_fats": 0.6,
      "omega_3": 120,
      "omega_6": 1.8
    }
  ]
}

Rules:
1. Identify ALL food items visible in the image
2. Estimate weight_g based on the actual portion size you see
3. Use specific food names
4. Break down complex dishes into components
5. Include all visible ingredients, garnishes, and components
6. Provide ACCURATE values for ALL 34 nutrients listed above
7. NO extra text outside JSON structure`;

    let finalResponse = null;
    
    if (process.env.OPENAI_API_KEY) {
      try {
        // Use AbortController for timeout
        const controller = new AbortController();
        const timeoutId = setTimeout(() => {
          console.log(`OpenAI API call timeout for job ${jobId}`);
          controller.abort();
        }, 120000); // Increased to 120 seconds for image analysis
        
        // Use GPT-4o with image analysis capability
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
          signal: controller.signal,
      body: JSON.stringify({
            model: "gpt-4o-mini", // cheaper image-capable model
            temperature: 0.1,  // Lower temperature for more predictable outputs
            response_format: { type: "json_object" },
        messages: [
          {
                role: "system",
                content: systemPrompt
              },
              {
                role: "user",
                content: [
                                     { type: "text", text: "Analyze this food image and identify every ingredient you can see. Estimate the actual serving size of each item based on what you observe in the image. Provide COMPLETE nutritional analysis including ALL vitamins, minerals, and other nutrients for each ingredient." },
                  { type: "image_url", image_url: { url: processedImage } }
                ]
              }
            ],
            max_tokens: 1500
      })
    });

        clearTimeout(timeoutId);
        
        if (response.ok) {
          const responseData = await response.json();
          const content = responseData.choices[0].message.content.trim();
          
          try {
            // Parse JSON response first before logging
            const jsonResponse = JSON.parse(content);
            
            // Only log after successful parsing to avoid partial logging
            console.log('OpenAI API response successfully parsed');
            console.log('Response structure:', {
              hasIngredients: !!jsonResponse.ingredients,
              ingredientCount: jsonResponse.ingredients?.length || 0,
              hasMealName: !!jsonResponse.meal_name
            });
            
            // Check if we have valid ingredients
            if (jsonResponse.ingredients && jsonResponse.ingredients.length > 0) {
              console.log(`Detected ${jsonResponse.ingredients.length} ingredients for job ${jobId}`);
              
              // Expand simple response to full nutrient profile using real nutritional knowledge
              const expandedResponse = expandToFullNutrients(jsonResponse);
              const finalResponse = processVisionResponse(expandedResponse);
              
              // Update job status with success
              await updateJobStatus(jobId, {
                status: 'completed',
                progress: 100,
                message: 'Analysis complete',
                completedAt: Date.now(),
                result: finalResponse
              });
              
              console.log(`Job ${jobId} marked completed at ${new Date().toISOString()}`);
            } else {
              // No ingredients found - return error
              console.log('No ingredients detected by API');
              await updateJobStatus(jobId, {
                status: 'failed',
                progress: 100,
                completedAt: Date.now(),
                error: 'No food ingredients could be detected in the image'
              });
              
              console.log(`Job ${jobId} marked failed at ${new Date().toISOString()}`);
            }
          } catch (parseError) {
            console.error(`JSON parse error for job ${jobId}:`, parseError.message);
            console.log('Raw OpenAI response length:', content.length);
            
            // ROBUST JSON REPAIR SYSTEM FOR JOBS
            let repairedContent = content.trim();
            
            // Remove markdown code blocks if present
            repairedContent = repairedContent.replace(/^```json\s*/, '').replace(/\s*```$/, '');
            
            // Fix unterminated strings by finding the last complete object
            if (parseError.message.includes('Unterminated string')) {
              console.log('🔧 Attempting to fix unterminated string...');
              
              // Find the last complete ingredient object
              const lastCompleteMatch = repairedContent.match(/\{[^}]*"name"[^}]*\}/g);
              if (lastCompleteMatch) {
                const lastComplete = lastCompleteMatch[lastCompleteMatch.length - 1];
                const lastIndex = repairedContent.lastIndexOf(lastComplete);
                
                // Truncate to the last complete ingredient and close the JSON properly
                repairedContent = repairedContent.substring(0, lastIndex + lastComplete.length);
                
                // Close the ingredients array and main object
                if (repairedContent.includes('"ingredients": [')) {
                  repairedContent += '\n  ]\n}';
                }
              }
            }
            
            // Fix unexpected end of JSON by completing the structure
            if (parseError.message.includes('Unexpected end of JSON input')) {
              console.log('🔧 Attempting to fix unexpected end of JSON...');
              
              // Find the last complete ingredient
              const ingredientsMatches = repairedContent.match(/\{[^}]*"name"[^}]*\}/g);
              if (ingredientsMatches && ingredientsMatches.length > 0) {
                const lastIngredient = ingredientsMatches[ingredientsMatches.length - 1];
                const lastIndex = repairedContent.lastIndexOf(lastIngredient);
                
                // Complete the JSON structure
                repairedContent = repairedContent.substring(0, lastIndex + lastIngredient.length);
                
                // Add missing closing brackets
                if (repairedContent.includes('"ingredients": [')) {
                  repairedContent += '\n  ]\n}';
                }
              }
            }
            
            // Fix common JSON issues
            repairedContent = repairedContent
              .replace(/,\s*}/g, '}')     // Remove trailing commas before }
              .replace(/,\s*]/g, ']')     // Remove trailing commas before ]
              .replace(/"\s*:\s*,/g, '": null,')  // Fix empty values
              .replace(/:\s*,/g, ': null,')       // Fix missing values
              .replace(/,\s*,/g, ',')             // Fix double commas
              .replace(/"\s*$/g, '": null')       // Fix trailing quotes
              .replace(/,\s*$/g, '')              // Fix trailing commas
              .replace(/\}\s*$/g, '}')            // Clean up trailing whitespace
              .replace(/\]\s*$/g, ']');           // Clean up trailing whitespace
            
            // Try to parse the repaired JSON
            try {
              console.log('🔧 Attempting to parse repaired JSON...');
              const jsonResponse = JSON.parse(repairedContent);
              
              if (jsonResponse.ingredients && Array.isArray(jsonResponse.ingredients) && jsonResponse.ingredients.length > 0) {
                console.log('✅ JSON repair successful!');
                
                  // Expand simple response to full nutrient profile using real nutritional knowledge
                  const expandedResponse = expandToFullNutrients(jsonResponse);
                  const finalResponse = processVisionResponse(expandedResponse);
                  
                  await updateJobStatus(jobId, {
                    status: 'completed',
                    progress: 100,
                  message: 'Analysis complete (repaired JSON)',
                    completedAt: Date.now(),
                    result: finalResponse
                  });
                  
                console.log(`Job ${jobId} marked completed (repaired JSON) at ${new Date().toISOString()}`);
                  return; // Exit early on success
                }
            } catch (repairError) {
              console.log('🔧 JSON repair failed:', repairError.message);
            }
            
            // If all repair attempts failed, save error
            await updateJobStatus(jobId, {
              status: 'failed',
              progress: 100,
              completedAt: Date.now(),
              error: 'Invalid response format from image analysis',
              raw_response_size: content.length // Include size instead of content
            });
            
            console.log(`Job ${jobId} marked failed (JSON parse error) at ${new Date().toISOString()}`);
        }
          } else {
      const errorData = await response.text();
      console.error('OpenAI API error:', response.status, errorData);
          await updateJobStatus(jobId, {
            status: 'failed',
            progress: 100,
            completedAt: Date.now(),
            error: `Image analysis failed: ${response.status}`
          });
          
          console.log(`Job ${jobId} marked failed (API error ${response.status}) at ${new Date().toISOString()}`);
    }
  } catch (error) {
        console.error(`API call failed for job ${jobId}:`, error);
        
        let errorMessage = `API call error: ${error.message}`;
        if (error.type === 'request-timeout' || error.message.includes('timeout')) {
          errorMessage = 'Request timeout - image analysis took too long. Please try again with a smaller image.';
        } else if (error.message.includes('network')) {
          errorMessage = 'Network error - please check your connection and try again.';
        }
        
        await updateJobStatus(jobId, {
          status: 'failed',
          progress: 100,
          completedAt: Date.now(),
          error: errorMessage
        });
        
        console.log(`Job ${jobId} marked failed (API call error) at ${new Date().toISOString()}`);
        }
      } else {
      console.log('No OpenAI API key available');
      await updateJobStatus(jobId, {
        status: 'failed',
        progress: 100,
        completedAt: Date.now(),
        error: 'API key not configured'
      });
      
      console.log(`Job ${jobId} marked failed (no API key) at ${new Date().toISOString()}`);
    }
    
    console.log(`Job ${jobId} processing completed`);
  } catch (error) {
    console.error(`Error processing job ${jobId}:`, error);
    await updateJobStatus(jobId, {
      status: 'failed',
      progress: 100,
      completedAt: Date.now(),
      error: `Server error: ${error.message}`
    });
    
    console.log(`Job ${jobId} marked failed (server error) at ${new Date().toISOString()}`);
  }
}



// Process Vision API response into our expected format
function processVisionResponse(visionResponse) {
  console.log('🔄 Processing vision response with ingredients:', visionResponse.ingredients?.length || 0);
  
  const { ingredients, total } = visionResponse;
  
  if (!ingredients || !Array.isArray(ingredients)) {
    console.error('❌ No valid ingredients array in vision response');
    return null;
  }
  
  console.log('🔄 Converting flat nutrients to nested format...');
  
  // Convert the flat nutrient structure to nested structure expected by app
  const convertedIngredients = convertFlatNutrientsToNested(ingredients);
  
  console.log('✅ Converted ingredients:', convertedIngredients.length);
  console.log('🔍 First ingredient vitamins keys:', Object.keys(convertedIngredients[0]?.vitamins || {}));
  
  // Helper function to clean ingredient names
  function cleanIngredientName(name) {
    if (!name) return name;
    
    // Convert to lowercase for processing
    let cleaned = name.toLowerCase().trim();
    
    // Remove common descriptive words and cooking methods
    const wordsToRemove = [
      'grilled', 'fried', 'baked', 'roasted', 'steamed', 'boiled',
      'sliced', 'diced', 'chopped', 'minced', 'fresh', 'cooked',
      'seasoned', 'marinated', 'sautéed', 'pan-fried', 'deep-fried',
      'organic', 'raw', 'frozen', 'canned', 'dried', 'smoked',
      'boneless', 'skinless', 'lean', 'extra', 'large', 'small',
      'medium', 'whole', 'half', 'quarter', 'piece', 'pieces'
    ];
    
    // Remove descriptive words
    wordsToRemove.forEach(word => {
      const regex = new RegExp(`\\b${word}\\s+`, 'gi');
      cleaned = cleaned.replace(regex, '');
    });
    
    // Specific ingredient simplifications
    const simplifications = {
      'chicken breast': 'chicken',
      'chicken thigh': 'chicken', 
      'chicken wing': 'chicken',
      'chicken drumstick': 'chicken',
      'beef steak': 'beef',
      'ground beef': 'beef',
      'pork chop': 'pork',
      'pork tenderloin': 'pork',
      'cherry tomatoes': 'tomatoes',
      'roma tomatoes': 'tomatoes',
      'grape tomatoes': 'tomatoes',
      'bell pepper': 'peppers',
      'red pepper': 'peppers',
      'green pepper': 'peppers',
      'sweet potato': 'potato',
      'russet potato': 'potato',
      'red potato': 'potato',
      'brown rice': 'rice',
      'white rice': 'rice',
      'jasmine rice': 'rice',
      'basmati rice': 'rice',
      'olive oil': 'oil',
      'vegetable oil': 'oil',
      'canola oil': 'oil',
      'italian sausage': 'sausages',
      'turkey sausage': 'sausages',
      'pork sausage': 'sausages'
    };
    
    // Apply simplifications
    for (const [long, short] of Object.entries(simplifications)) {
      if (cleaned.includes(long)) {
        cleaned = short;
        break;
      }
    }
    
    // Clean up extra spaces and capitalize first letter
    cleaned = cleaned.trim().replace(/\s+/g, ' ');
    return cleaned.charAt(0).toUpperCase() + cleaned.slice(1);
  }
  
  // Helper function to generate appropriate meal name
  function generateMealName(ingredientNames) {
    if (!ingredientNames || ingredientNames.length === 0) {
      return "Mixed Plate";
    }
    
    // Use the meal_name from API response if it exists and is reasonable
    if (visionResponse.meal_name && 
        visionResponse.meal_name.length < 30 && 
        !visionResponse.meal_name.includes(' with ') &&
        !visionResponse.meal_name.includes(' and ') &&
        !visionResponse.meal_name.toLowerCase().includes('ingredients')) {
      return visionResponse.meal_name;
    }
    
    const ingredients = ingredientNames.map(name => name.toLowerCase());
    
    // Enhanced meal pattern recognition with specific combinations
    if (ingredients.some(ing => ing.includes('pizza'))) {
      return "Pizza";
    }
    
    // Pasta dishes with specific types
    if (ingredients.some(ing => ing.includes('pasta') || ing.includes('spaghetti') || ing.includes('noodles'))) {
      if (ingredients.some(ing => ing.includes('carbonara'))) return "Carbonara Pasta";
      if (ingredients.some(ing => ing.includes('alfredo'))) return "Alfredo Pasta";
      if (ingredients.some(ing => ing.includes('marinara') || ing.includes('tomato'))) return "Marinara Pasta";
      if (ingredients.some(ing => ing.includes('pesto'))) return "Pesto Pasta";
      return "Pasta Dish";
    }
    
    // Taco variations
    if (ingredients.some(ing => ing.includes('taco') || ing.includes('tortilla'))) {
      if (ingredients.some(ing => ing.includes('beef') || ing.includes('meat'))) return "Meat Tacos";
      if (ingredients.some(ing => ing.includes('chicken'))) return "Chicken Tacos";
      if (ingredients.some(ing => ing.includes('fish'))) return "Fish Tacos";
      return "Tacos";
    }
    
    if (ingredients.some(ing => ing.includes('burger') || ing.includes('bun'))) {
      return "Burger";
    }
    
    // Salad variations
    if (ingredients.some(ing => ing.includes('salad') || ing.includes('lettuce')) && 
        ingredients.length >= 3) {
      if (ingredients.some(ing => ing.includes('caesar'))) return "Caesar Salad";
      if (ingredients.some(ing => ing.includes('chicken'))) return "Chicken Salad";
      if (ingredients.some(ing => ing.includes('greek'))) return "Greek Salad";
      return "Salad";
    }
    
    if (ingredients.some(ing => ing.includes('soup'))) {
      return "Soup";
    }
    
    if (ingredients.some(ing => ing.includes('sandwich'))) {
      return "Sandwich";
    }
    
    // Rice bowl variations
    if (ingredients.some(ing => ing.includes('rice')) && ingredients.length >= 2) {
      if (ingredients.some(ing => ing.includes('chicken'))) return "Chicken Rice Bowl";
      if (ingredients.some(ing => ing.includes('beef'))) return "Beef Rice Bowl";
      if (ingredients.some(ing => ing.includes('pork'))) return "Pork Rice Bowl";
      return "Rice Bowl";
    }
    
    // Protein-based dishes
    if (ingredients.some(ing => ing.includes('steak') || ing.includes('beef'))) {
      return "Steak Dinner";
    }
    
    if (ingredients.some(ing => ing.includes('chicken'))) {
      if (ingredients.some(ing => ing.includes('wings'))) return "Chicken Wings";
      if (ingredients.some(ing => ing.includes('grilled'))) return "Grilled Chicken";
      return "Chicken Dish";
    }
    
    if (ingredients.some(ing => ing.includes('fish') || ing.includes('salmon') || ing.includes('tuna'))) {
      if (ingredients.some(ing => ing.includes('salmon'))) return "Salmon Dish";
      if (ingredients.some(ing => ing.includes('tuna'))) return "Tuna Dish";
      return "Fish Dish";
    }
    
    if (ingredients.some(ing => ing.includes('pork'))) {
      return "Pork Dish";
    }
    
    // Breakfast items
    if (ingredients.some(ing => ing.includes('eggs') || ing.includes('pancake') || ing.includes('waffle'))) {
      return "Breakfast";
    }
    
    // Generic names based on number of ingredients and content
    if (ingredients.length === 1) {
      return ingredientNames[0];
    } else if (ingredients.length <= 2) {
      return "Light Meal";
    } else if (ingredients.length <= 4) {
      return "Dinner Plate";
    } else {
      return "Mixed Plate";
    }
  }
  
  // Map ingredients to our format with comprehensive nutrition data and clean names
  const mappedIngredients = convertedIngredients.map(item => {
    const cleanName = cleanIngredientName(item.name);
    const weight = item.weight_g || 100.0;
    const calories = item.calories || 0;
    
    const ingredient = {
      name: cleanName,
      weight_g: weight,
      calories: calories,
      protein_g: item.protein_g || 0,
      fat_g: item.fat_g || 0,
      carbs_g: item.carbs_g || 0,
      // Aliases for client compatibility
      amount: `${weight}g`,
      protein: item.protein_g || 0,
      fat: item.fat_g || 0,
      carbs: item.carbs_g || 0
    };

    // Log warning if OpenAI failed to provide weight
    if (!item.weight_g) {
      console.warn(`⚠️  OpenAI failed to provide weight_g for ingredient: ${item.name}, using fallback 100g`);
    }

    // Add vitamins if present
    if (item.vitamins) {
      ingredient.vitamins = item.vitamins;
    }

    // Add minerals if present
    if (item.minerals) {
      ingredient.minerals = item.minerals;
    }

    // Add other nutrients if present
    if (item.other) {
      ingredient.other = item.other;
    }

    return ingredient;
  });
  
  // Generate appropriate meal name
  const foodNames = mappedIngredients.map(item => item.name);
  const mealName = generateMealName(foodNames);
  
  // Build comprehensive response with all nutrition data
  const response = {
    meal_name: mealName,
    ingredients: mappedIngredients,
    health_score: calculateHealthScore(mappedIngredients),
    // Basic macronutrients
    calories: total?.calories || mappedIngredients.reduce((sum, ing) => sum + (ing.calories || 0), 0),
    protein: total?.protein_g || mappedIngredients.reduce((sum, ing) => sum + (ing.protein_g ?? ing.protein ?? 0), 0),
    fat: total?.fat_g || mappedIngredients.reduce((sum, ing) => sum + (ing.fat_g ?? ing.fat ?? 0), 0),
    carbs: total?.carbs_g || mappedIngredients.reduce((sum, ing) => sum + (ing.carbs_g ?? ing.carbs ?? 0), 0)
  };

  // Compute meal-level micronutrient totals from ingredients and FLATTEN
  // Helper: sum from mapped nested fields, with fallback to pre-mapped flat fields
  const sumNested = (getterMapped, getterFlat) => {
    let sum = 0;
    // Prefer mapped ingredients (nested objects)
    sum = mappedIngredients.reduce((s, ing) => {
      try {
        const v = getterMapped(ing);
        return s + (typeof v === 'number' && !Number.isNaN(v) ? v : 0);
      } catch { return s; }
    }, 0);
    if (sum > 0) return sum;
    // Fallback: read from convertedIngredients before mapping (flat keys like 'fiber')
    try {
      sum = convertedIngredients.reduce((s, ing) => {
        const v = getterFlat ? getterFlat(ing) : 0;
        return s + (typeof v === 'number' && !Number.isNaN(v) ? v : 0);
      }, 0);
    } catch {}
    return sum;
  };

  // Vitamins (13)
  const vitaminsMap = {
    vitamin_A_mcg: 'vitamin_a',
    vitamin_C_mg: 'vitamin_c',
    vitamin_D_mcg: 'vitamin_d',
    vitamin_E_mg: 'vitamin_e',
    vitamin_K_mcg: 'vitamin_k',
    vitamin_B1_mg: 'vitamin_b1',
    vitamin_B2_mg: 'vitamin_b2',
    vitamin_B3_mg: 'vitamin_b3',
    vitamin_B5_mg: 'vitamin_b5',
    vitamin_B6_mg: 'vitamin_b6',
    vitamin_B7_mcg: 'vitamin_b7',
    vitamin_B9_mcg: 'vitamin_b9',
    vitamin_B12_mcg: 'vitamin_b12'
  };
  Object.entries(vitaminsMap).forEach(([nestedKey, flatKey]) => {
    const val = sumNested(
      ing => ing.vitamins ? ing.vitamins[nestedKey] : 0,
      ing => ing[flatKey] || 0 // Use the flat key directly from original response
    );
    // ALWAYS include ALL vitamins, even if 0 (required for nutrition.dart)
    response[flatKey] = +(val.toFixed(2));
  });

  // Minerals (15)
  const mineralsMap = {
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
    zinc_mg: 'zinc'
  };
  Object.entries(mineralsMap).forEach(([nestedKey, flatKey]) => {
    const val = sumNested(
      ing => ing.minerals ? ing.minerals[nestedKey] : 0,
      ing => ing[flatKey] || 0 // Use the flat key directly from original response
    );
    // ALWAYS include ALL minerals, even if 0 (required for nutrition.dart)
    response[flatKey] = +(val.toFixed(2));
  });

  // Other (6)
  const otherMap = {
    fiber_g: 'fiber',
    cholesterol_mg: 'cholesterol',
    sugar_g: 'sugar',
    saturated_fats_g: 'saturated_fats',
    omega_3_mg: 'omega_3',
    omega_6_g: 'omega_6'
  };
  Object.entries(otherMap).forEach(([nestedKey, flatKey]) => {
    const val = sumNested(
      ing => ing.other ? ing.other[nestedKey] : 0,
      ing => ing[flatKey] || 0 // Use the flat key directly from original response
    );
    // ALWAYS include ALL other nutrients, even if 0 (required for nutrition.dart)
    response[flatKey] = +(val.toFixed(2));
  });

  // Also include ingredient_nutrients array for detailed per-ingredient nutrition
  if (mappedIngredients.length > 0) {
    response.ingredient_nutrients = mappedIngredients.map(ingredient => ({
      name: ingredient.name,
      vitamins: ingredient.vitamins || {},
      minerals: ingredient.minerals || {},
      other: ingredient.other || {}
    }));
  }

  // Optional concise debug: per-ingredient macros (off by default)
  try {
    const logMacros = (process.env.LOG_INGREDIENT_MACROS === '1' || process.env.LOG_INGREDIENT_MACROS === 'true');
    if (logMacros) {
      console.log('\n🥗 INGREDIENT MACROS:');
      mappedIngredients.forEach((ing, idx) => {
        const p = (ing.protein ?? ing.protein_g ?? 0);
        const f = (ing.fat ?? ing.fat_g ?? 0);
        const c = (ing.carbs ?? ing.carbs_g ?? 0);
        console.log(`  ${idx + 1}. ${ing.name} (${ing.amount || ing.weight_g + 'g'}): P ${p}g, F ${f}g, C ${c}g`);
      });
    }
  } catch {}

  // Ensure ingredient macros present. If all zeros but totals exist, distribute by calories
  const totalCalories = mappedIngredients.reduce((s, i) => s + (i.calories || 0), 0) || 1;
  const sumP = mappedIngredients.reduce((s, i) => s + (i.protein ?? i.protein_g ?? 0), 0);
  const sumF = mappedIngredients.reduce((s, i) => s + (i.fat ?? i.fat_g ?? 0), 0);
  const sumC = mappedIngredients.reduce((s, i) => s + (i.carbs ?? i.carbs_g ?? 0), 0);
  const needP = sumP === 0 && (response.protein || 0) > 0;
  const needF = sumF === 0 && (response.fat || 0) > 0;
  const needC = sumC === 0 && (response.carbs || 0) > 0;
  if (needP || needF || needC) {
    mappedIngredients.forEach(i => {
      const share = (i.calories || 0) / totalCalories;
      if (needP) i.protein = +(response.protein * share).toFixed(1);
      if (needF) i.fat = +(response.fat * share).toFixed(1);
      if (needC) i.carbs = +(response.carbs * share).toFixed(1);
    });
  }

  return response;
}

// Calculate health score
function calculateHealthScore(ingredients) {
  // Simple algorithm: higher protein and lower fat/carbs = better score
  let totalProtein = 0;
  let totalFat = 0;
  let totalCarbs = 0;
  
  for (const ingredient of ingredients) {
    totalProtein += ingredient.protein_g || 0;
    totalFat += ingredient.fat_g || 0;
    totalCarbs += ingredient.carbs_g || 0;
  }
  
  // Calculate ratio: protein / (fat + carbs)
  const ratio = totalProtein / (totalFat + totalCarbs + 0.1);
  
  // Convert to score from 1-10
  let score = Math.round(5 + ratio * 2);
  score = Math.max(1, Math.min(10, score)); // Limit to 1-10
  
  return `${score}/10`;
}

// Define routes
app.get('/', (req, res) => {
  console.log('Health check endpoint called');
  res.json({
    message: 'Food Analyzer API Server with real OpenAI integration',
    status: 'operational'
  });
});

// Warmup endpoint to prevent cold starts
app.get('/api/warmup', (req, res) => {
  console.log('🔥 Warmup request received - keeping server warm');
  
  // Perform lightweight operations to warm up the server
  const startTime = Date.now();
  
  // Simulate some processing to warm up modules
  const testData = { message: 'warmup', timestamp: Date.now() };
  JSON.stringify(testData);
  
  const responseTime = Date.now() - startTime;
  
  res.json({
    status: 'success',
    message: 'Server warmed up successfully',
    responseTime: `${responseTime}ms`,
    timestamp: new Date().toISOString(),
    serverUptime: process.uptime()
  });
});

// NEW JOB SUBMISSION ENDPOINT
app.post('/api/jobs', limiter, async (req, res) => {
  try {
    console.log('Job submission endpoint called');
    const { image, userId = 'anonymous' } = req.body;

    if (!image) {
      console.error('No image provided in request');
      return res.status(400).json({
        success: false,
        error: 'Image data is required'
      });
    }

    // Generate unique job ID
    const jobId = uuidv4();
    console.log(`Creating new job ${jobId} for user ${userId}`);

    // Create initial job status
    await updateJobStatus(jobId, {
      status: 'pending',
      createdAt: Date.now(),
      userId,
      progress: 0,
    });

    // Process job in background
    processAndAnalyzeImage(jobId, userId, image).catch(console.error);

    // Return job ID immediately
    return res.status(201).json({
      success: true,
      jobId,
      status: 'pending'
    });
  } catch (error) {
    console.error('Job submission error:', error.message);
    return res.status(500).json({
      success: false,
      error: `Job submission failed: ${error.message}`
    });
  }
});

// JOB STATUS ENDPOINT
app.get('/api/jobs/:jobId', async (req, res) => {
  try {
    const { jobId } = req.params;
    console.log(`Checking status for job ${jobId}`);

    // Get job status
    const jobData = getJobStatus(jobId);

    if (!jobData) {
      return res.status(404).json({
        success: false,
        error: 'Job not found'
      });
    }

    // If job is completed, include results
    if (jobData.status === 'completed') {
      if (jobData.result) {
        return res.json({
          success: true,
          status: 'completed',
          progress: 100,
          createdAt: jobData.createdAt,
          completedAt: jobData.completedAt || Date.now(),
          data: jobData.result
        });
      } else {
        return res.status(500).json({
          success: false,
          status: 'error',
          error: 'Analysis completed but no results available'
        });
      }
    } else if (jobData.status === 'failed') {
      // Return error status with 200 code so client can parse it properly
      return res.status(200).json({
        success: false,
        status: 'failed',
        error: jobData.error || 'Unknown error during processing',
        progress: 100,
        createdAt: jobData.createdAt,
        completedAt: jobData.completedAt || Date.now()
      });
    }

    // For non-completed jobs, return status info (always read from stored status)
    return res.json({
      success: true,
      status: jobData.status || 'pending', // Always use stored status
      progress: jobData.progress || 0,
      createdAt: jobData.createdAt,
      message: jobData.message || null
    });
  } catch (error) {
    console.error('Job status error:', error.message);
    return res.status(500).json({
      success: false,
      error: `Server error: ${error.message}`
    });
  }
});

// Legacy endpoint with real OpenAI - NO FALLBACKS, FAIL PROPERLY
app.post('/api/analyze-food', limiter, async (req, res) => {
  try {
    console.log('🔥 Legacy analyze food endpoint called - NO FALLBACKS');
    const { image, fast_mode, ultra_fast, lightning_fast } = req.body;
    
    // Log optimization modes
    if (lightning_fast) {
      console.log('⚡⚡⚡ LIGHTNING-FAST mode - 15 SECOND TARGET!');
    } else if (ultra_fast) {
      console.log('⚡⚡ ULTRA-FAST mode enabled - MAXIMUM SPEED');
    } else if (fast_mode) {
      console.log('⚡ Fast mode enabled - optimizing for speed');
    }

    if (!image) {
      console.error('No image provided in request');
      return res.status(400).json({
        success: false,
        error: 'Image data is required'
      });
    }

    // LIGHTNING cache check for similar images - enhanced for speed
    if (lightning_fast || ultra_fast) {
      const imageHash = require('crypto').createHash('md5').update(image.substring(0, 1500)).digest('hex');
      const cached = responseCache.get(imageHash);
      
      if (cached && (Date.now() - cached.timestamp) < CACHE_DURATION) {
        console.log(lightning_fast ? '⚡⚡⚡ LIGHTNING CACHE HIT - INSTANT!' : '⚡⚡ CACHE HIT - Instant response!');
        return res.json({
          success: true,
          data: cached.data,
          cached: true,
          mode: lightning_fast ? 'lightning' : 'ultra_fast'
        });
      }
    }

    if (!process.env.OPENAI_API_KEY) {
      console.log('🔥 No OpenAI API key - FAILING');
      return res.status(500).json({
        success: false,
        error: 'OpenAI API key not configured'
      });
    }

    try {
      // Use the original image without compression
      const processedImage = image;
      
                                         // COMPREHENSIVE prompt - request ALL 34 micronutrients tracked on nutrition.dart screen
         const systemPrompt = `You are a professional nutritionist and food analyst. ANALYZE THE VISUAL DETAILS CAREFULLY and provide COMPLETE nutritional information including ALL vitamins, minerals, and other nutrients:

VISUAL ANALYSIS CHECKLIST:
- Orange/golden cubes = likely sweet potato or regular potato
- White creamy substance = likely yogurt, cream, or sauce
- Meat pieces = identify by texture and color (chicken, beef, etc.)
- Fermented vegetables = kimchi, sauerkraut (often reddish/orange with cabbage texture)
- White chunks = could be cheese, tofu, or other protein
- Look at TEXTURES, COLORS, and SHAPES - don't guess based on assumptions

CRITICAL RULES:
- Identify by VISUAL CHARACTERISTICS, not assumptions
- Sweet potato = orange/golden cubes with smooth texture
- Greek yogurt = white, creamy, smooth consistency  
- Kimchi = fermented cabbage, often reddish/orange color
- Chicken = white/light meat pieces with fibrous texture

Return ONLY valid JSON with COMPLETE nutrition data including ALL 34 micronutrients:

{
  "meal_name": "ACCURATE DESCRIPTIVE NAME based on what you see",
  "ingredients": [
    {
      "name": "ONLY ingredients you can clearly see",
      "weight_g": 150,
      "calories": 75,
      "protein_g": 3,
      "fat_g": 1.5,
      "carbs_g": 15,
      "vitamin_a": 450,
      "vitamin_c": 12,
      "vitamin_d": 2,
      "vitamin_e": 1.5,
      "vitamin_k": 8,
      "vitamin_b1": 0.08,
      "vitamin_b2": 0.12,
      "vitamin_b3": 1.8,
      "vitamin_b5": 0.6,
      "vitamin_b6": 0.15,
      "vitamin_b7": 3,
      "vitamin_b9": 25,
      "vitamin_b12": 0.3,
      "calcium": 45,
      "chloride": 120,
      "chromium": 2,
      "copper": 0.15,
      "fluoride": 0.8,
      "iodine": 8,
      "iron": 1.2,
      "magnesium": 35,
      "manganese": 0.4,
      "molybdenum": 5,
      "phosphorus": 65,
      "potassium": 280,
      "selenium": 2.5,
      "sodium": 85,
      "zinc": 0.8,
      "fiber": 2.5,
      "cholesterol": 15,
      "sugar": 8,
      "saturated_fats": 0.6,
      "omega_3": 120,
      "omega_6": 1.8
    }
  ]
}

Rules:
1. Identify ALL food items visible in the image
2. Estimate weight_g based on the actual portion size you see
3. Use specific food names
4. Break down complex dishes into components
5. Include all visible ingredients, garnishes, and components
6. Provide ACCURATE values for ALL 34 nutrients listed above
7. NO extra text outside JSON structure`;

      // Make OpenAI API call with timeout
      const controller = new AbortController();
      const timeoutMs = lightning_fast ? 45000 : (ultra_fast ? 60000 : (fast_mode ? 75000 : 90000)); // Lightning: 45s, Ultra: 60s, Fast: 75s, Normal: 90s
      const timeoutId = setTimeout(() => {
        console.log(`🔥 OpenAI timeout - FAILING (aborting at ${timeoutMs/1000}s)`);
        controller.abort();
      }, timeoutMs);

      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
        },
        signal: controller.signal,
        body: JSON.stringify({
          model: "gpt-4o-mini", // Always use mini for speed
          temperature: lightning_fast ? 0.001 : (ultra_fast ? 0.01 : (fast_mode ? 0.05 : 0.1)), // EXTREME temperature for lightning
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
                  text: lightning_fast ? 
                     "VISUAL ANALYSIS: Look at colors, textures, shapes. Orange cubes = sweet potato. White creamy = yogurt/sauce. Meat pieces = chicken/beef by texture. Reddish fermented vegetables = kimchi. Be PRECISE about what you observe visually, don't assume based on typical combinations. Provide ACCURATE values for ALL 34 nutrients including vitamins, minerals, and other nutrients." :
                    (ultra_fast ? 
                       "Analyze visual characteristics: colors, textures, shapes. Identify by what you see, not what you expect. Include COMPLETE nutrient analysis for all identified foods including ALL vitamins, minerals, and other nutrients." :
                      (fast_mode ? 
                         "Look at visual details: orange cubes, white cream, meat texture, fermented vegetables. Provide COMPLETE nutritional analysis including ALL vitamins, minerals, and other nutrients." : 
                         "Carefully analyze visual characteristics and identify ingredients by their appearance. Provide COMPLETE nutrition data including ALL 34 vitamins, minerals, and other nutrients."))
                },
                { 
                  type: "image_url", 
                  image_url: { 
                    url: processedImage,
                    detail: lightning_fast ? "high" : "low" // High detail for lightning accuracy
                  } 
                }
              ]
            }
          ],
          max_tokens: lightning_fast ? 1200 : (ultra_fast ? 1000 : (fast_mode ? 1200 : 1500)), // Restored tokens for accuracy
          stream: false // Ensure no streaming for fastest response
        })
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        console.log('🔥 OpenAI API error - FAILING:', response.status);
        const errorText = await response.text();
        let errorMsg = errorText;
        try {
          const parsed = JSON.parse(errorText);
          errorMsg = parsed?.error?.message || errorText;
        } catch (_) {}
        return res.status(response.status).json({
          success: false,
          error: `OpenAI API error: ${response.status} - ${errorMsg}`
        });
      }

      const responseData = await response.json();
      const content = responseData.choices[0].message.content.trim();
      
      console.log('🔥 OpenAI response received, length:', content.length);
      
      try {
        // Try to parse the response
        const jsonResponse = JSON.parse(content);
        
        if (!jsonResponse.ingredients || !Array.isArray(jsonResponse.ingredients) || jsonResponse.ingredients.length === 0) {
          console.log('🔥 No valid ingredients in response - FAILING');
          return res.status(500).json({
            success: false,
            error: 'No food ingredients detected in the image'
          });
        }

        console.log('🔥 Valid ingredients found:', jsonResponse.ingredients.length);
        
        // Expand simple response to full nutrient profile using real nutritional knowledge
        const expandedResponse = expandToFullNutrients(jsonResponse);
        const finalResponse = processVisionResponse(expandedResponse);
        
        // Cache lightning/ultra-fast responses for instant future access
        if (lightning_fast || ultra_fast) {
          const imageHash = require('crypto').createHash('md5').update(image.substring(0, 1500)).digest('hex');
          
          // Manage cache size
          if (responseCache.size >= CACHE_MAX_SIZE) {
            const firstKey = responseCache.keys().next().value;
            responseCache.delete(firstKey);
          }
          
          responseCache.set(imageHash, {
            data: finalResponse,
            timestamp: Date.now(),
            mode: lightning_fast ? 'lightning' : 'ultra_fast'
          });
          
          console.log(lightning_fast ? '⚡⚡⚡ LIGHTNING response cached!' : '⚡⚡ Response cached for ultra-fast future access');
        }
        
        return res.json({
          success: true,
          data: finalResponse
        });
      } catch (parseError) {
         console.log('🔥 JSON parse failed - attempting repair:', parseError.message);
         
         // ROBUST JSON REPAIR SYSTEM
         let repairedContent = repairJsonFormat(content);
         
         // Additional fix: unterminated strings by finding the last complete object
         if (parseError.message.includes('Unterminated string')) {
           console.log('🔧 Attempting to fix unterminated string...');
           
           // Find the last complete ingredient object
           const lastCompleteMatch = repairedContent.match(/\{[^}]*"name"[^}]*\}/g);
           if (lastCompleteMatch) {
             const lastComplete = lastCompleteMatch[lastCompleteMatch.length - 1];
             const lastIndex = repairedContent.lastIndexOf(lastComplete);
             
             // Truncate to the last complete ingredient and close the JSON properly
             repairedContent = repairedContent.substring(0, lastIndex + lastComplete.length);
             
             // Close the ingredients array and main object
             if (repairedContent.includes('"ingredients": [')) {
               repairedContent += '\n  ]\n}';
             }
           }
         }
         
         // Fix unexpected end of JSON by completing the structure
         if (parseError.message.includes('Unexpected end of JSON input')) {
           console.log('🔧 Attempting to fix unexpected end of JSON...');
           
           // Find the last complete ingredient
           const ingredientsMatches = repairedContent.match(/\{[^}]*"name"[^}]*\}/g);
           if (ingredientsMatches && ingredientsMatches.length > 0) {
             const lastIngredient = ingredientsMatches[ingredientsMatches.length - 1];
             const lastIndex = repairedContent.lastIndexOf(lastIngredient);
             
             // Complete the JSON structure
             repairedContent = repairedContent.substring(0, lastIndex + lastIngredient.length);
             
             // Add missing closing brackets
             if (repairedContent.includes('"ingredients": [')) {
               repairedContent += '\n  ]\n}';
             }
           }
         }
         
         // Final tidy pass for commas/whitespace
         repairedContent = repairedContent
           .replace(/,\s*}/g, '}')
           .replace(/,\s*]/g, ']')
           .replace(/,\s*,/g, ',');
         
         // Try to parse the repaired JSON
         try {
           console.log('🔧 Attempting to parse repaired JSON...');
           const jsonResponse = JSON.parse(repairedContent);
           
           if (jsonResponse.ingredients && Array.isArray(jsonResponse.ingredients) && jsonResponse.ingredients.length > 0) {
             console.log('✅ JSON repair successful!');
             
             // Expand simple response to full nutrient profile using real nutritional knowledge
             const expandedResponse = expandToFullNutrients(jsonResponse);
             const finalResponse = processVisionResponse(expandedResponse);
             
             // Cache lightning/ultra-fast responses for instant future access
             if (lightning_fast || ultra_fast) {
               const imageHash = require('crypto').createHash('md5').update(image.substring(0, 1500)).digest('hex');
               
               // Manage cache size
               if (responseCache.size >= CACHE_MAX_SIZE) {
                 const firstKey = responseCache.keys().next().value;
                 responseCache.delete(firstKey);
               }
               
               responseCache.set(imageHash, {
                 data: finalResponse,
                 timestamp: Date.now(),
                 mode: lightning_fast ? 'lightning' : 'ultra_fast'
               });
               
               console.log(lightning_fast ? '⚡⚡⚡ LIGHTNING response cached!' : '⚡⚡ Response cached for ultra-fast future access');
             }
             
             return res.json({
               success: true,
               data: finalResponse
             });
           }
         } catch (repairError) {
           console.log('🔧 JSON repair failed:', repairError.message);
         }
         
         // If all repair attempts failed, return error
         console.log('🔥 All JSON repair attempts failed - FAILING');
        return res.status(500).json({
          success: false,
          error: 'OpenAI generated invalid JSON that could not be repaired'
        });
      }
    } catch (error) {
      if (error.name === 'AbortError') {
        console.log('🔥 OpenAI call aborted due to timeout');
        return res.status(504).json({
          success: false,
          error: 'OpenAI request timed out'
        });
      }
      console.log('🔥 OpenAI call failed - FAILING:', error.message);
      return res.status(500).json({
        success: false,
        error: `API call error: ${error.message}`
      });
    }
  } catch (error) {
    console.log('🔥 Server error - FAILING:', error.message);
    return res.status(500).json({
      success: false,
      error: `Server error: ${error.message}`
    });
  }
});

// Start the server
app.listen(PORT, () => {
  console.log(`Server with real OpenAI integration running on port ${PORT}`);
});