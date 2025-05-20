require('dotenv').config();
const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const fetch = require('node-fetch');

// Create Express app
const app = express();
const PORT = process.env.PORT || 3000;

// Debug startup
console.log('Starting server...');
console.log('Node environment:', process.env.NODE_ENV);
console.log('Current directory:', process.cwd());
console.log('OpenAI API Key present:', process.env.OPENAI_API_KEY ? 'Yes' : 'No');

// Helper function to robustly parse JSON content
function robustJsonParse(content) {
  try {
    // Attempt 1: Direct parsing
    const directParseResult = JSON.parse(content);
    console.log('Successfully parsed JSON response directly.');
    return directParseResult;
  } catch (e1) {
    console.log('Direct JSON parsing failed. Attempting to extract JSON from text. Error:', e1.message);
    
    let jsonString = "";
    // Try to match ```json ... ```
    const codeBlockMatch = content.match(/```json\n([\s\S]*?)\n```/);
    if (codeBlockMatch && codeBlockMatch[1]) {
      jsonString = codeBlockMatch[1].trim();
      console.log('Extracted JSON from ```json block.');
    } else {
      // If no ```json block, try to find the first occurrence of { ... }
      const objectMatch = content.match(/(\{[\s\S]*\})/);
      if (objectMatch && objectMatch[1]) {
        jsonString = objectMatch[1].trim();
        console.log('Extracted JSON using general object match.');
      }
    }

    if (jsonString) {
      try {
        // Attempt 2: Parse extracted/cleaned JSON
        const extractedParseResult = JSON.parse(jsonString);
        console.log('Successfully parsed extracted JSON.');
        return extractedParseResult;
      } catch (e2) {
        console.error('Failed to parse extracted JSON content. Error:', e2.message);
        const snippet = jsonString.length > 500 ? jsonString.substring(0, 500) + '...' : jsonString;
        console.error('Problematic JSON string snippet after extraction attempt:', snippet);
        throw new Error(`OpenAI response could not be parsed as JSON even after attempting extraction. Details: ${e2.message}. Original direct parse error: ${e1.message}`);
      }
    } else {
      const contentSnippet = content.length > 200 ? content.substring(0, 200) + "..." : content;
      console.warn('No JSON pattern found for extraction after direct parsing failed. Content snippet:', contentSnippet);
      throw new Error(`OpenAI response is not valid JSON and no JSON pattern could be extracted. Direct parse error: ${e1.message}`);
    }
  }
}

// Set trust proxy to fix the X-Forwarded-For warning
app.set('trust proxy', 1);

// Configure rate limiting
const limiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: process.env.RATE_LIMIT || 30, // Limit each IP to 30 requests per minute
  standardHeaders: true, // Return rate limit info in the `RateLimit-*` headers
  legacyHeaders: false, // Disable the `X-RateLimit-*` headers
  message: {
    status: 429,
    message: 'Too many requests, please try again later.'
  }
});

// Get allowed origins from environment or use default
const allowedOrigins = process.env.ALLOWED_ORIGINS 
  ? process.env.ALLOWED_ORIGINS.split(',') 
  : ['http://localhost:3000'];

// Configure CORS
app.use(cors({
  origin: '*',  // Allow all origins
  methods: ['POST', 'GET', 'OPTIONS'],  // Allow necessary methods
  credentials: true
}));

// Body parser middleware
app.use(express.json({ limit: '10mb' }));

// Middleware to check for OpenAI API key
const checkApiKey = (req, res, next) => {
  if (!process.env.OPENAI_API_KEY) {
    console.error('OpenAI API key not configured');
    return res.status(500).json({
      success: false,
      error: 'Server configuration error: OpenAI API key not set'
    });
  }
  console.log('OpenAI API key verified');
  next();
};

// Define routes
app.get('/', (req, res) => {
  console.log('Health check endpoint called');
  res.json({
    message: 'Food Analyzer API Server',
    status: 'operational'
  });
});

