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
1. **Compound Foods as Single Items**: Treat compound foods like "grilled chicken thigh", "beef steak", "pork chop" as ONE ingredient, not separate parts
2. **Precise Values**: Provide exact decimal values (e.g., 23.7g, not 24g)
3. **Comprehensive Analysis**: Include all visible food components
4. **Short Names**: Use concise ingredient names (e.g., "tomatoes" not "sliced tomatoes", "chicken" not "grilled chicken breast")
5. **Recognizable Meal Names**: If the meal is recognizable (like "Chicken Caesar Salad", "Beef Tacos", "Margherita Pizza"), use that name. Otherwise use generic names like "Mixed Plate", "Dinner Bowl", "Lunch Plate", etc.

INGREDIENT IDENTIFICATION RULES:
- **Proteins**: "chicken" = 1 ingredient (NOT "grilled chicken breast")
- **Vegetables**: each distinct vegetable type (tomatoes, cucumbers, lettuce, etc.) - use simple names
- **Grains/Starches**: rice, bread, pasta, potatoes as separate items
- **Sauces/Condiments**: dressings, sauces, oils as separate items
- **Sides**: coleslaw, salads, etc. as separate items

NAMING GUIDELINES:
- **Ingredient Names**: Keep simple - "chicken" not "grilled chicken breast", "tomatoes" not "cherry tomatoes", "sausages" not "grilled sausages"
- **Meal Names**: Use recognizable dish names when possible (Pizza, Pasta, Tacos, Salad, etc.) or generic terms (Mixed Plate, Dinner Bowl, Lunch)

IMPORTANT GUIDELINES:
1. **Don't over-split**: "chicken breast" = 1 ingredient, "beef steak" = 1 ingredient
2. **Do identify separate items**: chicken + vegetables + rice = 3 ingredients
3. **Include garnishes**: herbs, spices, small vegetables as separate if visible
4. **Systematic scanning**: Look at all areas of the plate/image
5. **Minimum threshold**: Try to identify 2-5 ingredients for typical meals

RESPONSE FORMAT (JSON ONLY):
Return a JSON object with meal_name and ingredients array. Each ingredient should have:
- name: simple, concise name (e.g., "chicken", "tomatoes", "rice")
- weight_g: estimated weight
- calories, protein_g, fat_g, carbs_g: nutritional values
- vitamins: object with vitamin values
- minerals: object with mineral values  
- other: object with fiber, cholesterol, etc.

