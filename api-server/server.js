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

// Add nutrients to ingredients based on food type
function addNutrientsToIngredients(ingredients) {
  return ingredients.map(ingredient => {
    const name = ingredient.name.toLowerCase();
    
    // Default nutrients that will be added to every ingredient
    const defaultNutrients = {
      vitamins: {
        vitamin_A_mcg: 10, vitamin_C_mg: 5, vitamin_D_mcg: 0, vitamin_E_mg: 1, 
        vitamin_K_mcg: 2, vitamin_B1_mg: 0.1, vitamin_B2_mg: 0.1, vitamin_B3_mg: 1, 
        vitamin_B5_mg: 0.5, vitamin_B6_mg: 0.2, vitamin_B7_mcg: 2, vitamin_B9_mcg: 20, 
        vitamin_B12_mcg: 0
      },
      minerals: {
        calcium_mg: 50, chloride_mg: 100, chromium_mcg: 1, copper_mcg: 100, 
        fluoride_mg: 0.1, iodine_mcg: 10, iron_mg: 2, magnesium_mg: 25, 
        manganese_mg: 0.5, molybdenum_mcg: 5, phosphorus_mg: 80, potassium_mg: 200, 
        selenium_mcg: 5, sodium_mg: 50, zinc_mg: 1
      },
      other: {
        fiber_g: 3, cholesterol_mg: 0, sugar_g: 5, saturated_fats_g: 0.5, 
        omega_3_mg: 50, omega_6_g: 0.2
      }
    };
    
    // Enhanced nutrients based on food type
    if (name.includes('chicken') || name.includes('meat') || name.includes('beef') || name.includes('pork')) {
      defaultNutrients.vitamins.vitamin_B12_mcg = 2.4;
      defaultNutrients.minerals.iron_mg = 8;
      defaultNutrients.minerals.zinc_mg = 4;
      defaultNutrients.other.cholesterol_mg = 70;
    } else if (name.includes('fish') || name.includes('salmon') || name.includes('tuna')) {
      defaultNutrients.vitamins.vitamin_D_mcg = 10;
      defaultNutrients.vitamins.vitamin_B12_mcg = 4;
      defaultNutrients.other.omega_3_mg = 1000;
      defaultNutrients.other.cholesterol_mg = 50;
    } else if (name.includes('vegetable') || name.includes('broccoli') || name.includes('spinach') || name.includes('carrot')) {
      defaultNutrients.vitamins.vitamin_A_mcg = 500;
      defaultNutrients.vitamins.vitamin_C_mg = 50;
      defaultNutrients.vitamins.vitamin_K_mcg = 100;
      defaultNutrients.other.fiber_g = 8;
      defaultNutrients.other.cholesterol_mg = 0;
    } else if (name.includes('rice') || name.includes('bread') || name.includes('pasta') || name.includes('grain')) {
      defaultNutrients.vitamins.vitamin_B1_mg = 0.5;
      defaultNutrients.vitamins.vitamin_B3_mg = 3;
      defaultNutrients.other.fiber_g = 2;
      defaultNutrients.other.cholesterol_mg = 0;
    }
    
    return {
      ...ingredient,
      ...defaultNutrients
    };
  });
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

    // System prompt for accurate food recognition - ULTRA SIMPLIFIED TO AVOID JSON ERRORS
    const systemPrompt = `You are a food analyst. Analyze the image and identify the main food items visible.

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
      "vitamin_A": 10,
      "vitamin_C": 5,
      "vitamin_D": 0,
      "vitamin_E": 1,
      "vitamin_K": 2,
      "vitamin_B1": 0.1,
      "vitamin_B2": 0.1,
      "vitamin_B3": 1,
      "vitamin_B5": 0.5,
      "vitamin_B6": 0.2,
      "vitamin_B7": 2,
      "vitamin_B9": 20,
      "vitamin_B12": 0,
      "calcium": 50,
      "chloride": 100,
      "chromium": 1,
      "copper": 100,
      "fluoride": 0.1,
      "iodine": 10,
      "iron": 2,
      "magnesium": 25,
      "manganese": 0.5,
      "molybdenum": 5,
      "phosphorus": 80,
      "potassium": 200,
      "selenium": 5,
      "sodium": 50,
      "zinc": 1,
      "fiber": 3,
      "cholesterol": 0,
      "sugar": 5,
      "saturated_fats": 0.5,
      "omega_3": 50,
      "omega_6": 0.2
    }
  ]
}

CRITICAL RULES:
1. Identify 2-4 distinct food items you can clearly see
2. Use specific names: "grilled chicken breast", "steamed broccoli", "brown rice", "mixed salad"
3. ALL numeric values must be valid numbers (integers or decimals)
4. NO text outside the JSON structure
5. Ensure all quotes are properly closed
6. Do NOT include any explanations or markdown
7. Include ALL nutrients for each ingredient with realistic values based on the food type`;

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
      
      // System prompt for accurate food recognition - ULTRA SIMPLIFIED TO AVOID JSON ERRORS
      const systemPrompt = `You are a food analyst. Analyze the image and identify the main food items visible.

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
      "vitamin_A": 10,
      "vitamin_C": 5,
      "vitamin_D": 0,
      "vitamin_E": 1,
      "vitamin_K": 2,
      "vitamin_B1": 0.1,
      "vitamin_B2": 0.1,
      "vitamin_B3": 1,
      "vitamin_B5": 0.5,
      "vitamin_B6": 0.2,
      "vitamin_B7": 2,
      "vitamin_B9": 20,
      "vitamin_B12": 0,
      "calcium": 50,
      "chloride": 100,
      "chromium": 1,
      "copper": 100,
      "fluoride": 0.1,
      "iodine": 10,
      "iron": 2,
      "magnesium": 25,
      "manganese": 0.5,
      "molybdenum": 5,
      "phosphorus": 80,
      "potassium": 200,
      "selenium": 5,
      "sodium": 50,
      "zinc": 1,
      "fiber": 3,
      "cholesterol": 0,
      "sugar": 5,
      "saturated_fats": 0.5,
      "omega_3": 50,
      "omega_6": 0.2
    }
  ]
}

CRITICAL RULES:
1. Identify 2-4 distinct food items you can clearly see
2. Use specific names: "grilled chicken breast", "steamed broccoli", "brown rice", "mixed salad"
3. ALL numeric values must be valid numbers (integers or decimals)
4. NO text outside the JSON structure
5. Ensure all quotes are properly closed
6. Do NOT include any explanations or markdown
7. Include ALL nutrients for each ingredient with realistic values based on the food type`;

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
                { type: "text", text: "Analyze this food image. Identify each distinct ingredient and return the exact JSON structure specified. Include ALL nutrients for every ingredient." },
                { type: "image_url", image_url: { url: processedImage } }
            ]
          }
        ],
          max_tokens: 1200
      })
    });

      if (response.ok) {
        const responseData = await response.json();
        const content = responseData.choices[0].message.content.trim();
        
        try {
          // Log the raw response for debugging
          console.log('LEGACY ENDPOINT - Raw OpenAI response length:', content.length);
          console.log('LEGACY ENDPOINT - Raw response preview (first 500 chars):', content.substring(0, 500));
          
          // SECOND: Try simple JSON cleaning
          console.log('LEGACY ENDPOINT - Attempting simple JSON cleaning...');
          let cleanedContent = content.trim();
          
          // Remove markdown blocks
          cleanedContent = cleanedContent.replace(/^```json\s*/, '').replace(/\s*```$/, '');
          cleanedContent = cleanedContent.replace(/^```\s*/, '').replace(/\s*```$/, '');
          
          // AGGRESSIVE JSON REPAIR
          cleanedContent = cleanedContent
            .replace(/,\s*}/g, '}')     // Remove trailing commas before }
            .replace(/,\s*]/g, ']')     // Remove trailing commas before ]
            .replace(/,\s*,/g, ',')     // Remove double commas
            .replace(/:\s*,/g, ': null,')  // Fix empty values
            .replace(/"\s*:\s*,/g, '": null,')  // Fix empty string values
            .replace(/:\s*([^",}\]]+)(?=\s*[,}\]])/g, ': "$1"')  // Quote unquoted string values
            .replace(/:\s*"([^"]*)\n/g, ': "$1",\n')  // Fix unterminated strings at line end
            .replace(/:\s*"([^"]*?)(?=\s*[,}\]])/g, ': "$1"')  // Fix unterminated strings before delimiters
            .replace(/([^\\])"([^",:}\]]*)"([^,}\]]*)/g, '$1"$2"$3')  // Fix broken quotes
            .replace(/"\s*:\s*([0-9.]+)\s*([,}\]])/g, '": $1$2')  // Fix number formatting
            .replace(/([{,]\s*)"([^"]*)"(\s*:\s*)"([^"]*)"([^,}\]]*)/g, '$1"$2"$3"$4"$5'); // Fix quote issues
          
          // Try to fix specific unterminated string patterns
          const lines = cleanedContent.split('\n');
          for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            // Count unescaped quotes in the line
            const quotes = (line.match(/(?<!\\)"/g) || []).length;
            if (quotes % 2 !== 0) {
              // Odd number of quotes - likely unterminated string
              console.log(`LEGACY ENDPOINT - Fixing unterminated string on line ${i + 1}: ${line.substring(0, 100)}...`);
              // Add closing quote before comma, brace, or bracket
              lines[i] = line.replace(/([^"])(\s*[,}\]])/, '$1"$2');
            }
          }
          cleanedContent = lines.join('\n');
          
          try {
            const cleanedJson = JSON.parse(cleanedContent);
            console.log('LEGACY ENDPOINT - Cleaned JSON parsed successfully!');
            
            if (cleanedJson.ingredients && cleanedJson.ingredients.length > 0) {
              // Convert flat nutrient structure to nested structure expected by app
              const convertedJson = {
                ...cleanedJson,
                ingredients: convertFlatNutrientsToNested(cleanedJson.ingredients)
              };
              
              const result = processVisionResponse(convertedJson);
              return res.json({
                success: true,
                data: result
              });
            } else {
              console.log('LEGACY ENDPOINT - No ingredients found in cleaned response');
            }
          } catch (cleanError) {
            console.log('LEGACY ENDPOINT - Cleaned JSON parse failed:', cleanError.message);
            
            // FINAL ATTEMPT: Try to extract just the ingredients array
            console.log('LEGACY ENDPOINT - Attempting to extract ingredients array...');
            try {
              const ingredientsMatch = content.match(/"ingredients"\s*:\s*\[(.*?)\]/s);
              if (ingredientsMatch) {
                const ingredientsStr = `{"ingredients": [${ingredientsMatch[1]}]}`;
                const ingredientsJson = JSON.parse(ingredientsStr);
                
                if (ingredientsJson.ingredients && ingredientsJson.ingredients.length > 0) {
                  // Convert flat nutrient structure and add default meal name
                  const convertedJson = {
                    meal_name: "Mixed Plate",
                    ingredients: convertFlatNutrientsToNested(ingredientsJson.ingredients)
                  };
                  
                  const result = processVisionResponse(convertedJson);
                  return res.json({
                    success: true,
                    data: result,
                    note: "Extracted ingredients from partial JSON"
                  });
                }
              }
            } catch (extractError) {
              console.log('LEGACY ENDPOINT - Ingredient extraction failed:', extractError.message);
            }
          }
          
          // If we reach here, all parsing attempts failed
          console.error('LEGACY ENDPOINT - All JSON parsing attempts failed');
          console.log('LEGACY ENDPOINT - Raw response (first 1000 chars):', content.substring(0, 1000));
          console.log('LEGACY ENDPOINT - Raw response (last 500 chars):', content.substring(Math.max(0, content.length - 500)));
          
          return res.status(500).json({
            success: false,
            error: 'OpenAI generated invalid JSON that could not be repaired. Please try again.'
          });
        } catch (parseError) {
          console.error(`LEGACY ENDPOINT - JSON PARSE ERROR: ${parseError.message}`);
          return res.status(500).json({
            success: false,
            error: `JSON parsing failed: ${parseError.message}`
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