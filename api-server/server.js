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
1. **Multiple Ingredient Detection**: For complex meals, identify EACH separate ingredient/component
2. **Precise Values**: Provide exact decimal values (e.g., 23.7g, not 24g)
3. **Comprehensive Analysis**: Include all visible food components

INGREDIENT CATEGORIES TO DETECT:
- **Proteins**: meat, fish, eggs, dairy, legumes, nuts
- **Vegetables**: all visible vegetables, garnishes, herbs
- **Grains/Starches**: rice, bread, pasta, potatoes
- **Sauces/Condiments**: dressings, sauces, oils
- **Fruits**: any visible fruits or fruit components

MULTI-INGREDIENT DETECTION RULES:
1. **Scan systematically**: Look at all areas of the plate/image
2. **Identify layers**: Check for ingredients that might be layered or mixed
3. **Consider garnishes**: Include herbs, spices, small vegetables
4. **Separate components**: Treat each distinct food item as separate ingredient
5. **Minimum threshold**: Always try to identify at least 2-3 ingredients unless it's genuinely a single-ingredient meal

RESPONSE FORMAT (JSON ONLY):
Return a JSON object with meal_name and ingredients array. Each ingredient should have name, weight_g, calories, protein_g, fat_g, and carbs_g properties.

IMPORTANT:
- EVERY number MUST end with .0 even for whole numbers
- Always try to detect multiple ingredients when visible
- If only 1 ingredient detected, double-check the image for missed components`;

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
                  { type: "text", text: "This plate contains MULTIPLE different food items. I can see at least 3-5 separate ingredients including proteins, vegetables, and side dishes. Identify each one separately. Do NOT return just one ingredient - that is incorrect." },
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
              if (jsonResponse.ingredients.length === 1) {
                console.warn(`WARNING: Only 1 ingredient detected for job ${jobId}. This might indicate the image needs better analysis or the meal is genuinely simple.`);
                
                // FALLBACK: Try again with more aggressive prompt if only 1 ingredient detected
                console.log(`Attempting fallback analysis for job ${jobId} to detect more ingredients...`);
                
                // Try with less compressed image for fallback
                let fallbackImage = processedImage;
                try {
                  const parts = image.split(','); // Use original image
                  const mimeType = parts[0];
                  const base64Data = parts[1] || '';
                  
                  // Use 1MB for fallback instead of broken compression
                  const fallbackTargetSize = 1000000; // 1MB - much larger for fallback
                  if (image.length > fallbackTargetSize) {
                    console.log('Creating fallback compressed image...');
                    
                    // Use proper compression for fallback too
                    const compressionRatio = fallbackTargetSize / image.length;
                    
                    if (compressionRatio < 0.1) {
                      // Aggressive compression for very large images
                      const keepEveryN = Math.ceil(1 / compressionRatio);
                      let compressedData = '';
                      
                      for (let i = 0; i < base64Data.length; i += keepEveryN) {
                        compressedData += base64Data[i];
                      }
                      
                      fallbackImage = `${mimeType},${compressedData}`;
                      console.log(`Fallback aggressively compressed to ${fallbackImage.length} bytes`);
                    } else {
                      // Moderate compression with valid base64
                      const keepLength = Math.floor(base64Data.length * compressionRatio);
                      const validKeepLength = Math.floor(keepLength / 4) * 4;
                      
                      fallbackImage = `${mimeType},${base64Data.substring(0, validKeepLength)}`;
                      console.log(`Fallback compressed to ${fallbackImage.length} bytes`);
                    }
                  } else {
                    fallbackImage = image; // Use original if small enough
                    console.log(`Using original image for fallback: ${fallbackImage.length} bytes`);
                  }
                } catch (e) {
                  console.log('Failed to create fallback compressed image, using processed version');
                  fallbackImage = processedImage;
                }
                
                const aggressivePrompt = `CRITICAL: This image contains MULTIPLE food ingredients. You MUST identify ALL separate components.

Look at this image again and identify EVERY SINGLE ingredient, component, and food item visible:
- Scan the ENTIRE image systematically
- Look for vegetables, proteins, sides, garnishes, sauces
- Identify items that might be partially hidden or mixed
- Consider different textures and colors as separate ingredients
- Include small items like herbs, spices, condiments

You MUST return at least 2-3 ingredients unless this is genuinely a single food item (which is rare).