IMPORTANT:
- EVERY number MUST end with .0 even for whole numbers
- Keep ingredient names short and simple
- Use recognizable meal names or generic terms like "Mixed Plate"
- Include comprehensive vitamin/mineral data for each ingredient`;

    let finalResponse = null;
    
    if (process.env.OPENAI_API_KEY) {
      try {
        // Use AbortController for timeout
        const controller = new AbortController();
        const timeoutId = setTimeout(() => {
          console.log(`OpenAI API call timeout for job ${jobId}`);
          controller.abort();
        }, 60000); // Increased to 60 seconds
        
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
                  { type: "text", text: "Analyze this food image. Identify each distinct food item as a single ingredient (e.g., grilled chicken thigh = 1 ingredient, not grilled chicken + thigh). Look for proteins, vegetables, sides, and sauces as separate items." },
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
        await updateJobStatus(jobId, {
          status: 'failed',
          progress: 100,
          completedAt: Date.now(),
          error: `API call error: ${error.message}`
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
    
    // Remove common descriptive words
    const wordsToRemove = [
      'grilled', 'fried', 'baked', 'roasted', 'steamed', 'boiled',
      'sliced', 'diced', 'chopped', 'minced', 'fresh', 'cooked',
      'seasoned', 'marinated', 'sautéed', 'pan-fried', 'deep-fried'
    ];
    
    let cleaned = name.toLowerCase();
    
    // Remove descriptive words
    wordsToRemove.forEach(word => {
      const regex = new RegExp(`\\b${word}\\s+`, 'gi');
      cleaned = cleaned.replace(regex, '');
    });
    
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
        visionResponse.meal_name.length < 50 && 
        !visionResponse.meal_name.includes(' with ') &&
        !visionResponse.meal_name.includes(' and ')) {
      return visionResponse.meal_name;
    }
    
    const ingredients = ingredientNames.map(name => name.toLowerCase());
    
    // Check for recognizable meal patterns
    if (ingredients.some(ing => ing.includes('pizza'))) {
      return "Pizza";
    }
    if (ingredients.some(ing => ing.includes('pasta') || ing.includes('spaghetti') || ing.includes('noodles'))) {
      return "Pasta Dish";
    }
    if (ingredients.some(ing => ing.includes('taco') || ing.includes('tortilla'))) {
      return "Tacos";
    }
    if (ingredients.some(ing => ing.includes('burger') || ing.includes('bun'))) {
      return "Burger";
    }
    if (ingredients.some(ing => ing.includes('salad') || ing.includes('lettuce')) && 
        ingredients.length >= 3) {
      return "Salad";
    }
    if (ingredients.some(ing => ing.includes('soup'))) {
      return "Soup";
    }
    if (ingredients.some(ing => ing.includes('sandwich'))) {
      return "Sandwich";
    }
    if (ingredients.some(ing => ing.includes('rice')) && ingredients.length >= 2) {
      return "Rice Bowl";
    }
    if (ingredients.some(ing => ing.includes('steak') || ing.includes('beef'))) {
      return "Steak Dinner";
    }
    if (ingredients.some(ing => ing.includes('chicken'))) {
      return "Chicken Dish";
    }
    if (ingredients.some(ing => ing.includes('fish') || ing.includes('salmon') || ing.includes('tuna'))) {
      return "Fish Dish";
    }
    
    // Generic names based on number of ingredients
    if (ingredients.length === 1) {
      return ingredientNames[0];
    } else if (ingredients.length <= 3) {
      return "Light Meal";
    } else {
      return "Mixed Plate";
    }
  }
  
  // Map ingredients to our format with comprehensive nutrition data and clean names
  const mappedIngredients = ingredients.map(item => {
    const ingredient = {
      name: cleanIngredientName(item.name),
      weight_g: item.weight_g || 100.0,
      calories: item.calories || 0,
      protein_g: item.protein_g || 0,
      fat_g: item.fat_g || 0,
      carbs_g: item.carbs_g || 0
    };

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

Return valid JSON with this EXACT structure:
{
  "ingredients": [
    { 
      "name": "specific food name (e.g. grilled chicken breast, white rice, broccoli)", 
      "weight_g": 100, 
      "calories": 165,
      "protein_g": 31, 
      "fat_g": 4, 
      "carbs_g": 0,
      "vitamins": {
        "vitamin_a": 0, "vitamin_c": 0, "vitamin_d": 0, "vitamin_e": 1.2, "vitamin_k": 0.3,
        "vitamin_b1": 0.1, "vitamin_b2": 0.2, "vitamin_b3": 12.5, "vitamin_b5": 1.8, 
        "vitamin_b6": 0.6, "vitamin_b7": 3.2, "vitamin_b9": 8, "vitamin_b12": 0.3
      },
      "minerals": {
        "calcium": 15, "iron": 1.0, "magnesium": 29, "potassium": 256, "sodium": 74, "zinc": 1.9,
        "chromium": 0.1, "copper": 45, "iodine": 2, "molybdenum": 1.5, "selenium": 8.5,
        "fluoride": 0, "manganese": 0.1, "phosphorus": 200
      },
      "other": {
        "fiber": 0, "cholesterol": 85, "sugar": 0, "saturated_fats": 1.1, "omega_3": 74, "omega_6": 0.6
      }
    }
  ],
  "total": { 
    "calories": 165, "protein_g": 31, "fat_g": 4, "carbs_g": 0,
    "vitamins": {
      "vitamin_a": 0, "vitamin_c": 0, "vitamin_d": 0, "vitamin_e": 1.2, "vitamin_k": 0.3,
      "vitamin_b1": 0.1, "vitamin_b2": 0.2, "vitamin_b3": 12.5, "vitamin_b5": 1.8, 
      "vitamin_b6": 0.6, "vitamin_b7": 3.2, "vitamin_b9": 8, "vitamin_b12": 0.3
    },
    "minerals": {
      "calcium": 15, "iron": 1.0, "magnesium": 29, "potassium": 256, "sodium": 74, "zinc": 1.9,
      "chromium": 0.1, "copper": 45, "iodine": 2, "molybdenum": 1.5, "selenium": 8.5,
      "fluoride": 0, "manganese": 0.1, "phosphorus": 200
    },
    "other": {
      "fiber": 0, "cholesterol": 85, "sugar": 0, "saturated_fats": 1.1, "omega_3": 74, "omega_6": 0.6
    }
  }
}

UNITS (CRITICAL - DO NOT CONVERT):
Vitamins: A,D,K,B7,B9,B12=mcg | C,E,B1,B2,B3,B5,B6=mg
Minerals: Ca,Fe,Mg,K,Na,Zn,Fluoride,Manganese,Phosphorus=mg | Cr,Cu,I,Mo,Se=mcg  
Other: fiber,sugar,saturated_fats,omega_6=g | cholesterol,omega_3=mg

CRITICAL REQUIREMENTS:
- ALWAYS include ALL 13 vitamins, ALL 14 minerals, ALL 6 other nutrients
- NEVER omit any nutrient - use 0 if not present
- Include fluoride, manganese, phosphorus in minerals (all in mg)
- Use exact units specified above
- MINIMUM 2 ingredients for any meal (unless truly single item)
- SCAN SYSTEMATICALLY: Look at all areas of the plate/image
- IDENTIFY LAYERS: Check for ingredients that might be layered or mixed

DETECTION STRATEGY:
1. Scan the entire image systematically (left to right, top to bottom)
2. Identify the main protein(s) - meat, fish, eggs, dairy
3. Identify all vegetables - even small garnishes count
4. Identify starches/grains - rice, bread, pasta, potatoes
5. Identify sides/salads - coleslaw, mixed salads, etc.
6. Identify sauces/condiments - dressings, oils, etc.
7. Double-check: Have I found at least 2-3 distinct items?

QUALITY CHECK:
- If you only detect 1 ingredient, look again more carefully
- Complex plated meals should have 3-6 ingredients typically
- Use realistic USDA nutrition values with precise decimal places
- Include ALL nutrients with correct units
- Use 0 for absent nutrients (e.g. cholesterol in vegetables)`;

      // Make OpenAI API call
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
        timeout: 90000, // 90 second timeout for legacy endpoint to match main endpoint
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
                { type: "text", text: "Analyze this meal image and identify ALL separate food components. Look carefully at every part of the plate - identify each distinct ingredient separately (proteins, vegetables, sides, garnishes). For complex meals, you should typically find 3-6 distinct ingredients. Return comprehensive nutrition data in JSON format exactly as specified." },
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
          
          // Check for position 4443 specifically where the error occurs
          if (content.length > 4443) {
            console.log('LEGACY ENDPOINT - Character at position 4443:', JSON.stringify(content.charAt(4443)));
            console.log('LEGACY ENDPOINT - Context around position 4443:', JSON.stringify(content.substring(4430, 4450)));
          }
          
          // Try to clean the response
          let cleanedContent = content.trim();
          
          // Remove markdown code blocks if present
          if (cleanedContent.startsWith('```json')) {
            cleanedContent = cleanedContent.replace(/^```json\s*/, '').replace(/\s*```$/, '');
          } else if (cleanedContent.startsWith('```')) {
            cleanedContent = cleanedContent.replace(/^```\s*/, '').replace(/\s*```$/, '');
          }
          
          // Fix common JSON issues that cause unterminated strings
          cleanedContent = cleanedContent
            .replace(/\n/g, ' ')     // Replace newlines with spaces
            .replace(/\r/g, ' ')     // Replace carriage returns with spaces  
            .replace(/\t/g, ' ')     // Replace tabs with spaces
            .replace(/\s+/g, ' ');   // Collapse multiple spaces
          
          console.log('LEGACY ENDPOINT - Cleaned response preview (first 500 chars):', cleanedContent.substring(0, 500));
          
          // Parse JSON response
          const jsonResponse = JSON.parse(cleanedContent);
          
          // Check if we have valid ingredients
          if (jsonResponse.ingredients && jsonResponse.ingredients.length > 0) {
            // Convert OpenAI's response to our expected format
            const result = processVisionResponse(jsonResponse);
            return res.json({
              success: true,
              data: result
            });
          } else {
            return res.status(422).json({
              success: false,
              error: 'No food ingredients could be detected in the image'
            });
          }
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
            
            // Find the last complete ingredient object
            const ingredientsStartMatch = repairedContent.match(/"ingredients":\s*\[/);
            if (ingredientsStartMatch) {
              const ingredientsStart = ingredientsStartMatch.index + ingredientsStartMatch[0].length;
              let ingredientsContent = repairedContent.substring(ingredientsStart);
              
              // Find complete ingredient objects by counting braces
              let completeIngredients = [];
              let currentIngredient = '';
              let braceCount = 0;
              let inString = false;
              let escapeNext = false;
              
              for (let i = 0; i < ingredientsContent.length; i++) {
                const char = ingredientsContent[i];
                
                if (escapeNext) {
                  escapeNext = false;
                  currentIngredient += char;
                  continue;
                }
                
                if (char === '\\') {
                  escapeNext = true;
                  currentIngredient += char;
                  continue;
                }
                
                if (char === '"' && !escapeNext) {
                  inString = !inString;
                }
                
                if (!inString) {
                  if (char === '{') {
                    braceCount++;
                  } else if (char === '}') {
                    braceCount--;
                    
                    // If we've closed all braces, we have a complete ingredient
                    if (braceCount === 0 && currentIngredient.trim()) {
                      currentIngredient += char;
                      completeIngredients.push(currentIngredient.trim());
                      currentIngredient = '';
                      
                      // Skip comma and whitespace
                      while (i + 1 < ingredientsContent.length && 
                             (ingredientsContent[i + 1] === ',' || 
                              ingredientsContent[i + 1] === ' ' || 
                              ingredientsContent[i + 1] === '\n' || 
                              ingredientsContent[i + 1] === '\t')) {
                        i++;
                      }
                      continue;
                    }
                  }
                }
                
                currentIngredient += char;
              }
              
              console.log(`LEGACY ENDPOINT - Found ${completeIngredients.length} complete ingredients`);
              
              if (completeIngredients.length > 0) {
                // Build a valid JSON with complete ingredients
                const validJson = `{
                  "ingredients": [
                    ${completeIngredients.join(',\n    ')}
                  ],
                  "total": {
                    "calories": 0,
                    "protein_g": 0,
                    "fat_g": 0,
                    "carbs_g": 0
                  }
                }`;
                
                console.log('LEGACY ENDPOINT - Attempting to parse repaired JSON...');
                const jsonResponse = JSON.parse(validJson);
                
                // Calculate totals from ingredients
                let totalCalories = 0, totalProtein = 0, totalFat = 0, totalCarbs = 0;
                
                jsonResponse.ingredients.forEach(ingredient => {
                  totalCalories += ingredient.calories || 0;
                  totalProtein += ingredient.protein_g || 0;
                  totalFat += ingredient.fat_g || 0;
                  totalCarbs += ingredient.carbs_g || 0;
                });
                
                jsonResponse.total = {
                  calories: totalCalories,
                  protein_g: totalProtein,
                  fat_g: totalFat,
                  carbs_g: totalCarbs
                };
                
                console.log('LEGACY ENDPOINT - JSON repair successful!');
                const result = processVisionResponse(jsonResponse);
                return res.json({
                  success: true,
                  data: result
                });
              }
            }
            
            // If ingredients parsing failed, try simpler extraction
            console.log('LEGACY ENDPOINT - Attempting simple ingredient extraction...');
            const simpleMatch = content.match(/"name":\s*"([^"]+)"/g);
            if (simpleMatch && simpleMatch.length > 0) {
              const simpleIngredients = simpleMatch.map((match, index) => {
                const name = match.match(/"name":\s*"([^"]+)"/)[1];
                return {
                  name: name,
                  weight_g: 100,
                  calories: 100,
                  protein_g: 10,
                  fat_g: 5,
                  carbs_g: 10,
                  vitamins: {},
                  minerals: {},
                  other: {}
                };
              });
              
              const fallbackResponse = {
                ingredients: simpleIngredients,
                total: {
                  calories: simpleIngredients.length * 100,
                  protein_g: simpleIngredients.length * 10,
                  fat_g: simpleIngredients.length * 5,
                  carbs_g: simpleIngredients.length * 10
                }
              };
              
              console.log(`LEGACY ENDPOINT - Simple extraction found ${simpleIngredients.length} ingredients`);
              const result = processVisionResponse(fallbackResponse);
              return res.json({
                success: true,
                data: result
              });
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
      return res.status(500).json({
        success: false,
        error: `API call error: ${error.message}`
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
