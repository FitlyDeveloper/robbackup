// Import required packages
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const fetch = require('node-fetch');

// Create Express app
const app = express();
const PORT = process.env.PORT || 10000;

// Debug startup
console.log('Starting server...');
console.log('Node environment:', process.env.NODE_ENV);
console.log('Current directory:', process.cwd());
console.log('OpenAI API Key present:', process.env.OPENAI_API_KEY ? 'Yes' : 'No');

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
  origin: function(origin, callback) {
    // Allow requests with no origin (like mobile apps or curl requests)
    if (!origin) return callback(null, true);
    
    // Check if the origin is allowed
    if (allowedOrigins.indexOf(origin) === -1) {
      const msg = 'The CORS policy for this site does not allow access from the specified Origin.';
      return callback(new Error(msg), false);
    }
    return callback(null, true);
  },
  methods: ['POST'],
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
  console.log('API Key configured: Yes');
  console.log('Allowed origins:', allowedOrigins.join(', '));
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
            content: '[STRICTLY JSON ONLY] SNAPFOOD PROMPT VERSION 12 - You are a nutrition expert providing detailed nutritional analysis of food in photos. Analyze the image and provide a comprehensive nutritional breakdown in JSON format. Include ONLY JSON with NO additional text. Return values with EXACTLY 1 decimal point precision.\n\nYOUR RESPONSE MUST INCLUDE:\n\n1. meal_name: A descriptive name of the overall meal\n2. ingredients: Array of ingredients with estimated weights and calories (e.g., "Grilled Chicken (100g) 165kcal")\n3. ingredient_nutrients: Array of detailed nutritional info for EACH ingredient including:\n   - ingredient_name_ref: Must exactly match an entry in the ingredients array\n   - calories: Total calories\n   - macronutrients: protein, fat, carbs (in grams)\n   - ALL vitamins in a nested "vitamins" object with EXACT KEYS: vitamin_a, vitamin_c, vitamin_d, vitamin_e, vitamin_k, vitamin_b1, vitamin_b2, vitamin_b3, vitamin_b5, vitamin_b6, vitamin_b7, vitamin_b9, vitamin_b12 (all in mg)\n   - ALL minerals in a nested "minerals" object with EXACT KEYS: calcium, iron, magnesium, phosphorus, potassium, sodium, zinc, copper, manganese, selenium, iodine, chromium, molybdenum, fluoride, chloride (all in mg)\n   - ALL other nutrients in a nested "other" object with EXACT KEYS: fiber (g), cholesterol (mg), sugar (g), saturated_fats (g), omega_3 (mg), omega_6 (g)\n\nEnsure ALL ingredients have ALL vitamins, minerals and other nutrients - provide the value 0.0 if a nutrient is not present. All nutrient values MUST be formatted with exactly ONE decimal point (e.g., 12.3, not 12 or 12.34). The "other" nutrients section is CRITICAL and must always be included with all values.'
          },
          {
            role: 'user',
            content: `Analyze the nutritional content of this food image. Provide a comprehensive breakdown with all macronutrients and micronutrients. The image data is: ${image}`
          }
        ],
        max_tokens: 4000,
        response_format: { type: 'json_object' }
      })
    });

    if (!response.ok) {
      const errorData = await response.text();
      console.error('OpenAI API error:', response.status, errorData);
      return res.status(response.status).json({
        success: false,
        error: `OpenAI API error: ${response.status}`
      });
    }

    console.log('OpenAI API request successful. Processing response...');
    const data = await response.json();
    
    // Log the full data object for debugging
    console.log('Full OpenAI API data object received:', JSON.stringify(data, null, 2));
    
    if (!data.choices || 
        !data.choices[0] || 
        !data.choices[0].message || 
        !data.choices[0].message.content) {
      console.error('Invalid response format from OpenAI:', JSON.stringify(data));
      return res.status(500).json({
        success: false,
        error: 'Invalid response from OpenAI'
      });
    }

    const content = data.choices[0].message.content;
    
    // Process and parse the response
    try {
      const parsedData = JSON.parse(content);
      
      // Transform the data to ensure it has the format our frontend expects
      let transformedData = transformToRequiredFormat(parsedData);
      
      return res.json({
        success: true,
        data: transformedData
      });
    } catch (error) {
      console.error('Error parsing or processing OpenAI response:', error);
      return res.status(500).json({
        success: false,
        error: 'Error processing OpenAI response'
      });
    }
  } catch (error) {
    console.error('Server error:', error);
    return res.status(500).json({
      success: false,
      error: 'Server error'
    });
  }
});