Return JSON format with meal_name and ingredients array. Each ingredient needs name, weight_g, calories, protein_g, fat_g, carbs_g properties.`;

                try {
                  const fallbackController = new AbortController();
                  const fallbackTimeoutId = setTimeout(() => fallbackController.abort(), 30000);
                  
                  const fallbackResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
                    signal: fallbackController.signal,
      body: JSON.stringify({
                      model: "gpt-4o",
                      temperature: 0.3,  // Slightly higher temperature for more creativity
                      response_format: { type: "json_object" },
        messages: [
          {
                          role: "system",
                          content: aggressivePrompt
          },
          {
                          role: "user",
            content: [
                            { type: "text", text: "This image has multiple ingredients. Identify ALL of them - look harder and find every component, vegetable, protein, and side dish visible." },
                            { type: "image_url", image_url: { url: fallbackImage } }
                          ]
                        }
                      ],
                      max_tokens: 1500
      })
    });

                  clearTimeout(fallbackTimeoutId);
                  
                  if (fallbackResponse.ok) {
                    const fallbackData = await fallbackResponse.json();
                    const fallbackContent = fallbackData.choices[0].message.content.trim();
                    
                    console.log('=== FALLBACK RESPONSE DEBUG ===');
                    console.log('Fallback raw content:', fallbackContent);
                    console.log('=== END FALLBACK DEBUG ===');
                    
                    try {
                      const fallbackJson = JSON.parse(fallbackContent);
                      console.log('Fallback parsed JSON:', JSON.stringify(fallbackJson, null, 2));
                      console.log('Fallback ingredients count:', fallbackJson.ingredients ? fallbackJson.ingredients.length : 0);
                      
                      if (fallbackJson.ingredients && fallbackJson.ingredients.length > jsonResponse.ingredients.length) {
                        console.log(`Fallback detected ${fallbackJson.ingredients.length} ingredients (improved from ${jsonResponse.ingredients.length})`);
                        // Use the better result
                        finalResponse = processVisionResponse(fallbackJson);
      } else {
                        console.log(`Fallback didn't improve results, using original`);
                        finalResponse = processVisionResponse(jsonResponse);
                      }
                    } catch (fallbackParseError) {
                      console.log(`Fallback JSON parse failed: ${fallbackParseError.message}, using original result`);
                      finalResponse = processVisionResponse(jsonResponse);
                    }
          } else {
                    console.log(`Fallback API call failed, using original result`);
                    finalResponse = processVisionResponse(jsonResponse);
                  }
                } catch (fallbackError) {
                  console.log(`Fallback attempt failed: ${fallbackError.message}, using original result`);
                  finalResponse = processVisionResponse(jsonResponse);
        }
      } else {
                // Multiple ingredients detected, use the result
                finalResponse = processVisionResponse(jsonResponse);
              }
              
              // Convert OpenAI's response to our expected format
              // finalResponse = processVisionResponse(jsonResponse);
              
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
            let repairedContent = content;
            
            // Remove any markdown code blocks
            repairedContent = repairedContent.replace(/```json\s*/g, '').replace(/```\s*/g, '');
            
            // Remove any leading/trailing whitespace
            repairedContent = repairedContent.trim();
            
            // Try to parse the repaired content
            if (repairedContent !== content) {
              try {
                console.log('Attempting to parse repaired JSON...');
                const repairedJson = JSON.parse(repairedContent);
                console.log('Repaired JSON parsed successfully!');
                
                if (repairedJson.ingredients && repairedJson.ingredients.length > 0) {
                  finalResponse = processVisionResponse(repairedJson);
                  
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
                console.log('JSON repair attempt failed:', repairError.message);
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
  
  // Map ingredients to our format with comprehensive nutrition data
  const mappedIngredients = ingredients.map(item => {
    const ingredient = {
      name: item.name,
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
  
  // Create a meal name from the ingredients
  const foodNames = mappedIngredients.map(item => item.name);
  const mealName = foodNames.length > 0 ? foodNames.join(' with ') : "Analyzed Meal";
  
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

CRITICAL: ALWAYS DETECT MULTIPLE INGREDIENTS
- Look carefully at EVERY part of the plate/image
- Identify EACH separate food component (proteins, vegetables, sides, garnishes)
- For complex meals, you should typically find 3-6 distinct ingredients
- Do NOT combine multiple foods into one ingredient
- Treat each distinct food item as a separate ingredient

EXAMPLES OF WHAT TO DETECT SEPARATELY:
- Meat items: chicken, beef, sausage, fish (each type separately)
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