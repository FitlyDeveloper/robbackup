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
app.use(express.json({ limit: '10mb' }));

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
    
    // Extract base64 data for vision API - needs special handling
    let processedImage = image;
    if (image.startsWith('data:')) {
      console.log(`Converting image from data URL to proper format for Vision API`);
    } else {
      console.log(`Image doesn't appear to be in data URL format, will try to process as-is`);
    }
    
    // Update progress
    await updateJobStatus(jobId, {
      progress: 30,
      message: 'Image processed, calling OpenAI Vision API...'
    });

    // Simplified system prompt to avoid JSON parsing errors
    const systemPrompt = `You are a food analyzer. Analyze the image and return ONLY basic nutrition info.
Return valid JSON with this EXACT structure (no extra fields):
{
  "ingredients": [
    { 
      "name": "ingredient name", 
      "weight_g": 100, 
      "calories": 250,
      "protein_g": 15, 
      "fat_g": 10, 
      "carbs_g": 30
    }
  ],
  "total": { 
    "calories": 250,
    "protein_g": 15,
    "fat_g": 10,
    "carbs_g": 30
  }
}

Keep it simple. Only identify 1-3 main ingredients. Use realistic nutrition values.`;

    let finalResponse = null;
    
    if (process.env.OPENAI_API_KEY) {
      try {
        // Use AbortController for timeout
        const controller = new AbortController();
        const timeoutId = setTimeout(() => {
          console.log(`OpenAI API call timeout for job ${jobId}`);
          controller.abort();
        }, 90000); // 90 second timeout for large uncompressed images
        
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
            temperature: 0.0,
            response_format: { type: "json_object" },
        messages: [
          {
                role: "system",
                content: systemPrompt
          },
          {
                role: "user",
            content: [
                  { type: "text", text: "Analyze this meal image and return JSON exactly as specified." },
                  { type: "image_url", image_url: { url: processedImage } }
                ]
              }
            ],
            max_tokens: 300  // Reduced since we're asking for simpler data
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
            
            // Check if we have valid ingredients
            if (jsonResponse.ingredients && jsonResponse.ingredients.length > 0) {
              // Convert OpenAI's response to our expected format
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
            console.error(`Error parsing API response: ${parseError}`);
            
            // Try to repair truncated JSON
            let repairedContent = content;
            
            // Common truncation fixes
            if (!content.endsWith('}') && !content.endsWith(']')) {
              // Try to close the JSON properly
              if (content.includes('"ingredients":[')) {
                // Find the last complete ingredient and close the array/object
                const lastBrace = content.lastIndexOf('}');
                if (lastBrace > 0) {
                  repairedContent = content.substring(0, lastBrace + 1) + ']}';
                }
              }
            }
            
            // Try parsing the repaired content
            if (repairedContent !== content) {
              try {
                console.log('Attempting to repair truncated JSON...');
                const repairedResponse = JSON.parse(repairedContent);
                if (repairedResponse.ingredients && repairedResponse.ingredients.length > 0) {
                  console.log('Successfully repaired truncated JSON');
                  finalResponse = processVisionResponse(repairedResponse);
                  
                  await updateJobStatus(jobId, {
                    status: 'completed',
                    progress: 100,
                    message: 'Analysis complete (repaired)',
                    completedAt: Date.now(),
                    result: finalResponse
                  });
                  
                  console.log(`Job ${jobId} marked completed (repaired JSON) at ${new Date().toISOString()}`);
                  return; // Exit early on success
                }
              } catch (repairError) {
                console.log('JSON repair attempt failed');
              }
            }
            
            // Save the raw response for debugging without logging to console
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
  
  // Map ingredients to our format
  const mappedIngredients = ingredients.map(item => ({
    name: item.name,
    weight_g: item.weight_g || 100.0,
    calories: item.calories || 0,
    protein_g: item.protein_g || 0,
    fat_g: item.fat_g || 0,
    carbs_g: item.carbs_g || 0
  }));
  
  // Create a meal name from the ingredients
  const foodNames = mappedIngredients.map(item => item.name);
  const mealName = foodNames.length > 0 ? foodNames.join(' with ') : "Analyzed Meal";
  
  // Use the actual nutrition data from OpenAI if available, otherwise generate fallback
  const ingredientNutrients = ingredients.map(ingredient => {
    return {
      name: ingredient.name,
      protein: ingredient.protein_g || 0,
      fat: ingredient.fat_g || 0,
      carbs: ingredient.carbs_g || 0,
      vitamins: ingredient.vitamins || generateNutritionData('vitamins', ingredient),
      minerals: ingredient.minerals || generateNutritionData('minerals', ingredient),
      other: ingredient.other || generateNutritionData('other', ingredient)
    };
  });
  
  // Return structured response - use the actual totals from OpenAI if available
  return {
    meal_name: mealName,
    ingredients: mappedIngredients,
    ingredient_nutrients: ingredientNutrients,
    health_score: calculateHealthScore(mappedIngredients),
    vitamins: total?.vitamins || generateNutritionData('vitamins'),
    minerals: total?.minerals || generateNutritionData('minerals'),
    other: total?.other || generateNutritionData('other')
  };
}

// Generate nutritional data based on category
function generateNutritionData(category, ingredient) {
  // Base multiplier based on ingredient weight (default 100g)
  const weight = ingredient?.weight_g || 100;
  const multiplier = weight / 100;
  
  // Generate realistic values based on ingredient name
  const ingredientName = ingredient?.name?.toLowerCase() || '';
  
  if (category === 'vitamins') {
    // Base vitamin values (per 100g) - adjust based on ingredient type
    let baseValues = {
      vitamin_a: 50,    // mcg
      vitamin_c: 5,     // mg  
      vitamin_d: 0.5,   // mcg
      vitamin_e: 1,     // mg
      vitamin_k: 5,     // mcg
      vitamin_b1: 0.1,  // mg
      vitamin_b2: 0.1,  // mg
      vitamin_b3: 1,    // mg
      vitamin_b5: 0.5,  // mg
      vitamin_b6: 0.1,  // mg
      vitamin_b7: 2,    // mcg
      vitamin_b9: 10,   // mcg
      vitamin_b12: 0.1  // mcg
    };
    
    // Adjust based on ingredient type
    if (ingredientName.includes('fruit') || ingredientName.includes('orange') || ingredientName.includes('berry')) {
      baseValues.vitamin_c *= 10; // Fruits high in vitamin C
      baseValues.vitamin_a *= 2;
    } else if (ingredientName.includes('meat') || ingredientName.includes('chicken') || ingredientName.includes('beef')) {
      baseValues.vitamin_b12 *= 20; // Meat high in B12
      baseValues.vitamin_b3 *= 5;
    } else if (ingredientName.includes('vegetable') || ingredientName.includes('green')) {
      baseValues.vitamin_k *= 10; // Greens high in vitamin K
      baseValues.vitamin_a *= 5;
    }
    
    // Apply weight multiplier and round to reasonable precision
    Object.keys(baseValues).forEach(vitamin => {
      baseValues[vitamin] = Math.round(baseValues[vitamin] * multiplier * 10) / 10;
    });
    
    return baseValues;
  } else if (category === 'minerals') {
    let baseValues = {
      calcium: 50,      // mg
      chloride: 10,     // mg
      chromium: 1,      // mcg
      copper: 100,      // mcg
      fluoride: 0.1,    // mg
      iodine: 5,        // mcg
      iron: 2,          // mg
      magnesium: 25,    // mg
      manganese: 0.5,   // mg
      molybdenum: 5,    // mcg
      phosphorus: 50,   // mg
      potassium: 200,   // mg
      selenium: 5,      // mcg
      sodium: 100,      // mg
      zinc: 1           // mg
    };
    
    // Adjust based on ingredient type
    if (ingredientName.includes('dairy') || ingredientName.includes('milk') || ingredientName.includes('cheese')) {
      baseValues.calcium *= 10; // Dairy high in calcium
      baseValues.phosphorus *= 3;
    } else if (ingredientName.includes('meat') || ingredientName.includes('red')) {
      baseValues.iron *= 5; // Red meat high in iron
      baseValues.zinc *= 3;
    } else if (ingredientName.includes('banana') || ingredientName.includes('potato')) {
      baseValues.potassium *= 5; // High potassium foods
    }
    
    // Apply weight multiplier and round
    Object.keys(baseValues).forEach(mineral => {
      baseValues[mineral] = Math.round(baseValues[mineral] * multiplier * 10) / 10;
    });
    
    return baseValues;
        } else {
    let baseValues = {
      fiber: 2,           // g
      sugar: 5,           // g
      cholesterol: 10,    // mg
      saturated_fats: 1,  // g
      omega_3: 0.1,       // mg
      omega_6: 0.5        // g
    };
    
    // Adjust based on ingredient type
    if (ingredientName.includes('fruit')) {
      baseValues.sugar *= 3; // Fruits higher in sugar
      baseValues.fiber *= 2;
      baseValues.cholesterol = 0; // Fruits have no cholesterol
    } else if (ingredientName.includes('vegetable')) {
      baseValues.fiber *= 3; // Vegetables high in fiber
      baseValues.sugar *= 0.5; // Lower sugar
      baseValues.cholesterol = 0;
    } else if (ingredientName.includes('meat')) {
      baseValues.cholesterol *= 5; // Meat has cholesterol
      baseValues.saturated_fats *= 3;
      baseValues.fiber = 0; // Meat has no fiber
    }
    
    // Apply weight multiplier and round
    Object.keys(baseValues).forEach(nutrient => {
      baseValues[nutrient] = Math.round(baseValues[nutrient] * multiplier * 10) / 10;
    });
    
    return baseValues;
  }
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
      const systemPrompt = `You are a food analyzer. Analyze the image and return ONLY basic nutrition info.
Return valid JSON with this EXACT structure (no extra fields):
{
  "ingredients": [
    { 
      "name": "ingredient name", 
      "weight_g": 100, 
      "calories": 250,
      "protein_g": 15, 
      "fat_g": 10, 
      "carbs_g": 30
    }
  ],
  "total": { 
    "calories": 250,
    "protein_g": 15,
    "fat_g": 10,
    "carbs_g": 30
  }
}

Keep it simple. Only identify 1-3 main ingredients. Use realistic nutrition values.`;

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
          temperature: 0.0,
          response_format: { type: "json_object" },
          messages: [
            {
              role: "system",
              content: systemPrompt
            },
            {
              role: "user",
              content: [
                { type: "text", text: "Analyze this meal image and return JSON exactly as specified." },
                { type: "image_url", image_url: { url: processedImage } }
              ]
            }
          ],
          max_tokens: 300
        })
      });
      
      if (response.ok) {
        const responseData = await response.json();
        const content = responseData.choices[0].message.content.trim();
        
        try {
          // Parse JSON response first before logging
          const jsonResponse = JSON.parse(content);
          console.log('Legacy endpoint API response successfully parsed');
          
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
          console.error(`Error parsing API response: ${parseError}`);
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