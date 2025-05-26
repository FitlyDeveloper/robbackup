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

    // Precise prompt to ensure accurate recognition without hallucinations
    const systemPrompt = `You are a precise food-image analyzer.  
- Only identify items you can visually confirm in the image.  
- Do NOT guess or hallucinate extra foods.  
- If uncertain of an ingredient, label it "unknown".
- Use ONLY the following units for all nutrients: mcg (micrograms), mg (milligrams), and g (grams). 
- DO NOT use IU (International Units) for any nutrient values.
- Return strictly valid JSON with exactly these keys:
{
  "ingredients": [
    { 
      "name": String, 
      "weight_g": Number, 
      "calories": Number,
      "protein_g": Number, 
      "fat_g": Number, 
      "carbs_g": Number,
      "vitamins": {
        "vitamin_a": Number, // in mcg (NOT IU)
        "vitamin_c": Number, // in mg
        "vitamin_d": Number, // in mcg (NOT IU)
        "vitamin_e": Number, // in mg (NOT IU)
        "vitamin_k": Number, // in mcg
        "vitamin_b1": Number, // in mg
        "vitamin_b2": Number, // in mg
        "vitamin_b3": Number, // in mg
        "vitamin_b5": Number, // in mg
        "vitamin_b6": Number, // in mg
        "vitamin_b7": Number, // in mcg
        "vitamin_b9": Number, // in mcg
        "vitamin_b12": Number // in mcg
      },
      "minerals": {
        "calcium": Number, // in mg
        "chloride": Number, // in mg
        "chromium": Number, // in mcg
        "copper": Number, // in mcg
        "fluoride": Number, // in mg
        "iodine": Number, // in mcg
        "iron": Number, // in mg
        "magnesium": Number, // in mg
        "manganese": Number, // in mg
        "molybdenum": Number, // in mcg
        "phosphorus": Number, // in mg
        "potassium": Number, // in mg
        "selenium": Number, // in mcg
        "sodium": Number, // in mg
        "zinc": Number // in mg
      },
      "other": {
        "fiber": Number, // in g
        "sugar": Number, // in g
        "cholesterol": Number, // in mg
        "saturated_fats": Number, // in g
        "omega_3": Number, // in mg
        "omega_6": Number // in g
      }
    }
  ],
  "total": { 
    "calories": Number,
    "protein_g": Number,
    "fat_g": Number,
    "carbs_g": Number,
    "vitamins": { /* same as above */ },
    "minerals": { /* same as above */ },
    "other": { /* same as above */ }
  }
}`;

    let finalResponse = null;
    
    if (process.env.OPENAI_API_KEY) {
      try {
        // Use AbortController for timeout
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 25000); // 25 second timeout
        
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
            max_tokens: 1000
          })
        });
        
        clearTimeout(timeoutId);
        
        if (response.ok) {
          const responseData = await response.json();
          const content = responseData.choices[0].message.content.trim();
          console.log('OpenAI API response:', content);
          
          try {
            // Parse JSON response
            const jsonResponse = JSON.parse(content);
            console.log('Parsed API response:', JSON.stringify(jsonResponse, null, 2));
            
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
            } else {
              // No ingredients found - return error
              console.log('No ingredients detected by API');
              await updateJobStatus(jobId, {
                status: 'failed',
                progress: 100,
                completedAt: Date.now(),
                error: 'No food ingredients could be detected in the image'
              });
            }
          } catch (parseError) {
            console.error('Error parsing API response:', parseError);
            await updateJobStatus(jobId, {
              status: 'failed',
              progress: 100,
              completedAt: Date.now(),
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
        }
      } catch (error) {
        console.error(`API call failed for job ${jobId}:`, error);
        await updateJobStatus(jobId, {
          status: 'failed',
          progress: 100,
          completedAt: Date.now(),
          error: `API call error: ${error.message}`
        });
      }
    } else {
      console.log('No OpenAI API key available');
      await updateJobStatus(jobId, {
        status: 'failed',
        progress: 100,
        completedAt: Date.now(),
        error: 'API key not configured'
      });
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
  
  // Generate ingredient nutrients for each ingredient - use the actual data if available
  const ingredientNutrients = ingredients.map(ingredient => {
    return {
      name: ingredient.name,
      protein: ingredient.protein_g || 0,
      fat: ingredient.fat_g || 0,
      carbs: ingredient.carbs_g || 0,
      vitamins: ingredient.vitamins || generateNutritionData('vitamins'),
      minerals: ingredient.minerals || generateNutritionData('minerals'),
      other: ingredient.other || generateNutritionData('other')
    };
  });
  
  // Return structured response - use the actual totals if available
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
function generateNutritionData(category, nutrition) {
  const baseValue = nutrition ? 1 : 1;
  
  if (category === 'vitamins') {
    return {
      vitamin_a: 0,
      vitamin_c: 0,
      vitamin_d: 0,
      vitamin_e: 0,
      vitamin_k: 0,
      vitamin_b1: 0,
      vitamin_b2: 0,
      vitamin_b3: 0,
      vitamin_b5: 0,
      vitamin_b6: 0,
      vitamin_b7: 0,
      vitamin_b9: 0,
      vitamin_b12: 0
    };
  } else if (category === 'minerals') {
    return {
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
      zinc: 0
    };
  } else {
    return {
      fiber: 0,
      sugar: 0,
      cholesterol: 0,
      saturated_fats: 0,
      omega_3: 0,
      omega_6: 0
    };
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
          status: jobData.status,
          progress: 100,
          createdAt: jobData.createdAt,
          completedAt: jobData.completedAt || Date.now(),
          data: jobData.result
        });
      } else {
        return res.status(500).json({
          success: false,
          status: 'error',
          error: 'Analysis failed - no results available'
        });
      }
    } else if (jobData.status === 'failed') {
      // Return error status
      return res.status(422).json({
        success: false,
        status: 'failed',
        error: jobData.error || 'Unknown error during processing',
        progress: 100,
        createdAt: jobData.createdAt,
        completedAt: jobData.completedAt || Date.now()
      });
    }

    // For non-completed jobs, return status info
    return res.json({
      success: true,
      status: jobData.status,
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
      const systemPrompt = `You are a precise food-image analyzer.  
- Only identify items you can visually confirm in the image.  
- Do NOT guess or hallucinate extra foods.  
- If uncertain of an ingredient, label it "unknown".
- Use ONLY the following units for all nutrients: mcg (micrograms), mg (milligrams), and g (grams). 
- DO NOT use IU (International Units) for any nutrient values.
- Return strictly valid JSON with exactly these keys:
{
  "ingredients": [
    { 
      "name": String, 
      "weight_g": Number, 
      "calories": Number,
      "protein_g": Number, 
      "fat_g": Number, 
      "carbs_g": Number,
      "vitamins": {
        "vitamin_a": Number, // in mcg (NOT IU)
        "vitamin_c": Number, // in mg
        "vitamin_d": Number, // in mcg (NOT IU)
        "vitamin_e": Number, // in mg (NOT IU)
        "vitamin_k": Number, // in mcg
        "vitamin_b1": Number, // in mg
        "vitamin_b2": Number, // in mg
        "vitamin_b3": Number, // in mg
        "vitamin_b5": Number, // in mg
        "vitamin_b6": Number, // in mg
        "vitamin_b7": Number, // in mcg
        "vitamin_b9": Number, // in mcg
        "vitamin_b12": Number // in mcg
      },
      "minerals": {
        "calcium": Number, // in mg
        "chloride": Number, // in mg
        "chromium": Number, // in mcg
        "copper": Number, // in mcg
        "fluoride": Number, // in mg
        "iodine": Number, // in mcg
        "iron": Number, // in mg
        "magnesium": Number, // in mg
        "manganese": Number, // in mg
        "molybdenum": Number, // in mcg
        "phosphorus": Number, // in mg
        "potassium": Number, // in mg
        "selenium": Number, // in mcg
        "sodium": Number, // in mg
        "zinc": Number // in mg
      },
      "other": {
        "fiber": Number, // in g
        "sugar": Number, // in g
        "cholesterol": Number, // in mg
        "saturated_fats": Number, // in g
        "omega_3": Number, // in mg
        "omega_6": Number // in g
      }
    }
  ],
  "total": { 
    "calories": Number,
    "protein_g": Number,
    "fat_g": Number,
    "carbs_g": Number,
    "vitamins": { /* same as above */ },
    "minerals": { /* same as above */ },
    "other": { /* same as above */ }
  }
}`;

      // Make OpenAI API call
      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
        },
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
          max_tokens: 1000
        })
      });
      
      if (response.ok) {
        const responseData = await response.json();
        const content = responseData.choices[0].message.content.trim();
        console.log('Legacy endpoint API response:', content);
        
        try {
          // Parse JSON response
          const jsonResponse = JSON.parse(content);
          console.log('Parsed API response:', JSON.stringify(jsonResponse, null, 2));
          
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
          console.error('Error parsing API response:', parseError);
          return res.status(500).json({
            success: false,
            error: 'Invalid response format from image analysis'
          });
        }
      } else {
        const errorData = await response.text();
        console.error('OpenAI API error:', response.status, errorData);
        return res.status(500).json({
          success: false,
          error: `Image analysis failed: ${response.status}`
        });
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