// Helper function to transform data to our required format
function transformToRequiredFormat(data) {
  // If we don't have proper data, return error instead of defaults
  if (!data.meal_name || !data.ingredients || !data.ingredient_nutrients || data.ingredients.length === 0) {
    throw new Error('Invalid or missing data: Required fields meal_name, ingredients, and ingredient_nutrients must be provided');
  }

  // Define all required nutrients with their standard keys
  const REQUIRED_VITAMINS = [
    'vitamin_a', 'vitamin_c', 'vitamin_d', 'vitamin_e', 'vitamin_k',
    'vitamin_b1', 'vitamin_b2', 'vitamin_b3', 'vitamin_b5', 'vitamin_b6',
    'vitamin_b7', 'vitamin_b9', 'vitamin_b12'
  ];

  const REQUIRED_MINERALS = [
    'calcium', 'chloride', 'chromium', 'copper', 'fluoride', 'iodine', 'iron',
    'magnesium', 'manganese', 'molybdenum', 'phosphorus', 'potassium',
    'selenium', 'sodium', 'zinc'
  ];

  const REQUIRED_OTHER = [
    'fiber', 'cholesterol', 'sugar', 'saturated_fats', 'omega_3', 'omega_6'
  ];

  // Default values for other nutrients if missing
  const DEFAULT_OTHER_VALUES = {
    'fiber': 2.0,
    'cholesterol': 10.0,
    'sugar': 5.0,
    'saturated_fats': 1.0,
    'omega_3': 0.2,
    'omega_6': 0.5
  };

  // Helper function to round to exactly one decimal place
  const roundToOneDecimal = (value) => {
    if (typeof value === 'number') {
      return parseFloat(value.toFixed(1));
    } else if (typeof value === 'string') {
      const numberValue = parseFloat(value.replace(/[^\d.-]/g, ''));
      return isNaN(numberValue) ? 0.0 : parseFloat(numberValue.toFixed(1));
    }
    return 0.0;
  };

  // Process each ingredient's nutrients
  const processedIngredientNutrients = data.ingredient_nutrients.map(nutrient => {
    const result = {
      ingredient_name_ref: nutrient.ingredient_name_ref,
      calories: roundToOneDecimal(nutrient.calories || 0),
      protein: roundToOneDecimal(nutrient.protein || 0),
      fat: roundToOneDecimal(nutrient.fat || 0),
      carbs: roundToOneDecimal(nutrient.carbs || 0),
      fiber: roundToOneDecimal(nutrient.fiber || 0),
      vitamins: {},
      minerals: {},
      other: {}
    };

    // Process vitamins
    REQUIRED_VITAMINS.forEach(vitamin => {
      if (nutrient.vitamins && nutrient.vitamins[vitamin] !== undefined) {
        result.vitamins[vitamin] = roundToOneDecimal(nutrient.vitamins[vitamin]);
      } else {
        result.vitamins[vitamin] = 0.0;
      }
    });

    // Process minerals
    REQUIRED_MINERALS.forEach(mineral => {
      if (nutrient.minerals && nutrient.minerals[mineral] !== undefined) {
        result.minerals[mineral] = roundToOneDecimal(nutrient.minerals[mineral]);
      } else {
        result.minerals[mineral] = 0.0;
      }
    });

    // Process other nutrients with enhanced checking and defaults
    let hasOtherData = false;
    
    // Create a placeholder for other nutrient data
    let otherData = {};
    
    // First check if 'other' object exists and has any of our required fields
    if (nutrient.other && typeof nutrient.other === 'object') {
      REQUIRED_OTHER.forEach(otherNutrient => {
        if (nutrient.other[otherNutrient] !== undefined) {
          otherData[otherNutrient] = roundToOneDecimal(nutrient.other[otherNutrient]);
          hasOtherData = true;
        }
      });
    }
    
    // Then check for other nutrients at the root level of the ingredient
    REQUIRED_OTHER.forEach(otherNutrient => {
      if (nutrient[otherNutrient] !== undefined) {
        otherData[otherNutrient] = roundToOneDecimal(nutrient[otherNutrient]);
        hasOtherData = true;
      }
    });

    // Special case for 'saturated_fat' -> 'saturated_fats' conversion
    if (nutrient.other && nutrient.other.saturated_fat !== undefined) {
      otherData.saturated_fats = roundToOneDecimal(nutrient.other.saturated_fat);
      hasOtherData = true;
    } else if (nutrient.saturated_fat !== undefined) {
      otherData.saturated_fats = roundToOneDecimal(nutrient.saturated_fat);
      hasOtherData = true;
    }

    // Log if other nutrients are missing
    if (!hasOtherData) {
      console.log(`WARNING: No other nutrients found for ${nutrient.ingredient_name_ref}. Using default values.`);
    }

    // Ensure all required other nutrients exist with appropriate values
    REQUIRED_OTHER.forEach(otherNutrient => {
      if (otherData[otherNutrient] === undefined) {
        // If we don't have data for this nutrient, use the default
        otherData[otherNutrient] = DEFAULT_OTHER_VALUES[otherNutrient] || 0.0;
      }
      
      // Ensure exactly one decimal place
      result.other[otherNutrient] = roundToOneDecimal(otherData[otherNutrient]);
    });

    return result;
  });

  // Return the transformed data
  return {
    meal_name: data.meal_name,
    ingredients: data.ingredients,
    ingredient_nutrients: processedIngredientNutrients
  };
}

// Export the transformToRequiredFormat function for testing
module.exports = {
  transformToRequiredFormat
};

// Start the server
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
}); 