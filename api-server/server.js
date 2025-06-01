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

    // ENHANCED prompt for better ingredient detection
    const enhancedPrompt = `You are a professional nutritionist and food analyst. Analyze this food image and identify ALL individual ingredients and food items visible in the meal.

CRITICAL REQUIREMENTS:
- ALWAYS include ALL 13 vitamins, ALL 15 minerals, ALL 6 other nutrients for EVERY ingredient
- NEVER omit any nutrient - use 0.0 if not present
- Use EXACT units and structure specified below
- MINIMUM 2 ingredients for any meal (unless truly single item)
- SCAN SYSTEMATICALLY: Look at all areas of the plate/image
- IDENTIFY LAYERS: Check for ingredients that might be layered or mixed
- ALWAYS provide weight_g based on what you SEE in the image - this is MANDATORY

INGREDIENT IDENTIFICATION RULES:
- **Proteins**: "chicken" = 1 ingredient (NOT "grilled chicken breast")
- **Vegetables**: each distinct vegetable type (tomatoes, cucumbers, lettuce, etc.) - use simple names
- **Grains/Starches**: rice, bread, pasta, potatoes as separate items
- **Sauces/Condiments**: dressings, sauces, oils as separate items
- **Sides**: coleslaw, salads, etc. as separate items

NAMING GUIDELINES:
- **Ingredient Names**: Keep simple - "chicken" not "grilled chicken breast", "tomatoes" not "cherry tomatoes", "sausages" not "grilled sausages"
- **Meal Names**: Use recognizable dish names when possible (Pizza, Pasta, Tacos, Salad, etc.) or generic names like "Mixed Plate", "Dinner Bowl", "Lunch Plate", etc.

WEIGHT ESTIMATION:
You MUST provide weight_g estimates for each ingredient based on visual analysis of the actual portion sizes shown in the image. Look at the actual size of each food item and estimate the weight based on what you see.

RESPONSE FORMAT (JSON ONLY):
Return a JSON object with meal_name and ingredients array. Each ingredient MUST have:
- name: simple, concise name (e.g., "chicken", "tomatoes", "rice")
- weight_g: Estimated weight based on ACTUAL VISUAL portion size shown in the image
- calories, protein_g, fat_g, carbs_g: nutritional values
- vitamins: object with ALL 13 vitamin values (MANDATORY)
- minerals: object with ALL 15 mineral values (MANDATORY)
- other: object with ALL 6 other nutrient values (MANDATORY)

MANDATORY EXACT NUTRIENT STRUCTURE FOR EVERY INGREDIENT:
vitamins: {
  "vitamin_A_mcg": 0.0,
  "vitamin_C_mg": 0.0,
  "vitamin_D_mcg": 0.0,
  "vitamin_E_mg": 0.0,
  "vitamin_K_mcg": 0.0,
  "vitamin_B1_mg": 0.0,
  "vitamin_B2_mg": 0.0,
  "vitamin_B3_mg": 0.0,
  "vitamin_B5_mg": 0.0,
  "vitamin_B6_mg": 0.0,
  "vitamin_B7_mcg": 0.0,
  "vitamin_B9_mcg": 0.0,
  "vitamin_B12_mcg": 0.0
}

minerals: {
  "calcium_mg": 0.0,
  "chloride_mg": 0.0,
  "chromium_mcg": 0.0,
  "copper_mcg": 0.0,
  "fluoride_mg": 0.0,
  "iodine_mcg": 0.0,
  "iron_mg": 0.0,
  "magnesium_mg": 0.0,
  "manganese_mg": 0.0,
  "molybdenum_mcg": 0.0,
  "phosphorus_mg": 0.0,
  "potassium_mg": 0.0,
  "selenium_mcg": 0.0,
  "sodium_mg": 0.0,
  "zinc_mg": 0.0
}

other: {
  "fiber_g": 0.0,
  "cholesterol_mg": 0.0,
  "sugar_g": 0.0,
  "saturated_fats_g": 0.0,
  "omega_3_mg": 0.0,
  "omega_6_g": 0.0
}

CRITICAL NUTRIENT REQUIREMENTS:
- EVERY ingredient MUST have ALL 13 vitamins, ALL 15 minerals, ALL 6 other nutrients
- Use 0.0 for nutrients not present in that ingredient
- NEVER omit any nutrient from the structure above
- Use realistic USDA nutrition values with precise decimal places

VITAMIN UNITS (CRITICAL):
- vitamin_A_mcg: micrograms (NOT IU) - typical values 0-500 mcg
- vitamin_C_mg: milligrams - typical values 0-100 mg
- vitamin_D_mcg: micrograms - typical values 0-10 mcg
- vitamin_E_mg: milligrams - typical values 0-15 mg
- vitamin_K_mcg: micrograms - typical values 0-100 mcg
- vitamin_B1_mg: milligrams - typical values 0-2 mg
- vitamin_B2_mg: milligrams - typical values 0-2 mg
- vitamin_B3_mg: milligrams - typical values 0-20 mg
- vitamin_B5_mg: milligrams - typical values 0-5 mg
- vitamin_B6_mg: milligrams - typical values 0-2 mg
- vitamin_B7_mcg: micrograms - typical values 0-50 mcg
- vitamin_B9_mcg: micrograms - typical values 0-400 mcg
- vitamin_B12_mcg: micrograms - typical values 0-10 mcg

MINERAL UNITS (CRITICAL):
- calcium_mg: milligrams - typical values 0-300 mg
- chloride_mg: milligrams - typical values 0-1000 mg
- chromium_mcg: micrograms - typical values 0-50 mcg
- copper_mcg: micrograms - typical values 0-1000 mcg
- fluoride_mg: milligrams - typical values 0-2 mg
- iodine_mcg: micrograms - typical values 0-200 mcg
- iron_mg: milligrams - typical values 0-10 mg
- magnesium_mg: milligrams - typical values 0-100 mg
- manganese_mg: milligrams - typical values 0-3 mg
- molybdenum_mcg: micrograms - typical values 0-50 mcg
- phosphorus_mg: milligrams - typical values 0-400 mg
- potassium_mg: milligrams - typical values 0-1000 mg
- selenium_mcg: micrograms - typical values 0-100 mcg
- sodium_mg: milligrams - typical values 0-1000 mg
- zinc_mg: milligrams - typical values 0-5 mg

OTHER NUTRIENT UNITS (CRITICAL):
- fiber_g: grams - typical values 0-10 g
- cholesterol_mg: milligrams - typical values 0-200 mg
- sugar_g: grams - typical values 0-20 g
- saturated_fats_g: grams - typical values 0-10 g
- omega_3_mg: milligrams - typical values 0-1000 mg
- omega_6_g: grams - typical values 0-5 g

IMPORTANT:
- EVERY number MUST end with .0 even for whole numbers
- Keep ingredient names short and simple
- Use recognizable meal names or generic terms like "Mixed Plate"
- ALWAYS provide weight_g estimates based on what you SEE in the image - this is MANDATORY
- NEVER omit any nutrient from the structure above - use 0.0 if not present
- VERIFY all 13 vitamins, 15 minerals, and 6 other nutrients are included for EVERY ingredient

QUALITY CHECK:
- If you only detect 1 ingredient, look again more carefully
- Complex plated meals should have 3-6 ingredients typically
- Use realistic USDA nutrition values with precise decimal places
- Include ALL nutrients with correct units for EVERY ingredient
- Use 0.0 for absent nutrients (e.g. cholesterol in vegetables)
- ALWAYS provide weight_g estimates based on what you SEE in the image - this is MANDATORY
- VERIFY all 13 vitamins, 15 minerals, and 6 other nutrients are included for EVERY ingredient`;

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
            model: "gpt-4o", // Using gpt-4o which can handle images
            temperature: 0.1,  // Lower temperature for more predictable outputs
            response_format: { type: "json_object" },
        messages: [
          {
                role: "system",
                content: enhancedPrompt
              },
              {
                role: "user",
                content: [
                  { type: "text", text: "Analyze this food image. Identify each distinct food item as a single ingredient (e.g., grilled chicken thigh = 1 ingredient, not grilled chicken + thigh). Look for proteins, vegetables, sides, and sauces as separate items. Estimate weights based purely on what you see in the image." },
                  { type: "image_url", image_url: { url: processedImage } }
                ]
              }
            ],
            max_tokens: 1500  // Increased from 800 to allow for more detailed analysis
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
              
              // Process the response directly without fallback
              finalResponse = processVisionResponse(jsonResponse);
              
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
            console.log('Raw OpenAI response preview (first 500 chars):', content.substring(0, 500));
            console.log('Raw OpenAI response preview (last 500 chars):', content.substring(Math.max(0, content.length - 500)));
            
            // Try to find and fix common JSON issues
            let cleanedResponse = content.trim();
            
            // Remove markdown code blocks if present
            cleanedResponse = cleanedResponse.replace(/^```json\s*/, '').replace(/\s*```$/, '');
            
            // Remove any leading/trailing whitespace
            cleanedResponse = cleanedResponse.trim();
            
            // Try to parse the cleaned response
            if (cleanedResponse !== content) {
              try {
                console.log('Attempting to parse cleaned JSON...');
                const jsonResponse = JSON.parse(cleanedResponse);
                console.log('Cleaned JSON parsed successfully!');
                
                if (jsonResponse.ingredients && jsonResponse.ingredients.length > 0) {
                  finalResponse = processVisionResponse(jsonResponse);
                  
                  await updateJobStatus(jobId, {
                    status: 'completed',
                    progress: 100,
                    message: 'Analysis complete (cleaned JSON)',
                    completedAt: Date.now(),
                    result: finalResponse
                  });
                  
                  console.log(`Job ${jobId} marked completed (cleaned JSON) at ${new Date().toISOString()}`);
                  return; // Exit early on success
                }
              } catch (cleanError) {
                console.log('JSON clean attempt failed:', cleanError.message);
              }
            }
            
            // Save the cleaned response for debugging without logging to console
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
  const { ingredients, total } = visionResponse;
  
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
  const mappedIngredients = ingredients.map(item => {
    const cleanName = cleanIngredientName(item.name);
    const weight = item.weight_g || 100.0;
    const calories = item.calories || 0;
    
    const ingredient = {
      name: cleanName,
      weight_g: weight,
      calories: calories,
      protein_g: item.protein_g || 0,
      fat_g: item.fat_g || 0,
      carbs_g: item.carbs_g || 0
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
    protein: total?.protein_g || mappedIngredients.reduce((sum, ing) => sum + (ing.protein_g || 0), 0),
    fat: total?.fat_g || mappedIngredients.reduce((sum, ing) => sum + (ing.fat_g || 0), 0),
    carbs: total?.carbs_g || mappedIngredients.reduce((sum, ing) => sum + (ing.carbs_g || 0), 0)
  };

  // Add comprehensive nutrition data if available in totals
  if (total?.vitamins) {
    response.vitamins = total.vitamins;
  }

  if (total?.minerals) {
    response.minerals = total.minerals;
  }

  if (total?.other) {
    response.other = total.other;
  }

  // Also include ingredient_nutrients array for detailed per-ingredient nutrition
  if (mappedIngredients.length > 0) {
    response.ingredient_nutrients = mappedIngredients.map(ingredient => ({
      name: ingredient.name,
      vitamins: ingredient.vitamins || {},
      minerals: ingredient.minerals || {},
      other: ingredient.other || {}
    }));
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

// Legacy endpoint with real OpenAI
app.post('/api/analyze-food', limiter, async (req, res) => {
  try {
    console.log('Legacy analyze food endpoint called');
    const { image } = req.body;

    if (!image) {
      console.error('No image provided in request');
      return res.status(400).json({
        success: false,
        error: 'Image data is required'
      });
    }

    // Generate job ID
    const jobId = uuidv4();
    console.log(`Creating legacy job ${jobId}`);

    // Create initial job status
    await updateJobStatus(jobId, {
      status: 'pending',
      createdAt: Date.now(),
      userId: 'legacy-api',
      progress: 0,
    });

    if (!process.env.OPENAI_API_KEY) {
      return res.status(500).json({
        success: false,
        error: 'API key not configured'
      });
    }

    try {
      // Use the original image without compression
      const processedImage = image;
      
      // System prompt for accurate food recognition
      const systemPrompt = `You are a professional food nutrition analyzer. Analyze the image and identify ALL visible food items with comprehensive nutrition data.

IMPORTANT GUIDELINES:
- Identify each distinct food item as a single ingredient
- Keep compound foods together (e.g., "grilled chicken thigh" = 1 ingredient, NOT "grilled chicken" + "thigh")
- Look for separate food items: proteins, vegetables, sides, sauces, garnishes
- Don't over-split compound food names

EXAMPLES OF PROPER DETECTION:
- Meat items: "grilled chicken thigh", "beef steak", "pork sausage" (each as single ingredient)
- Vegetables: broccoli, carrots, tomatoes, cucumbers, lettuce (each separately)
- Starches: rice, pasta, bread, potatoes (each separately)
- Sides: coleslaw, salad, sauce, dressing (each separately)
- Garnishes: herbs, spices, small vegetables (include these too)

WEIGHT ESTIMATION:
You MUST provide weight_g estimates for each ingredient based on visual analysis of the actual portion sizes shown in the image. Look at the actual size of each food item and estimate the weight based on what you see.

IMPORTANT GUIDELINES:
1. **Don't over-split**: "chicken breast" = 1 ingredient, "beef steak" = 1 ingredient
2. **Do identify separate items**: chicken + vegetables + rice = 3 ingredients
3. **Include garnishes**: herbs, spices, small vegetables as separate if visible
4. **Systematic scanning**: Look at all areas of the plate/image
5. **Minimum threshold**: Try to identify 2-5 ingredients for typical meals
6. **ALWAYS provide weight_g**: Never leave weight_g empty or null - estimate based on ACTUAL VISUAL portion size in the image

RESPONSE FORMAT (JSON ONLY):
Return a JSON object with meal_name and ingredients array. Each ingredient should have:
- name: simple, concise name (e.g., "chicken", "tomatoes", "rice")
- weight_g: Estimated weight based on ACTUAL VISUAL portion size shown in the image
- calories, protein_g, fat_g, carbs_g: nutritional values
- vitamins: object with vitamin values
- minerals: object with mineral values  
- other: object with fiber, cholesterol, etc.

IMPORTANT:
- EVERY number MUST end with .0 even for whole numbers
- Keep ingredient names short and simple
- Use recognizable meal names or generic terms like "Mixed Plate"
- Include comprehensive vitamin/mineral data for each ingredient
- ALWAYS provide weight_g estimates based on what you SEE in the image - this is MANDATORY

CRITICAL VITAMIN UNITS:
- Vitamin A: ALWAYS in mcg (micrograms), NOT IU. Typical values: 0-500 mcg per meal
- Vitamin D, K, B7, B9, B12: mcg (micrograms)
- Vitamin C, E, B1, B2, B3, B5, B6: mg (milligrams)
- If you calculate vitamin A in IU, convert: 1 IU = 0.3 mcg

VITAMIN A CRITICAL NOTE: 
- ALWAYS return Vitamin A in MICROGRAMS (mcg), NOT International Units (IU)
- Typical meal values: 50-500 mcg (NOT 500-5000 IU)
- If you calculate IU, convert: 1 IU = 0.3 mcg for vitamin A
- Example: 1000 IU = 300 mcg

REALISTIC VITAMIN A VALUES FOR COMMON FOODS:
- Chicken: 0-10 mcg per 100g
- Tomatoes: 40-50 mcg per 100g  
- Carrots: 800-900 mcg per 100g
- Leafy greens: 400-500 mcg per 100g
- Most meals: 50-300 mcg total

QUALITY CHECK:
- If you only detect 1 ingredient, look again more carefully
- Complex plated meals should have 3-6 ingredients typically
- Use realistic USDA nutrition values with precise decimal places
- Include ALL nutrients with correct units
- Use 0 for absent nutrients (e.g. cholesterol in vegetables)
- ALWAYS provide weight_g estimates based on what you SEE in the image - this is MANDATORY`;

      // Make OpenAI API call
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
        timeout: 120000, // Increased to 120 seconds for image analysis
      body: JSON.stringify({
          model: "gpt-4o", // Using gpt-4o which can handle images
          temperature: 0.1,  // Slight variation for better JSON generation
          response_format: { type: "json_object" },
        messages: [
          {
              role: "system",
              content: systemPrompt
          },
          {
              role: "user",
            content: [
                { type: "text", text: "Analyze this meal image and identify ALL separate food components. Look carefully at every part of the plate - identify each distinct ingredient separately (proteins, vegetables, sides, garnishes). For complex meals, you should typically find 3-6 distinct ingredients. Estimate weights based purely on what you see in the image. Return comprehensive nutrition data in JSON format exactly as specified." },
                { type: "image_url", image_url: { url: processedImage } }
            ]
          }
        ],
          max_tokens: 2000
      })
    });

      if (response.ok) {
        const responseData = await response.json();
        const content = responseData.choices[0].message.content.trim();
        
        try {
          // Log the raw response for debugging
          console.log('LEGACY ENDPOINT - Raw OpenAI response length:', content.length);
          console.log('LEGACY ENDPOINT - Raw response preview (first 500 chars):', content.substring(0, 500));
          
          // Check for position 3711 specifically where the error occurs
          if (content.length > 3711) {
            console.log('LEGACY ENDPOINT - Character at position 3711:', JSON.stringify(content.charAt(3711)));
            console.log('LEGACY ENDPOINT - Context around position 3711:', JSON.stringify(content.substring(3700, 3720)));
          }
          
          // Try to clean the response first
          let cleanedContent = content.trim();
          
          // Remove markdown code blocks if present
          cleanedContent = cleanedContent.replace(/^```json\s*/, '').replace(/\s*```$/, '');
          
          // Fix common JSON syntax errors
          cleanedContent = cleanedContent
            .replace(/,\s*}/g, '}')     // Remove trailing commas before }
            .replace(/,\s*]/g, ']')     // Remove trailing commas before ]
            .replace(/"\s*:\s*,/g, '": null,')  // Fix empty values
            .replace(/:\s*,/g, ': null,')       // Fix missing values
            .replace(/,\s*,/g, ',');            // Fix double commas
          
          console.log('LEGACY ENDPOINT - Cleaned response preview (first 500 chars):', cleanedContent.substring(0, 500));
          
          // Try to find the ingredients array and extract complete ingredients
          const ingredientsMatch = cleanedContent.match(/"ingredients":\s*\[(.*?)\]/s);
          if (ingredientsMatch) {
            console.log('LEGACY ENDPOINT - Found ingredients array, attempting to parse...');
            
            try {
              // Try to parse just the ingredients array first
              const ingredientsArrayStr = `[${ingredientsMatch[1]}]`;
              const cleanedIngredientsStr = ingredientsArrayStr
                .replace(/,\s*}/g, '}')
                .replace(/,\s*]/g, ']')
                .replace(/"\s*:\s*,/g, '": null,')
                .replace(/:\s*,/g, ': null,');
              
              const ingredientsArray = JSON.parse(cleanedIngredientsStr);
              
              if (ingredientsArray && ingredientsArray.length > 0) {
                console.log(`LEGACY ENDPOINT - Successfully parsed ${ingredientsArray.length} ingredients`);
                
                // Calculate totals from ingredients
                let totalCalories = 0, totalProtein = 0, totalFat = 0, totalCarbs = 0;
                
                ingredientsArray.forEach(ingredient => {
                  totalCalories += ingredient.calories || 0;
                  totalProtein += ingredient.protein_g || 0;
                  totalFat += ingredient.fat_g || 0;
                  totalCarbs += ingredient.carbs_g || 0;
                });
                
                const repairedResponse = {
                  ingredients: ingredientsArray,
                  total: {
                    calories: totalCalories,
                    protein_g: totalProtein,
                    fat_g: totalFat,
                    carbs_g: totalCarbs
                  }
                };
                
                console.log('LEGACY ENDPOINT - JSON repair successful via ingredients array!');
                const result = processVisionResponse(repairedResponse);
            return res.json({
              success: true,
              data: result
            });
              }
            } catch (ingredientsError) {
              console.log('LEGACY ENDPOINT - Ingredients array parsing failed:', ingredientsError.message);
            }
          }
          
          // Alternative approach: find individual ingredient objects
          const ingredientMatches = cleanedContent.match(/\{\s*"name":\s*"[^"]+",[\s\S]*?\}/g);
          if (ingredientMatches && ingredientMatches.length > 0) {
            console.log(`LEGACY ENDPOINT - Found ${ingredientMatches.length} individual ingredient objects`);
            
            const validIngredients = [];
            
            for (const ingredientStr of ingredientMatches) {
              try {
                const cleanedIngredientStr = ingredientStr
                  .replace(/,\s*}/g, '}')
                  .replace(/"\s*:\s*,/g, '": null,')
                  .replace(/:\s*,/g, ': null,');
                
                const ingredient = JSON.parse(cleanedIngredientStr);
                if (ingredient.name) {
                  validIngredients.push(ingredient);
                }
              } catch (ingredientError) {
                console.log('LEGACY ENDPOINT - Failed to parse individual ingredient:', ingredientError.message);
              }
            }
            
            if (validIngredients.length > 0) {
              console.log(`LEGACY ENDPOINT - Successfully parsed ${validIngredients.length} individual ingredients`);
              
              // Calculate totals
              let totalCalories = 0, totalProtein = 0, totalFat = 0, totalCarbs = 0;
              
              validIngredients.forEach(ingredient => {
                totalCalories += ingredient.calories || 0;
                totalProtein += ingredient.protein_g || 0;
                totalFat += ingredient.fat_g || 0;
                totalCarbs += ingredient.carbs_g || 0;
              });
              
              const repairedResponse = {
                ingredients: validIngredients,
                total: {
                  calories: totalCalories,
                  protein_g: totalProtein,
                  fat_g: totalFat,
                  carbs_g: totalCarbs
                }
              };
              
              console.log('LEGACY ENDPOINT - JSON repair successful via individual ingredients!');
              const result = processVisionResponse(repairedResponse);
              return res.json({
                success: true,
                data: result
            });
          }
          }
          
          return res.status(500).json({
            success: false,
            error: 'Invalid response format from image analysis'
          });
        } catch (parseError) {
          console.error(`LEGACY ENDPOINT - Error parsing API response: ${parseError}`);
          console.log('LEGACY ENDPOINT - Raw response length:', content.length);
          console.log('LEGACY ENDPOINT - Raw response preview (first 500 chars):', content.substring(0, 500));
          console.log('LEGACY ENDPOINT - Raw response preview (last 500 chars):', content.substring(Math.max(0, content.length - 500)));
          
          // ROBUST JSON REPAIR LOGIC
          try {
            console.log('LEGACY ENDPOINT - Starting robust JSON repair...');
            
            let repairedContent = content.trim();
            
            // Remove markdown blocks
            if (repairedContent.startsWith('```json')) {
              repairedContent = repairedContent.replace(/^```json\s*/, '').replace(/\s*```$/, '');
            } else if (repairedContent.startsWith('```')) {
              repairedContent = repairedContent.replace(/^```\s*/, '').replace(/\s*```$/, '');
            }
            
            // Clean whitespace but preserve structure
            repairedContent = repairedContent.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
            
            // Fix common JSON syntax errors
            repairedContent = repairedContent
              .replace(/,\s*}/g, '}')     // Remove trailing commas before }
              .replace(/,\s*]/g, ']')     // Remove trailing commas before ]
              .replace(/"\s*:\s*,/g, '": null,')  // Fix empty values
              .replace(/:\s*,/g, ': null,')       // Fix missing values
              .replace(/,\s*,/g, ',');            // Fix double commas
            
            // Try to find the ingredients array and extract complete ingredients
            const ingredientsMatch = repairedContent.match(/"ingredients":\s*\[(.*?)\]/s);
            if (ingredientsMatch) {
              console.log('LEGACY ENDPOINT - Found ingredients array, attempting to parse...');
              
              try {
                // Try to parse just the ingredients array first
                const ingredientsArrayStr = `[${ingredientsMatch[1]}]`;
                const cleanedIngredientsStr = ingredientsArrayStr
                  .replace(/,\s*}/g, '}')
                  .replace(/,\s*]/g, ']')
                  .replace(/"\s*:\s*,/g, '": null,')
                  .replace(/:\s*,/g, ': null,');
                
                const ingredientsArray = JSON.parse(cleanedIngredientsStr);
              
                if (ingredientsArray && ingredientsArray.length > 0) {
                  console.log(`LEGACY ENDPOINT - Successfully parsed ${ingredientsArray.length} ingredients`);
                
                // Calculate totals from ingredients
                let totalCalories = 0, totalProtein = 0, totalFat = 0, totalCarbs = 0;
                
                  ingredientsArray.forEach(ingredient => {
                  totalCalories += ingredient.calories || 0;
                  totalProtein += ingredient.protein_g || 0;
                  totalFat += ingredient.fat_g || 0;
                  totalCarbs += ingredient.carbs_g || 0;
                });
                
                  const repairedResponse = {
                    ingredients: ingredientsArray,
                    total: {
                  calories: totalCalories,
                  protein_g: totalProtein,
                  fat_g: totalFat,
                  carbs_g: totalCarbs
                    }
                };
                
                  console.log('LEGACY ENDPOINT - JSON repair successful via ingredients array!');
                  const result = processVisionResponse(repairedResponse);
                return res.json({
                  success: true,
                  data: result
                });
              }
              } catch (ingredientsError) {
                console.log('LEGACY ENDPOINT - Ingredients array parsing failed:', ingredientsError.message);
              }
            }
            
            // Alternative approach: find individual ingredient objects
            const ingredientMatches = repairedContent.match(/\{\s*"name":\s*"[^"]+",[\s\S]*?\}/g);
            if (ingredientMatches && ingredientMatches.length > 0) {
              console.log(`LEGACY ENDPOINT - Found ${ingredientMatches.length} individual ingredient objects`);
              
              const validIngredients = [];
              
              for (const ingredientStr of ingredientMatches) {
                try {
                  const cleanedIngredientStr = ingredientStr
                    .replace(/,\s*}/g, '}')
                    .replace(/"\s*:\s*,/g, '": null,')
                    .replace(/:\s*,/g, ': null,');
                  
                  const ingredient = JSON.parse(cleanedIngredientStr);
                  if (ingredient.name) {
                    validIngredients.push(ingredient);
                  }
                } catch (ingredientError) {
                  console.log('LEGACY ENDPOINT - Failed to parse individual ingredient:', ingredientError.message);
                }
              }
              
              if (validIngredients.length > 0) {
                console.log(`LEGACY ENDPOINT - Successfully parsed ${validIngredients.length} individual ingredients`);
                
                // Calculate totals
                let totalCalories = 0, totalProtein = 0, totalFat = 0, totalCarbs = 0;
                
                validIngredients.forEach(ingredient => {
                  totalCalories += ingredient.calories || 0;
                  totalProtein += ingredient.protein_g || 0;
                  totalFat += ingredient.fat_g || 0;
                  totalCarbs += ingredient.carbs_g || 0;
              });
              
                const repairedResponse = {
                  ingredients: validIngredients,
                total: {
                    calories: totalCalories,
                    protein_g: totalProtein,
                    fat_g: totalFat,
                    carbs_g: totalCarbs
                }
              };
              
                console.log('LEGACY ENDPOINT - JSON repair successful via individual ingredients!');
                const result = processVisionResponse(repairedResponse);
              return res.json({
                success: true,
                data: result
              });
              }
            }
            
          } catch (repairError) {
            console.log('LEGACY ENDPOINT - JSON repair failed:', repairError.message);
          }
          
          return res.status(500).json({
            success: false,
            error: 'Invalid response format from image analysis'
          });
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
      console.error('OpenAI API error:', error);
      
      let errorMessage = `API call error: ${error.message}`;
      if (error.type === 'request-timeout' || error.message.includes('timeout')) {
        errorMessage = 'Request timeout - image analysis took too long. Please try again with a smaller image.';
      } else if (error.message.includes('network')) {
        errorMessage = 'Network error - please check your connection and try again.';
      }
      
      return res.status(500).json({
        success: false,
        error: errorMessage
      });
    }
  } catch (error) {
    console.error('Server error:', error.message);
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
