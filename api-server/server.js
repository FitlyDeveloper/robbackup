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

// Convert flat nutrient structure from OpenAI to nested structure expected by app
function convertFlatNutrientsToNested(ingredients) {
  return ingredients.map(ingredient => {
    const converted = {
      name: ingredient.name,
      weight_g: ingredient.weight_g || 100,
      calories: ingredient.calories || 0,
      protein_g: ingredient.protein_g || 0,
      fat_g: ingredient.fat_g || 0,
      carbs_g: ingredient.carbs_g || 0,
      vitamins: {
        vitamin_A_mcg: ingredient.vitamin_A || 0,
        vitamin_C_mg: ingredient.vitamin_C || 0,
        vitamin_D_mcg: ingredient.vitamin_D || 0,
        vitamin_E_mg: ingredient.vitamin_E || 0,
        vitamin_K_mcg: ingredient.vitamin_K || 0,
        vitamin_B1_mg: ingredient.vitamin_B1 || 0,
        vitamin_B2_mg: ingredient.vitamin_B2 || 0,
        vitamin_B3_mg: ingredient.vitamin_B3 || 0,
        vitamin_B5_mg: ingredient.vitamin_B5 || 0,
        vitamin_B6_mg: ingredient.vitamin_B6 || 0,
        vitamin_B7_mcg: ingredient.vitamin_B7 || 0,
        vitamin_B9_mcg: ingredient.vitamin_B9 || 0,
        vitamin_B12_mcg: ingredient.vitamin_B12 || 0
      },
      minerals: {
        calcium_mg: ingredient.calcium || 0,
        chloride_mg: ingredient.chloride || 0,
        chromium_mcg: ingredient.chromium || 0,
        copper_mcg: ingredient.copper || 0,
        fluoride_mg: ingredient.fluoride || 0,
        iodine_mcg: ingredient.iodine || 0,
        iron_mg: ingredient.iron || 0,
        magnesium_mg: ingredient.magnesium || 0,
        manganese_mg: ingredient.manganese || 0,
        molybdenum_mcg: ingredient.molybdenum || 0,
        phosphorus_mg: ingredient.phosphorus || 0,
        potassium_mg: ingredient.potassium || 0,
        selenium_mcg: ingredient.selenium || 0,
        sodium_mg: ingredient.sodium || 0,
        zinc_mg: ingredient.zinc || 0
      },
      other: {
        fiber_g: ingredient.fiber || 0,
        cholesterol_mg: ingredient.cholesterol || 0,
        sugar_g: ingredient.sugar || 0,
        saturated_fats_g: ingredient.saturated_fats || 0,
        omega_3_mg: ingredient.omega_3 || 0,
        omega_6_g: ingredient.omega_6 || 0
      }
    };
    
    return converted;
  });
}

// Expand simple OpenAI response to include all 34 nutrients using real nutritional knowledge
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
    
    // Use real nutritional knowledge to estimate missing micronutrients based on food type
    const micronutrients = estimateMicronutrients(name, expanded.calories, expanded.protein_g, expanded.fat_g, expanded.carbs_g);
    
    console.log(`🍎 ${ingredient.name}: Generated ${Object.keys(micronutrients).filter(k => micronutrients[k] > 0).length} non-zero nutrients`);
    console.log(`   Key nutrients: vitamin_C=${micronutrients.vitamin_C}, iron=${micronutrients.iron}, calcium=${micronutrients.calcium}`);
    
    // Merge with OpenAI's provided values (OpenAI takes priority)
    const result = {
      ...expanded,
      ...micronutrients,
      // Override with any values OpenAI specifically provided
      vitamin_C: ingredient.vitamin_C || micronutrients.vitamin_C,
      iron: ingredient.iron || micronutrients.iron,
      calcium: ingredient.calcium || micronutrients.calcium
    };
    
    return result;
  });
  
  console.log('🔬 Expansion complete, returning expanded ingredients');
  return {
    meal_name: simpleResponse.meal_name || "Mixed Plate",
    ingredients: expandedIngredients
  };
}

