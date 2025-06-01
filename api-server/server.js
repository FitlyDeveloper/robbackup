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

    // RELIABLE prompt - get food names and let server generate nutrients
    const systemPrompt = `Analyze this food image and identify the main food items you can see.

Return ONLY this JSON structure with NO extra text:

{
  "ingredients": [
    {
      "name": "pineapple",
      "calories": 50,
      "weight_g": 100
    },
    {
      "name": "watermelon", 
      "calories": 30,
      "weight_g": 100
    }
  ]
}

Rules:
- Use specific food names like "pineapple", "watermelon", "chicken breast", "broccoli", "rice", "salmon"
- Provide realistic calories per 100g for each food
- Return 2-4 ingredients maximum
- NO explanations, NO markdown, ONLY the JSON`;

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
      
      // RELIABLE prompt - get food names and let server generate nutrients
      const systemPrompt = `Analyze this food image and identify the main food items you can see.

Return ONLY this JSON structure with NO extra text:

{
  "ingredients": [
    {
      "name": "pineapple",
      "calories": 50,
      "weight_g": 100
    },
    {
      "name": "watermelon", 
      "calories": 30,
      "weight_g": 100
    }
  ]
}

Rules:
- Use specific food names like "pineapple", "watermelon", "chicken breast", "broccoli", "rice", "salmon"
- Provide realistic calories per 100g for each food
- Return 2-4 ingredients maximum
- NO explanations, NO markdown, ONLY the JSON`;

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
        
        // Convert simple response to full format
        const fullResponse = convertSimpleToFullFormat(jsonResponse.ingredients);
        const result = processVisionResponse(fullResponse);
        
        return res.json({
          success: true,
          data: result
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

// Convert simple OpenAI response to full format with ALL 34 nutrients
function convertSimpleToFullFormat(simpleIngredients) {
  
  // Comprehensive nutrient database by food type
  function getNutrientsForFood(foodName, calories) {
    const name = foodName.toLowerCase();
    
    // Base macronutrients and micronutrients - will be overridden by specific foods
    let nutrients = {
      protein_g: 0,
      fat_g: 0,
      carbs_g: 0,
      vitamin_A: 0,
      vitamin_C: 0,
      vitamin_D: 0,
      vitamin_E: 0,
      vitamin_K: 0,
      vitamin_B1: 0,
      vitamin_B2: 0,
      vitamin_B3: 0,
      vitamin_B5: 0,
      vitamin_B6: 0,
      vitamin_B7: 0,
      vitamin_B9: 0,
      vitamin_B12: 0,
      calcium: 0,
      chloride: 0,
      chromium: 0,
      copper: 0,
      fluoride: 0,
      iodine: 0,
      iron: 0,
      magnesium: 0,
      manganese: 0,
      molybdenum: 0,
      phosphorus: 0,
      potassium: 0,
      selenium: 0,
      sodium: 0,
      zinc: 0,
      fiber: 0,
      cholesterol: 0,
      sugar: 0,
      saturated_fats: 0,
      omega_3: 0,
      omega_6: 0
    };

    // FRUITS
    if (name.includes('pineapple')) {
      nutrients = {
        protein_g: 0.5, fat_g: 0.1, carbs_g: 13,
        vitamin_A: 3, vitamin_C: 47, vitamin_D: 0, vitamin_E: 0.02, vitamin_K: 0.7,
        vitamin_B1: 0.08, vitamin_B2: 0.03, vitamin_B3: 0.5, vitamin_B5: 0.2, vitamin_B6: 0.1,
        vitamin_B7: 1, vitamin_B9: 18, vitamin_B12: 0,
        calcium: 13, chloride: 1, chromium: 0.1, copper: 110, fluoride: 0.1,
        iodine: 1, iron: 0.3, magnesium: 12, manganese: 0.9, molybdenum: 1,
        phosphorus: 8, potassium: 109, selenium: 0.1, sodium: 1, zinc: 0.1,
        fiber: 1.4, cholesterol: 0, sugar: 10, saturated_fats: 0, omega_3: 0, omega_6: 0
      };
    } else if (name.includes('watermelon')) {
      nutrients = {
        protein_g: 0.6, fat_g: 0.2, carbs_g: 8,
        vitamin_A: 28, vitamin_C: 8, vitamin_D: 0, vitamin_E: 0.05, vitamin_K: 0.1,
        vitamin_B1: 0.03, vitamin_B2: 0.02, vitamin_B3: 0.2, vitamin_B5: 0.2, vitamin_B6: 0.05,
        vitamin_B7: 1, vitamin_B9: 3, vitamin_B12: 0,
        calcium: 7, chloride: 1, chromium: 0.1, copper: 42, fluoride: 0.1,
        iodine: 1, iron: 0.2, magnesium: 10, manganese: 0.04, molybdenum: 1,
        phosphorus: 11, potassium: 112, selenium: 0.4, sodium: 1, zinc: 0.1,
        fiber: 0.4, cholesterol: 0, sugar: 6, saturated_fats: 0.1, omega_3: 0, omega_6: 0.1
      };
    } else if (name.includes('apple')) {
      nutrients = {
        protein_g: 0.3, fat_g: 0.2, carbs_g: 14,
        vitamin_A: 3, vitamin_C: 5, vitamin_D: 0, vitamin_E: 0.18, vitamin_K: 2.2,
        vitamin_B1: 0.02, vitamin_B2: 0.03, vitamin_B3: 0.1, vitamin_B5: 0.06, vitamin_B6: 0.04,
        vitamin_B7: 1, vitamin_B9: 3, vitamin_B12: 0,
        calcium: 6, chloride: 1, chromium: 0.1, copper: 27, fluoride: 0.1,
        iodine: 1, iron: 0.1, magnesium: 5, manganese: 0.04, molybdenum: 1,
        phosphorus: 11, potassium: 107, selenium: 0, sodium: 1, zinc: 0.04,
        fiber: 2.4, cholesterol: 0, sugar: 10, saturated_fats: 0.03, omega_3: 9, omega_6: 0.04
      };
    } else if (name.includes('banana')) {
      nutrients = {
        protein_g: 1.1, fat_g: 0.3, carbs_g: 23,
        vitamin_A: 3, vitamin_C: 9, vitamin_D: 0, vitamin_E: 0.1, vitamin_K: 0.5,
        vitamin_B1: 0.03, vitamin_B2: 0.07, vitamin_B3: 0.7, vitamin_B5: 0.3, vitamin_B6: 0.4,
        vitamin_B7: 2, vitamin_B9: 20, vitamin_B12: 0,
        calcium: 5, chloride: 1, chromium: 0.1, copper: 78, fluoride: 0.1,
        iodine: 1, iron: 0.3, magnesium: 27, manganese: 0.3, molybdenum: 1,
        phosphorus: 22, potassium: 358, selenium: 1, sodium: 1, zinc: 0.2,
        fiber: 2.6, cholesterol: 0, sugar: 12, saturated_fats: 0.1, omega_3: 27, omega_6: 0.05
      };
    }
    
    // VEGETABLES
    else if (name.includes('broccoli')) {
      nutrients = {
        protein_g: 2.8, fat_g: 0.4, carbs_g: 7,
        vitamin_A: 623, vitamin_C: 89, vitamin_D: 0, vitamin_E: 0.78, vitamin_K: 102,
        vitamin_B1: 0.07, vitamin_B2: 0.12, vitamin_B3: 0.6, vitamin_B5: 0.6, vitamin_B6: 0.2,
        vitamin_B7: 1.5, vitamin_B9: 63, vitamin_B12: 0,
        calcium: 47, chloride: 1, chromium: 0.1, copper: 49, fluoride: 0.1,
        iodine: 1, iron: 0.7, magnesium: 21, manganese: 0.2, molybdenum: 1,
        phosphorus: 66, potassium: 316, selenium: 2.5, sodium: 33, zinc: 0.4,
        fiber: 2.6, cholesterol: 0, sugar: 1.5, saturated_fats: 0.1, omega_3: 21, omega_6: 0.1
      };
    } else if (name.includes('carrot')) {
      nutrients = {
        protein_g: 0.9, fat_g: 0.2, carbs_g: 10,
        vitamin_A: 835, vitamin_C: 6, vitamin_D: 0, vitamin_E: 0.66, vitamin_K: 13,
        vitamin_B1: 0.07, vitamin_B2: 0.06, vitamin_B3: 1, vitamin_B5: 0.3, vitamin_B6: 0.1,
        vitamin_B7: 2.5, vitamin_B9: 19, vitamin_B12: 0,
        calcium: 33, chloride: 1, chromium: 0.1, copper: 45, fluoride: 0.1,
        iodine: 1, iron: 0.3, magnesium: 12, manganese: 0.1, molybdenum: 1,
        phosphorus: 35, potassium: 320, selenium: 0.1, sodium: 69, zinc: 0.2,
        fiber: 2.8, cholesterol: 0, sugar: 4.7, saturated_fats: 0.04, omega_3: 2, omega_6: 0.1
      };
    }
    
    // PROTEINS
    else if (name.includes('chicken')) {
      nutrients = {
        protein_g: 25, fat_g: 14, carbs_g: 0,
        vitamin_A: 6, vitamin_C: 1.6, vitamin_D: 0.2, vitamin_E: 0.27, vitamin_K: 0.4,
        vitamin_B1: 0.07, vitamin_B2: 0.12, vitamin_B3: 8.5, vitamin_B5: 0.8, vitamin_B6: 0.5,
        vitamin_B7: 10, vitamin_B9: 4, vitamin_B12: 0.3,
        calcium: 15, chloride: 1, chromium: 0.1, copper: 76, fluoride: 0.1,
        iodine: 1, iron: 1, magnesium: 20, manganese: 0.02, molybdenum: 1,
        phosphorus: 147, potassium: 189, selenium: 14, sodium: 70, zinc: 1.3,
        fiber: 0, cholesterol: 75, sugar: 0, saturated_fats: 4, omega_3: 62, omega_6: 2.5
      };
    } else if (name.includes('salmon') || name.includes('fish')) {
      nutrients = {
        protein_g: 25, fat_g: 11, carbs_g: 0,
        vitamin_A: 12, vitamin_C: 0, vitamin_D: 11, vitamin_E: 1.22, vitamin_K: 0.1,
        vitamin_B1: 0.23, vitamin_B2: 0.15, vitamin_B3: 8.5, vitamin_B5: 1.7, vitamin_B6: 0.6,
        vitamin_B7: 5, vitamin_B9: 25, vitamin_B12: 2.8,
        calcium: 9, chloride: 1, chromium: 0.1, copper: 90, fluoride: 0.1,
        iodine: 1, iron: 0.3, magnesium: 30, manganese: 0.02, molybdenum: 1,
        phosphorus: 200, potassium: 363, selenium: 36, sodium: 44, zinc: 0.4,
        fiber: 0, cholesterol: 55, sugar: 0, saturated_fats: 1.8, omega_3: 2260, omega_6: 0.13
      };
    } else if (name.includes('beef') || name.includes('steak')) {
      nutrients = {
        protein_g: 26, fat_g: 15, carbs_g: 0,
        vitamin_A: 0, vitamin_C: 0, vitamin_D: 0.1, vitamin_E: 0.6, vitamin_K: 1.6,
        vitamin_B1: 0.04, vitamin_B2: 0.18, vitamin_B3: 4.4, vitamin_B5: 0.6, vitamin_B6: 0.4,
        vitamin_B7: 3, vitamin_B9: 6, vitamin_B12: 2.6,
        calcium: 18, chloride: 1, chromium: 0.1, copper: 73, fluoride: 0.1,
        iodine: 1, iron: 2.9, magnesium: 21, manganese: 0.01, molybdenum: 1,
        phosphorus: 198, potassium: 318, selenium: 14.2, sodium: 72, zinc: 4.8,
        fiber: 0, cholesterol: 90, sugar: 0, saturated_fats: 6, omega_3: 84, omega_6: 0.5
      };
    }
    
    // GRAINS
    else if (name.includes('rice')) {
      nutrients = {
        protein_g: 2.7, fat_g: 0.3, carbs_g: 23,
        vitamin_A: 0, vitamin_C: 0, vitamin_D: 0, vitamin_E: 0.11, vitamin_K: 0.1,
        vitamin_B1: 0.07, vitamin_B2: 0.05, vitamin_B3: 1.6, vitamin_B5: 1, vitamin_B6: 0.16,
        vitamin_B7: 2, vitamin_B9: 8, vitamin_B12: 0,
        calcium: 28, chloride: 1, chromium: 0.1, copper: 220, fluoride: 0.1,
        iodine: 1, iron: 0.8, magnesium: 25, manganese: 1.1, molybdenum: 1,
        phosphorus: 115, potassium: 115, selenium: 15, sodium: 5, zinc: 1.1,
        fiber: 0.4, cholesterol: 0, sugar: 0.1, saturated_fats: 0.1, omega_3: 5, omega_6: 0.1
      };
    }
    
    // DEFAULT for unknown foods - use calories to estimate
    else {
      const calorieRatio = calories / 100; // Scale based on calories
      nutrients = {
        protein_g: Math.round(calorieRatio * 3),
        fat_g: Math.round(calorieRatio * 2),
        carbs_g: Math.round(calorieRatio * 15),
        vitamin_A: Math.round(calorieRatio * 10),
        vitamin_C: Math.round(calorieRatio * 5),
        vitamin_D: 0, vitamin_E: Math.round(calorieRatio * 0.5), vitamin_K: Math.round(calorieRatio * 2),
        vitamin_B1: Math.round(calorieRatio * 0.1 * 100) / 100,
        vitamin_B2: Math.round(calorieRatio * 0.1 * 100) / 100,
        vitamin_B3: Math.round(calorieRatio * 1),
        vitamin_B5: Math.round(calorieRatio * 0.5 * 100) / 100,
        vitamin_B6: Math.round(calorieRatio * 0.2 * 100) / 100,
        vitamin_B7: Math.round(calorieRatio * 2), vitamin_B9: Math.round(calorieRatio * 10), vitamin_B12: 0,
        calcium: Math.round(calorieRatio * 20), chloride: 1, chromium: 0.1,
        copper: Math.round(calorieRatio * 50), fluoride: 0.1, iodine: 1,
        iron: Math.round(calorieRatio * 1), magnesium: Math.round(calorieRatio * 15),
        manganese: Math.round(calorieRatio * 0.2 * 100) / 100, molybdenum: 1,
        phosphorus: Math.round(calorieRatio * 50), potassium: Math.round(calorieRatio * 150),
        selenium: Math.round(calorieRatio * 2), sodium: Math.round(calorieRatio * 10),
        zinc: Math.round(calorieRatio * 0.5 * 100) / 100,
        fiber: Math.round(calorieRatio * 2), cholesterol: 0, sugar: Math.round(calorieRatio * 5),
        saturated_fats: Math.round(calorieRatio * 0.5 * 100) / 100, omega_3: Math.round(calorieRatio * 10), omega_6: Math.round(calorieRatio * 0.2 * 100) / 100
      };
    }

    return nutrients;
  }

  const fullIngredients = simpleIngredients.map(ingredient => {
    const name = ingredient.name || 'Food Item';
    const calories = ingredient.calories || 100;
    const weight = ingredient.weight_g || 100;
    
    // Get comprehensive nutrients for this food
    const nutrients = getNutrientsForFood(name, calories);
    
    return {
      name: name,
      weight_g: weight,
      calories: calories,
      ...nutrients
    };
  });
  
  return {
    meal_name: "Mixed Plate",
    ingredients: convertFlatNutrientsToNested(fullIngredients)
  };
}

// Start the server
app.listen(PORT, () => {
  console.log(`Server with real OpenAI integration running on port ${PORT}`);
});