// OpenAI proxy endpoint for food analysis
app.post('/api/analyze-food', limiter, checkApiKey, async (req, res) => {
  try {
    console.log('Analyze food endpoint called');
    const { image } = req.body;

    if (!image) {
      console.error('No image provided in request');
      return res.status(400).json({
        success: false,
        error: 'Image data is required'
      });
    }

    // Debug logging
    console.log('Received image data, length:', image.length);
    console.log('Image data starts with:', image.substring(0, 50));

    // Call OpenAI API
    console.log('Calling OpenAI API...');
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
      body: JSON.stringify({
        model: 'gpt-4o',
        temperature: 0.2,
        messages: [
          {
            role: 'system',
            content: `YOUR PRIMARY TASK: Analyze the provided food image and return a detailed per-ingredient nutritional breakdown in JSON format.

RESPONSE MUST FOLLOW THESE RULES:
1.  meal_name: Specific, descriptive name for the entire meal (e.g., "Grilled Salmon with Asparagus"). NO generic names.
2.  ingredients: Array of strings. Each string details one ingredient: "Ingredient Name (estimated weight) estimated_calories_for_ingredient_kcal" (e.g., "Salmon Fillet (150g) 300kcal"). List EVERY visible ingredient.
3.  ingredient_nutrients: Array of objects. THIS IS THE MOST CRITICAL PART. Each object corresponds to an item in the 'ingredients' array.
    EACH OBJECT IN ingredient_nutrients MUST CONTAIN (with realistic, non-zero estimates unless truly absent for that ingredient - DO NOT default to zero for likely present nutrients like protein in meat or carbs in fruit):
        - ingredient_name_ref: String, verbatim copy of the ingredient string from the "ingredients" array for reference.
        - calories: Number (kcal)
        - protein: Number (g)
        - fat: Number (g)
        - carbs: Number (g)
        - fiber: Number (g)
        - sugar: Number (g)
        - cholesterol: Number (mg)
        - saturated_fats: Number (g)
        - omega_3: Number (mg)
        - omega_6: Number (g)
        - vitamins: Object containing ALL vitamins listed below with their non-zero (unless absent) values and units for THIS INGREDIENT.
            (A (IU), C (mg), D (IU), E (mg), K (mcg), B1 (mg), B2 (mg), B3 (mg), B5 (mg), B6 (mg), B7 (mcg), B9 (mcg), B12 (mcg))
        - minerals: Object containing ALL minerals listed below with their non-zero (unless absent) values and units for THIS INGREDIENT.
            (calcium (mg), iron (mg), magnesium (mg), phosphorus (mg), potassium (mg), sodium (mg), zinc (mg), copper (mg), manganese (mg), selenium (mcg), iodine (mcg), chromium (mcg), molybdenum (mcg), fluoride (mg), chloride (mg))
4.  total_calories, total_protein, total_fat, total_carbs, total_fiber, total_sugar, total_cholesterol, total_saturated_fats, total_omega_3, total_omega_6: Numbers, representing the sum for the entire meal, derived by you from the per-ingredient data you provide.
5.  total_vitamins, total_minerals: Objects, containing the sum of each vitamin/mineral for the entire meal, derived from your per-ingredient data.
6.  health_score: String (e.g., "7/10").

CRITICAL EXAMPLE for one item in ingredient_nutrients (You MUST provide this level of detail for ALL ingredients):
{\n  "ingredient_name_ref": "Chicken Breast (150g) 240kcal",\n  "calories": 240,\n  "protein": 45.0,\n  "fat": 6.0,\n  "carbs": 0.0,\n  "fiber": 0.0,\n  "sugar": 0.0,\n  "cholesterol": 120,\n  "saturated_fats": 1.5,\n  "omega_3": 50,\n  "omega_6": 0.5,\n  "vitamins": { "vitamin_a": 10, "vitamin_c": 0, "vitamin_d": 5, "vitamin_e": 0.5, "vitamin_k": 2, "vitamin_b1": 0.1, "vitamin_b2": 0.3, "vitamin_b3": 12.0, "vitamin_b5": 1.0, "vitamin_b6": 0.9, "vitamin_b7": 3, "vitamin_b9": 10, "vitamin_b12": 1.0 },\n  "minerals": { "calcium": 15, "iron": 1.0, "magnesium": 30, "phosphorus": 300, "potassium": 400, "sodium": 70, "zinc": 1.0, "copper": 0.1, "manganese": 0.05, "selenium": 40, "iodine": 2, "chromium": 5, "molybdenum": 10, "fluoride": 0.1, "chloride": 80 }\n}\n\nIt is crucial to provide detailed, non-zero (where appropriate) per-ingredient breakdowns in ingredient_nutrients as specified. Accurate JSON output is essential.\`
          },
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: "RAW JSON ONLY. Analyze image. Critical: Provide FULL, DETAILED, NON-ZERO (unless truly absent) per-ingredient nutrients for macros, vitamins, and minerals in the 'ingredient_nutrients' array as per system prompt example. Sum these for totals. Incomplete per-ingredient data is a failure."
              },
              {
                type: 'image_url',
                image_url: { url: image }
              }
            ]
          }
        ],
        max_tokens: 4095, 
        response_format: { type: 'json_object' }
      })
    });

    if (!response.ok) {
      const errorData = await response.text(); // Get text for more detailed error
      console.error('OpenAI API request failed with status:', response.status);
      console.error('OpenAI API error response data:', errorData);
      return res.status(response.status).json({
        success: false,
        error: `OpenAI API error: ${response.status}`,
        details: errorData
      });
    }

    console.log('OpenAI API request successful. Processing response...');
    const data = await response.json(); // This can also throw if response is not valid JSON despite response.ok
    
    // Log the entire raw data object from OpenAI for debugging
    console.log('Full OpenAI API data object received:', JSON.stringify(data, null, 2));

    // Enhanced validation of the OpenAI response structure
    if (!data || !data.choices || !Array.isArray(data.choices) || data.choices.length === 0 || 
        !data.choices[0].message || typeof data.choices[0].message.content !== 'string') {
      console.error('Invalid or unexpected response structure from OpenAI. Full data logged above.');
      if (data && data.choices && data.choices[0] && data.choices[0].message) {
        console.error('Problematic message object from OpenAI:', JSON.stringify(data.choices[0].message, null, 2));
      }
      return res.status(500).json({
        success: false,
        error: 'Invalid or unexpected response structure from OpenAI after successful API call.'
      });
    }

    const content = data.choices[0].message.content;
    console.log('Extracted content for parsing (first 300 chars):', content.substring(0, 300) + (content.length > 300 ? '...' : ''));
    
    try {
      const parsedData = robustJsonParse(content);
      
      // Validate crucial structure AFTER successful parsing
      if (!parsedData.meal_name || !parsedData.ingredients || !parsedData.ingredient_nutrients || 
          !Array.isArray(parsedData.ingredients) || !Array.isArray(parsedData.ingredient_nutrients) || 
          parsedData.ingredient_nutrients.length === 0) {
        console.error('Missing or invalid crucial fields (meal_name, ingredients, ingredient_nutrients) in parsed data from OpenAI');
        return res.status(500).json({
          success: false,
          error: 'Invalid response from OpenAI: Missing or malformed crucial fields after parsing.'
        });
      }

      const transformedData = transformToRequiredFormat(parsedData);
      
      const detailedResponse = {
              success: true,
        data: transformedData,
        meal_details: {
          name: transformedData.meal_name,
          total_calories: transformedData.calories,
          ingredients: transformedData.ingredients,
          ingredient_breakdown: transformedData.ingredient_nutrients.map((ingredient, index) => ({
            name: transformedData.ingredients[index] || 'Unknown Ingredient',
            calories: ingredient.calories,
            macros: { protein: ingredient.protein, fat: ingredient.fat, carbs: ingredient.carbs },
            vitamins: ingredient.vitamins,
            minerals: ingredient.minerals,
            other: ingredient.other
          }))
        }
      };

      return res.json(detailedResponse);
    } catch (error) {
      console.error('Error processing OpenAI response, transforming data, or validating structure:', error);
      return res.status(500).json({
        success: false,
        error: 'Error processing nutrition data from OpenAI.',
        details: error.message
      });
    }
  } catch (error) {
    console.error('Server error:', error);
    return res.status(500).json({
      success: false,
      error: 'Server error processing request'
    });
  }
});

// Helper function to transform data to our required format
function transformToRequiredFormat(data) {
  // If we don't have proper data, return error instead of defaults
  if (!data.meal_name || !data.ingredients || !data.ingredient_nutrients || data.ingredients.length === 0) {
    throw new Error('Invalid or missing data: Required fields meal_name, ingredients, and ingredient_nutrients must be provided');
  }

  // Transform ingredient data while preserving all specific nutrients
    const transformedData = {
    meal_name: data.meal_name,
    ingredients: data.ingredients,
    ingredient_nutrients: data.ingredient_nutrients.map(ingredient => ({
      ...ingredient,
      // Ensure each ingredient has its specific nutrients
      vitamins: ingredient.vitamins || {},
      minerals: ingredient.minerals || {},
      other: ingredient.other || {}
    })),
    // Calculate total values by summing up from ingredients
    calories: data.ingredient_nutrients.reduce((sum, ing) => sum + (ing.calories || 0), 0),
    protein: data.ingredient_nutrients.reduce((sum, ing) => sum + (ing.protein || 0), 0),
    fat: data.ingredient_nutrients.reduce((sum, ing) => sum + (ing.fat || 0), 0),
    carbs: data.ingredient_nutrients.reduce((sum, ing) => sum + (ing.carbs || 0), 0),
    vitamins: {
      vitamin_a: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.vitamins?.vitamin_a || 0)), 0),
      vitamin_c: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.vitamins?.vitamin_c || 0)), 0),
      vitamin_d: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.vitamins?.vitamin_d || 0)), 0),
      vitamin_e: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.vitamins?.vitamin_e || 0)), 0),
      vitamin_k: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.vitamins?.vitamin_k || 0)), 0),
      vitamin_b1: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.vitamins?.vitamin_b1 || 0)), 0),
      vitamin_b2: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.vitamins?.vitamin_b2 || 0)), 0),
      vitamin_b3: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.vitamins?.vitamin_b3 || 0)), 0),
      vitamin_b5: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.vitamins?.vitamin_b5 || 0)), 0),
      vitamin_b6: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.vitamins?.vitamin_b6 || 0)), 0),
      vitamin_b7: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.vitamins?.vitamin_b7 || 0)), 0),
      vitamin_b9: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.vitamins?.vitamin_b9 || 0)), 0),
      vitamin_b12: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.vitamins?.vitamin_b12 || 0)), 0)
    },
    minerals: {
      calcium: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.calcium || 0)), 0),
      chloride: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.chloride || 0)), 0),
      chromium: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.chromium || 0)), 0),
      copper: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.copper || 0)), 0),
      fluoride: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.fluoride || 0)), 0),
      iodine: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.iodine || 0)), 0),
      iron: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.iron || 0)), 0),
      magnesium: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.magnesium || 0)), 0),
      manganese: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.manganese || 0)), 0),
      molybdenum: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.molybdenum || 0)), 0),
      phosphorus: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.phosphorus || 0)), 0),
      potassium: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.potassium || 0)), 0),
      selenium: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.selenium || 0)), 0),
      sodium: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.sodium || 0)), 0),
      zinc: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.minerals?.zinc || 0)), 0)
    },
    other: {
      fiber: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.other?.fiber || 0)), 0),
      cholesterol: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.other?.cholesterol || 0)), 0),
      sugar: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.other?.sugar || 0)), 0),
      saturated_fats: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.other?.saturated_fats || 0)), 0),
      omega_3: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.other?.omega_3 || 0)), 0),
      omega_6: data.ingredient_nutrients.reduce((sum, ing) => sum + ((ing.other?.omega_6 || 0)), 0)
    },
    health_score: data.health_score || "0/10"
    };
    
    return transformedData;
}

// Start the server
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`API Key configured: ${process.env.OPENAI_API_KEY ? 'Yes' : 'No'}`);
  console.log(`Allowed origins: ${allowedOrigins.join(', ')}`);
});

// Error handling for unhandled promises
process.on('unhandledRejection', (error) => {
  console.error('Unhandled Promise Rejection:', error);
}); 