// Estimate micronutrients based on food type and macronutrients using real nutritional knowledge
function estimateMicronutrients(foodName, calories, protein, fat, carbs) {
  // Base nutrients (will be adjusted based on food type)
  let nutrients = {
    vitamin_A: 0, vitamin_C: 0, vitamin_D: 0, vitamin_E: 0, vitamin_K: 0,
    vitamin_B1: 0, vitamin_B2: 0, vitamin_B3: 0, vitamin_B5: 0, vitamin_B6: 0,
    vitamin_B7: 0, vitamin_B9: 0, vitamin_B12: 0,
    calcium: 0, chloride: 0, chromium: 0, copper: 0, fluoride: 0,
    iodine: 0, iron: 0, magnesium: 0, manganese: 0, molybdenum: 0,
    phosphorus: 0, potassium: 0, selenium: 0, sodium: 0, zinc: 0,
    fiber: 0, cholesterol: 0, sugar: 0, saturated_fats: 0, omega_3: 0, omega_6: 0
  };
  
  // Protein-rich foods (meat, fish, eggs)
  if (foodName.includes('chicken') || foodName.includes('beef') || foodName.includes('pork') || 
      foodName.includes('meat') || foodName.includes('steak')) {
    nutrients.vitamin_B3 = protein * 0.3;
    nutrients.vitamin_B6 = protein * 0.02;
    nutrients.vitamin_B12 = protein * 0.1;
    nutrients.iron = protein * 0.1;
    nutrients.zinc = protein * 0.05;
    nutrients.phosphorus = protein * 8;
    nutrients.selenium = protein * 0.6;
    nutrients.cholesterol = fat * 5;
    nutrients.saturated_fats = fat * 0.3;
  }
  
  // Fish
  else if (foodName.includes('fish') || foodName.includes('salmon') || foodName.includes('tuna')) {
    nutrients.vitamin_D = protein * 0.4;
    nutrients.vitamin_B12 = protein * 0.15;
    nutrients.omega_3 = fat * 100;
    nutrients.selenium = protein * 1.5;
    nutrients.phosphorus = protein * 10;
    nutrients.iodine = protein * 0.5;
  }
  
  // Vegetables
  else if (foodName.includes('broccoli') || foodName.includes('spinach') || foodName.includes('kale') ||
           foodName.includes('vegetable') || foodName.includes('green')) {
    nutrients.vitamin_A = carbs * 50;
    nutrients.vitamin_C = carbs * 10;
    nutrients.vitamin_K = carbs * 20;
    nutrients.vitamin_B9 = carbs * 8;
    nutrients.iron = carbs * 0.3;
    nutrients.calcium = carbs * 5;
    nutrients.magnesium = carbs * 3;
    nutrients.potassium = carbs * 20;
    nutrients.fiber = carbs * 0.3;
  }
  
  // Fruits
  else if (foodName.includes('apple') || foodName.includes('banana') || foodName.includes('orange') ||
           foodName.includes('berry') || foodName.includes('fruit') || foodName.includes('pineapple') ||
           foodName.includes('watermelon') || foodName.includes('melon') || foodName.includes('grape') ||
           foodName.includes('strawberry') || foodName.includes('mango') || foodName.includes('kiwi') ||
           foodName.includes('peach') || foodName.includes('pear') || foodName.includes('cherry')) {
    nutrients.vitamin_C = carbs * 3;
    nutrients.vitamin_A = carbs * 2;
    nutrients.potassium = carbs * 15;
    nutrients.fiber = carbs * 0.2;
    nutrients.sugar = carbs * 0.7;
    nutrients.vitamin_B6 = carbs * 0.02;
    
    // Special cases for specific fruits
    if (foodName.includes('pineapple')) {
      nutrients.vitamin_C = carbs * 4; // Pineapple is high in vitamin C
      nutrients.manganese = carbs * 0.1;
    }
    if (foodName.includes('watermelon')) {
      nutrients.vitamin_A = carbs * 3; // Watermelon has more vitamin A
      nutrients.vitamin_C = carbs * 1; // But less vitamin C
    }
  }
  
  // Grains and starches
  else if (foodName.includes('rice') || foodName.includes('bread') || foodName.includes('pasta') ||
           foodName.includes('potato') || foodName.includes('grain')) {
    nutrients.vitamin_B1 = carbs * 0.03;
    nutrients.vitamin_B3 = carbs * 0.2;
    nutrients.iron = carbs * 0.15;
    nutrients.magnesium = carbs * 1;
    nutrients.phosphorus = carbs * 4;
    nutrients.fiber = carbs * 0.1;
    nutrients.manganese = carbs * 0.05;
  }
  
  // Dairy
  else if (foodName.includes('cheese') || foodName.includes('milk') || foodName.includes('yogurt')) {
    nutrients.calcium = protein * 40;
    nutrients.vitamin_B12 = protein * 0.2;
    nutrients.vitamin_B2 = protein * 0.08;
    nutrients.phosphorus = protein * 30;
    nutrients.zinc = protein * 0.15;
    nutrients.saturated_fats = fat * 0.6;
  }
  
  // General estimates based on macronutrients for unknown foods
  else {
    nutrients.vitamin_C = Math.max(1, carbs * 0.5);
    nutrients.iron = Math.max(0.1, (protein + carbs) * 0.05);
    nutrients.calcium = Math.max(5, protein * 2);
    nutrients.potassium = Math.max(50, (protein + carbs) * 5);
    nutrients.magnesium = Math.max(5, calories * 0.1);
    nutrients.phosphorus = Math.max(20, protein * 5);
    nutrients.fiber = Math.max(0.5, carbs * 0.1);
  }
  
  // Ensure reasonable minimums for essential nutrients
  nutrients.vitamin_B1 = Math.max(0.01, nutrients.vitamin_B1);
  nutrients.vitamin_B2 = Math.max(0.01, nutrients.vitamin_B2);
  nutrients.vitamin_B3 = Math.max(0.1, nutrients.vitamin_B3);
  nutrients.iron = Math.max(0.1, nutrients.iron);
  nutrients.calcium = Math.max(5, nutrients.calcium);
  
  return nutrients;
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

    // SIMPLIFIED prompt that's more reliable for JSON generation
    const systemPrompt = `You are a nutrition expert. Analyze this food image and identify the main food items.

Return ONLY valid JSON with this EXACT structure (no extra text):

{
  "meal_name": "Descriptive Meal Name",
  "ingredients": [
    {
      "name": "specific food name",
      "weight_g": 100,
      "calories": 150,
      "protein_g": 5,
      "fat_g": 2,
      "carbs_g": 20,
      "vitamin_C": 25,
      "iron": 2,
      "calcium": 120
    }
  ]
}

CRITICAL RULES:
1. Identify 2-4 distinct food items you can clearly see
2. Use specific names like "grilled chicken breast", "steamed broccoli", "brown rice"
3. Provide realistic nutritional values per 100g for each food
4. NO text outside the JSON structure
5. Ensure all quotes are properly closed
6. Keep the JSON simple and valid`;

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
                content: systemPrompt
              },
              {
                role: "user",
                content: [
                  { type: "text", text: "Analyze this food image. Identify each distinct ingredient and return the exact JSON structure specified. Include ALL nutrients for every ingredient." },
                  { type: "image_url", image_url: { url: processedImage } }
                ]
              }
            ],
            max_tokens: 1200
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
              finalResponse = processVisionResponse(expandedResponse);
              
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
            let cleanedContent = content.trim();
            
            // Remove markdown code blocks if present
            cleanedContent = cleanedContent.replace(/^```json\s*/, '').replace(/\s*```$/, '');
            
            // Remove any leading/trailing whitespace
            cleanedContent = cleanedContent.trim();
            
            // Fix common JSON issues
            cleanedContent = cleanedContent
              .replace(/,\s*}/g, '}')     // Remove trailing commas before }
              .replace(/,\s*]/g, ']')     // Remove trailing commas before ]
              .replace(/"\s*:\s*,/g, '": null,')  // Fix empty values
              .replace(/:\s*,/g, ': null,')       // Fix missing values
              .replace(/,\s*,/g, ',');            // Fix double commas
            
            // Try to parse the cleaned response
            if (cleanedContent !== content) {
              try {
                console.log('Attempting to parse cleaned JSON...');
                const jsonResponse = JSON.parse(cleanedContent);
                console.log('Cleaned JSON parsed successfully!');
                
                if (jsonResponse.ingredients && jsonResponse.ingredients.length > 0) {
                  // Expand simple response to full nutrient profile using real nutritional knowledge
                  const expandedResponse = expandToFullNutrients(jsonResponse);
                  finalResponse = processVisionResponse(expandedResponse);
                  
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

// Legacy endpoint with real OpenAI - NO FALLBACKS, FAIL PROPERLY
app.post('/api/analyze-food', limiter, async (req, res) => {
  try {
    console.log('🔥 Legacy analyze food endpoint called - NO FALLBACKS');
    const { image } = req.body;

    if (!image) {
      console.error('No image provided in request');
      return res.status(400).json({
        success: false,
        error: 'Image data is required'
      });
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
      
      // SIMPLIFIED prompt that's more reliable for JSON generation
      const systemPrompt = `You are a nutrition expert. Analyze this food image and identify the main food items.

Return ONLY valid JSON with this EXACT structure (no extra text):

{
  "meal_name": "Descriptive Meal Name",
  "ingredients": [
    {
      "name": "specific food name",
      "weight_g": 100,
      "calories": 150,
      "protein_g": 5,
      "fat_g": 2,
      "carbs_g": 20,
      "vitamin_C": 25,
      "iron": 2,
      "calcium": 120
    }
  ]
}

CRITICAL RULES:
1. Identify 2-4 distinct food items you can clearly see
2. Use specific names like "grilled chicken breast", "steamed broccoli", "brown rice"
3. Provide realistic nutritional values per 100g for each food
4. NO text outside the JSON structure
5. Ensure all quotes are properly closed
6. Keep the JSON simple and valid`;

      // Make OpenAI API call with timeout
      const controller = new AbortController();
      const timeoutId = setTimeout(() => {
        console.log('🔥 OpenAI timeout - FAILING');
        controller.abort();
      }, 30000); // 30 second timeout

      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
        },
        signal: controller.signal,
        body: JSON.stringify({
          model: "gpt-4o",
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
                { type: "text", text: "Identify the main foods in this image." },
                { type: "image_url", image_url: { url: processedImage } }
              ]
            }
          ],
          max_tokens: 300
        })
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        console.log('🔥 OpenAI API error - FAILING:', response.status);
        return res.status(500).json({
          success: false,
          error: `OpenAI API error: ${response.status}`
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
        
        return res.json({
          success: true,
          data: finalResponse
        });
      } catch (parseError) {
        console.log('🔥 JSON parse failed - FAILING:', parseError.message);
        return res.status(500).json({
          success: false,
          error: 'OpenAI generated invalid JSON that could not be repaired'
        });
      }
    } catch (error) {
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