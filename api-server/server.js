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
            content: '[STRICTLY JSON ONLY] You are a nutrition expert analyzing food images. You must be EXTREMELY SPECIFIC and DETAILED. OUTPUT MUST BE VALID JSON AND NOTHING ELSE.\n\nFORMAT RULES:\n1. MEAL NAMING RULES:\n   - NEVER use generic terms like "Mixed Meal" or "Plate"\n   - BE SPECIFIC: e.g. "Pepperoni and Mushroom Pizza" instead of just "Pizza"\n   - Include main ingredients in the name: e.g. "Grilled Chicken Caesar Salad" instead of just "Salad"\n   - If multiple items, name it after the primary dish: e.g. "Cheeseburger with Sweet Potato Fries"\n\n2. INGREDIENT LISTING RULES:\n   - List EVERY visible ingredient separately in the 'ingredients' array as strings: "Ingredient Name (estimated weight) estimated_calories_for_ingredient_kcal" (e.g., "Chicken Breast (150g) 240kcal").\n   - Include estimated weights (e.g., 100g, 50ml) and estimated calories for EACH ingredient in this string format.\n   - DO NOT use generic terms like "Mixed ingredients". If an ingredient is visible, it MUST be listed.\n\n3. NUTRIENT BREAKDOWN FOR EACH INGREDIENT (in 'ingredient_nutrients' array):\n   - For EACH item in the 'ingredients' array, provide a corresponding object in the 'ingredient_nutrients' array.\n   - EACH such object MUST contain: calories (kcal), protein (g), fat (g), carbs (g), fiber (g), sugar (g), cholesterol (mg), saturated_fats (g), omega_3 (mg), omega_6 (g).\n   - EACH such object MUST ALSO contain a nested 'vitamins' object and a nested 'minerals' object, listing ALL specified vitamins and minerals with their amounts and units for THAT INGREDIENT.\n     * Vitamins: A (IU), C (mg), D (IU), E (mg), K (mcg), B1/Thiamin (mg), B2/Riboflavin (mg), B3/Niacin (mg), B5/Pantothenic acid (mg), B6/Pyridoxine (mg), B7/Biotin (mcg), B9/Folate (mcg), B12/Cobalamin (mcg).\n     * Minerals: calcium (mg), iron (mg), magnesium (mg), phosphorus (mg), potassium (mg), sodium (mg), zinc (mg), copper (mg), manganese (mg), selenium (mcg), iodine (mcg), chromium (mcg), molybdenum (mcg), fluoride (mg), chloride (mg).\n
4. TOTALS FOR THE ENTIRE MEAL:\n   - Provide overall total values for the entire meal: total_calories (kcal), total_protein (g), total_fat (g), total_carbs (g), total_fiber (g), total_sugar (g), total_cholesterol (mg), total_saturated_fats (g), total_omega_3 (mg), total_omega_6 (g).\n   - Provide a 'total_vitamins' object and a 'total_minerals' object with the sum of ALL specified vitamins and minerals for the entire meal.\n
5. Add a health score (1-10) for the entire meal.\n6. Use realistic decimal places for nutrient values.\n7. DO NOT respond with markdown code blocks or any text explanations outside the JSON.\n8. ONLY RETURN A RAW JSON OBJECT. NO PREFIXES, NO MARKDOWN.\n9. FAILURE TO FOLLOW THESE INSTRUCTIONS, ESPECIALLY THE PER-INGREDIENT BREAKDOWN, WILL RESULT IN REJECTION.\n
EXACT FORMAT REQUIRED (Illustrative Example - provide real data based on image):
{
  "meal_name": "Grilled Chicken Salad with Avocado",
  "ingredients": [
    "Chicken Breast (150g) 240kcal", 
    "Avocado (70g) 120kcal", 
    "Romaine Lettuce (100g) 15kcal", 
    "Olive Oil Dressing (15ml) 120kcal"
  ],
  "ingredient_nutrients": [
    {
      "ingredient_name_ref": "Chicken Breast (150g) 240kcal", // Reference to 'ingredients' list
      "calories": 240,
      "protein": 45.0,
      "fat": 6.0,
      "carbs": 0.0,
      "fiber": 0.0,
      "sugar": 0.0,
      "cholesterol": 120,
      "saturated_fats": 1.5,
      "omega_3": 50,
      "omega_6": 0.5,
      "vitamins": {
        "vitamin_a": 0, "vitamin_c": 0, "vitamin_d": 5, "vitamin_e": 0.5, "vitamin_k": 0,
        "vitamin_b1": 0.1, "vitamin_b2": 0.3, "vitamin_b3": 12.0, "vitamin_b5": 1.0,
        "vitamin_b6": 0.9, "vitamin_b7": 3, "vitamin_b9": 10, "vitamin_b12": 1.0
      },
      "minerals": {
        "calcium": 15, "iron": 1.0, "magnesium": 30, "phosphorus": 300, "potassium": 400,
        "sodium": 70, "zinc": 1.0, "copper": 0.1, "manganese": 0.05, "selenium": 40,
        "iodine": 2, "chromium": 5, "molybdenum": 10, "fluoride": 0, "chloride": 80
      }
    },
    {
      "ingredient_name_ref": "Avocado (70g) 120kcal",
      "calories": 120,
      "protein": 1.5,
      "fat": 11.0,
      "carbs": 6.0,
      "fiber": 5.0,
      "sugar": 0.5,
      "cholesterol": 0,
      "saturated_fats": 1.5,
      "omega_3": 80,
      "omega_6": 1.2,
      "vitamins": { /* ... detailed vitamins for Avocado ... */ },
      "minerals": { /* ... detailed minerals for Avocado ... */ }
    }
    // ... (objects for Romaine Lettuce and Olive Oil Dressing with their full nutrient breakdowns)
  ],
  "total_calories": 500, // Example sum
  "total_protein": 48.0,
  "total_fat": 25.0,
  "total_carbs": 10.0,
  "total_fiber": 7.0,
  "total_sugar": 1.0,
  "total_cholesterol": 120,
  "total_saturated_fats": 4.0,
  "total_omega_3": 150,
  "total_omega_6": 2.0,
  "total_vitamins": { /* ... summed vitamins for the whole meal ... */ },
  "total_minerals": { /* ... summed minerals for the whole meal ... */ },
  "health_score": "8/10"
}
'
          },
          {
            role: 'user',
            content: [
              {
                type: 'text',
                text: "RETURN ONLY RAW JSON - NO TEXT, NO MARKDOWN, NO EXPLANATIONS. Analyze this food image. YOU MUST PROVIDE A COMPLETE AND ACCURATE NUTRITIONAL BREAKDOWN FOR EACH INDIVIDUAL INGREDIENT, including its calories, protein (g), fat (g), carbs (g), fiber (g), sugar (g), cholesterol (mg), saturated_fats (g), omega_3 (mg), omega_6 (g), and FULLY POPULATED nested 'vitamins' and 'minerals' objects with all specified micro-nutrients for THAT SPECIFIC INGREDIENT. Also provide overall totals for the meal. Adhere strictly to the JSON format specified in the system prompt, especially for the 'ingredient_nutrients' array."
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
      const errorData = await response.text();
      console.error('OpenAI API error:', response.status, errorData);
      return res.status(response.status).json({
        success: false,
        error: `OpenAI API error: ${response.status}`
      });
    }

    console.log('OpenAI API response received');
    const data = await response.json();
    
    if (!data.choices || !data.choices[0] || !data.choices[0].message || !data.choices[0].message.content) {
      console.error('Invalid response format from OpenAI:', JSON.stringify(data));
      return res.status(500).json({
        success: false,
        error: 'Invalid response from OpenAI'
      });
    }

    const content = data.choices[0].message.content;
    console.log('OpenAI API response content (first 100 chars):', content.substring(0, 100) + '...');
    
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

// Helper function to transform raw text to our required format
function transformTextToRequiredFormat(text) {
  // Extract any top-level micronutrients from the text
  const topLevelVitamins = {};
  const topLevelMinerals = {};
  
  // Look for vitamin and mineral mentions in the text
  const vitaminMatches = text.match(/vitamin [a-z]\s*:\s*[\d\.]+/gi) || [];
  const mineralMatches = text.match(/(iron|calcium|zinc|magnesium|potassium|sodium)\s*:\s*[\d\.]+/gi) || [];
  
  // Extract values from matches
  vitaminMatches.forEach(match => {
    const parts = match.split(':');
    if (parts.length === 2) {
      const name = parts[0].trim().toLowerCase().replace('vitamin ', '');
      const value = parseFloat(parts[1].trim());
      if (!isNaN(value)) {
        topLevelVitamins[name] = value;
      }
    }
  });
  
  mineralMatches.forEach(match => {
    const parts = match.split(':');
    if (parts.length === 2) {
      const name = parts[0].trim().toLowerCase();
      const value = parseFloat(parts[1].trim());
      if (!isNaN(value)) {
        topLevelMinerals[name] = value;
      }
    }
  });
  
  // Try to parse "Food item" format
  if (text.includes('Food item') || text.includes('FOOD ANALYSIS RESULTS')) {
    const lines = text.split('\n');
    const ingredients = [];
    const ingredientMacros = [];
    let calories = 0;
    let protein = 0;
    let fat = 0;
    let carbs = 0;
    let vitaminC = 0;
    let mealName = "Mixed Meal";
    
    // Extract meal name from the first food item if available
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].includes('Food item 1:')) {
        mealName = lines[i].replace('Food item 1:', '').trim();
        break;
      }
    }
    
    // Process each line for ingredients and nutrition values
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      
      if (line.startsWith('Ingredients:')) {
        const ingredientsText = line.replace('Ingredients:', '').trim();
        const ingredientParts = ingredientsText.split(',');
        
        for (const part of ingredientParts) {
          let ingredient = part.trim();
          let ingredientWeight = '30g';
          let ingredientCalories = 75;
          let ingredientProtein = 3.0;
          let ingredientFat = 2.0;
          let ingredientCarbs = 10.0;
          
          // Vitamins and minerals for this ingredient
          let vitamins = {};
          let minerals = {};
          
          // Customize based on ingredient type - using same logic as above for consistency
          if (ingredient.toLowerCase().includes('pasta') || 
              ingredient.toLowerCase().includes('noodle')) {
            ingredientWeight = '100g';
            ingredientCalories = 200;
            ingredientProtein = 7.5;
            ingredientFat = 1.1;
            ingredientCarbs = 43.2;
            // Add micronutrients
            vitamins = {
              'b1': 0.2,
              'b2': 0.1,
              'b3': 1.7,
              'b6': 0.1,
              'folate': 18
            };
            minerals = {
              'iron': 1.8,
              'magnesium': 53,
              'phosphorus': 189,
              'zinc': 1.3,
              'selenium': 63.2,
              'potassium': 223
            };
          } else if (ingredient.toLowerCase().includes('rice')) {
            ingredientWeight = '100g';
            ingredientCalories = 130;
            ingredientProtein = 2.7;
            ingredientFat = 0.3;
            ingredientCarbs = 28.2;
            // Add micronutrients
            vitamins = {
              'b1': 0.1,
              'b3': 1.6,
              'b6': 0.15,
              'folate': 8
            };
            minerals = {
              'iron': 0.4,
              'magnesium': 25,
              'phosphorus': 115,
              'zinc': 1.2,
              'selenium': 15.1,
              'potassium': 115
            };
          } else if (ingredient.toLowerCase().includes('watermelon')) {
            ingredientWeight = '100g';
            ingredientCalories = 30;
            ingredientProtein = 0.6;
            ingredientFat = 0.2;
            ingredientCarbs = 7.6;
            // Add micronutrients for watermelon
            vitamins = {
              'a': 569,
              'c': 8.1,
              'b6': 0.045,
              'b1': 0.033
            };
            minerals = {
              'potassium': 112,
              'magnesium': 10,
              'phosphorus': 11,
              'zinc': 0.1
            };
          } else if (ingredient.toLowerCase().includes('pineapple')) {
            ingredientWeight = '100g';
            ingredientCalories = 50;
            ingredientProtein = 0.5;
            ingredientFat = 0.1;
            ingredientCarbs = 13.1;
            // Add micronutrients for pineapple
            vitamins = {
              'c': 47.8,
              'b1': 0.079,
              'b6': 0.112,
              'folate': 18
            };
            minerals = {
              'manganese': 0.927,
              'copper': 0.110,
              'potassium': 109,
              'magnesium': 12
            };
          }

          if (ingredient.includes('(') && ingredient.includes(')')) {
            ingredients.push(ingredient);
          } else {
            // Add estimated weight and calories if not provided
            ingredients.push(`${ingredient} (${ingredientWeight}) ${ingredientCalories}kcal`);
          }
          
          // Ensure each ingredient has vitamins/minerals by using top-level data if available
          if (Object.keys(vitamins).length === 0 && Object.keys(topLevelVitamins).length > 0) {
            vitamins = { ...topLevelVitamins };
          }
          
          if (Object.keys(minerals).length === 0 && Object.keys(topLevelMinerals).length > 0) {
            minerals = { ...topLevelMinerals };
          }

          // Add macros for this ingredient with 1 decimal precision
          ingredientMacros.push({
            protein: parseFloat(ingredientProtein.toFixed(1)),
            fat: parseFloat(ingredientFat.toFixed(1)),
            carbs: parseFloat(ingredientCarbs.toFixed(1)),
            vitamins: vitamins,
            minerals: minerals
          });
        }
      }
      
      if (line.startsWith('Calories:')) {
        const calValue = parseFloat(line.replace('Calories:', '').replace('kcal', '').trim());
        if (!isNaN(calValue)) calories += calValue;
      }
      
      if (line.startsWith('Protein:')) {
        const protValue = parseFloat(line.replace('Protein:', '').replace('g', '').trim());
        if (!isNaN(protValue)) protein += protValue;
      }
      
      if (line.startsWith('Fat:')) {
        const fatValue = parseFloat(line.replace('Fat:', '').replace('g', '').trim());
        if (!isNaN(fatValue)) fat += fatValue;
      }
      
      if (line.startsWith('Carbs:')) {
        const carbValue = parseFloat(line.replace('Carbs:', '').replace('g', '').trim());
        if (!isNaN(carbValue)) carbs += carbValue;
      }
      
      if (line.startsWith('Vitamin C:')) {
        const vitCValue = parseFloat(line.replace('Vitamin C:', '').replace('mg', '').trim());
        if (!isNaN(vitCValue)) vitaminC += vitCValue;
      }
    }
    
    // If we don't have any ingredients, add placeholders
    if (ingredients.length === 0) {
      ingredients.push("Mixed ingredients (100g) 200kcal");
      ingredientMacros.push({
        protein: 10.0,
        fat: 7.0,
        carbs: 30.0,
        vitamins: Object.keys(topLevelVitamins).length > 0 ? { ...topLevelVitamins } : {
          'c': 2.0,
          'a': 100,
          'b1': 0.1,
          'b2': 0.2
        },
        minerals: Object.keys(topLevelMinerals).length > 0 ? { ...topLevelMinerals } : {
          'calcium': 30,
          'iron': 1.2,
          'potassium': 150,
          'magnesium': 20
        }
      });
    }
    
    // Calculate a health score (simple algorithm based on macros)
    const healthScore = Math.max(1, Math.min(10, Math.round((protein * 0.5 + vitaminC * 0.3) / (fat * 0.3 + calories / 100))));
    
    // Get values with fallbacks
    const totalCalories = calories || 500;
    const totalProtein = protein || 15;
    const totalFat = fat || 10;
    const totalCarbs = carbs || 20;
    
    // Return the properly formatted JSON with complete nutrient data
    return {
      meal_name: mealName,
      ingredients: ingredients,
      ingredient_nutrients: ingredientMacros,
      calories: totalCalories,
      protein: totalProtein,
      fat: totalFat,
      carbs: totalCarbs,
      health_score: `${healthScore}/10`,
      // Complete vitamins object with estimates for missing values
      vitamins: {
        vitamin_a: (topLevelVitamins.a !== undefined) ? topLevelVitamins.a : Math.round(totalCalories * 0.1),
        vitamin_c: vitaminC || Math.round(totalCalories * 0.06),
        vitamin_d: (topLevelVitamins.d !== undefined) ? topLevelVitamins.d : Math.round(totalCalories * 0.02),
        vitamin_e: (topLevelVitamins.e !== undefined) ? topLevelVitamins.e : Math.round(totalCalories * 0.05),
        vitamin_k: (topLevelVitamins.k !== undefined) ? topLevelVitamins.k : Math.round(totalCalories * 0.04),
        vitamin_b1: (topLevelVitamins.b1 !== undefined) ? topLevelVitamins.b1 : Math.round(totalCalories * 0.03),
        vitamin_b2: (topLevelVitamins.b2 !== undefined) ? topLevelVitamins.b2 : Math.round(totalCalories * 0.03),
        vitamin_b3: (topLevelVitamins.b3 !== undefined) ? topLevelVitamins.b3 : Math.round(totalCalories * 0.05),
        vitamin_b5: (topLevelVitamins.b5 !== undefined) ? topLevelVitamins.b5 : Math.round(totalCalories * 0.02),
        vitamin_b6: (topLevelVitamins.b6 !== undefined) ? topLevelVitamins.b6 : Math.round(totalCalories * 0.03),
        vitamin_b7: (topLevelVitamins.b7 !== undefined) ? topLevelVitamins.b7 : Math.round(totalCalories * 0.01),
        vitamin_b9: (topLevelVitamins.b9 !== undefined) ? topLevelVitamins.b9 : Math.round(totalCalories * 0.04),
        vitamin_b12: (topLevelVitamins.b12 !== undefined) ? topLevelVitamins.b12 : Math.round(totalCalories * 0.02),
        ...topLevelVitamins
      },
      // Complete minerals object with estimates for missing values
      minerals: {
        calcium: (topLevelMinerals.calcium !== undefined) ? topLevelMinerals.calcium : Math.round(totalCalories * 0.2),
        chloride: (topLevelMinerals.chloride !== undefined) ? topLevelMinerals.chloride : Math.round(totalCalories * 0.1),
        chromium: (topLevelMinerals.chromium !== undefined) ? topLevelMinerals.chromium : Math.round(totalCalories * 0.01),
        copper: (topLevelMinerals.copper !== undefined) ? topLevelMinerals.copper : Math.round(totalCalories * 0.03),
        fluoride: (topLevelMinerals.fluoride !== undefined) ? topLevelMinerals.fluoride : Math.round(totalCalories * 0.02),
        iodine: (topLevelMinerals.iodine !== undefined) ? topLevelMinerals.iodine : Math.round(totalCalories * 0.01),
        iron: (topLevelMinerals.iron !== undefined) ? topLevelMinerals.iron : Math.round(totalCalories * 0.08),
        magnesium: (topLevelMinerals.magnesium !== undefined) ? topLevelMinerals.magnesium : Math.round(totalCalories * 0.15),
        manganese: (topLevelMinerals.manganese !== undefined) ? topLevelMinerals.manganese : Math.round(totalCalories * 0.05),
        molybdenum: (topLevelMinerals.molybdenum !== undefined) ? topLevelMinerals.molybdenum : Math.round(totalCalories * 0.01),
        phosphorus: (topLevelMinerals.phosphorus !== undefined) ? topLevelMinerals.phosphorus : Math.round(totalCalories * 0.15),
        potassium: (topLevelMinerals.potassium !== undefined) ? topLevelMinerals.potassium : Math.round(totalCalories * 0.3),
        selenium: (topLevelMinerals.selenium !== undefined) ? topLevelMinerals.selenium : Math.round(totalCalories * 0.02),
        sodium: (topLevelMinerals.sodium !== undefined) ? topLevelMinerals.sodium : Math.round(totalCalories * 0.2),
        zinc: (topLevelMinerals.zinc !== undefined) ? topLevelMinerals.zinc : Math.round(totalCalories * 0.05),
        ...topLevelMinerals
      },
      // Other nutrients with default values
      other: {
        fiber: Math.round(totalCarbs * 0.15),
        cholesterol: Math.round(totalFat * 10),
        sugar: Math.round(totalCarbs * 0.4),
        saturated_fats: Math.round(totalFat * 0.35),
        omega_3: Math.round(totalFat * 1),
        omega_6: Math.round(totalFat * 2)
      }
    };
  }
  
  // Default response if we can't parse anything meaningful
  // Use default values for calories, macros, and health score
  const calories = 500;
  const protein = 20;
  const fat = 15;
  const carbs = 60;
  
  return {
    meal_name: "Mixed Meal",
    ingredients: [
      "Mixed ingredients (100g) 200kcal"
    ],
    ingredient_nutrients: [
      {
        protein: 10,
        fat: 7,
        carbs: 30,
        vitamins: {},
        minerals: {},
        other: {}
      }
    ],
    calories: calories,
    protein: protein,
    fat: fat,
    carbs: carbs,
    health_score: "6/10",
    // Complete vitamins object with estimates for missing values
    vitamins: {
      vitamin_a: (topLevelVitamins.a !== undefined) ? topLevelVitamins.a : Math.round(calories * 0.1),
      vitamin_c: (topLevelVitamins.c !== undefined) ? topLevelVitamins.c : 2,
      vitamin_d: (topLevelVitamins.d !== undefined) ? topLevelVitamins.d : Math.round(calories * 0.02),
      vitamin_e: (topLevelVitamins.e !== undefined) ? topLevelVitamins.e : Math.round(calories * 0.05),
      vitamin_k: (topLevelVitamins.k !== undefined) ? topLevelVitamins.k : Math.round(calories * 0.04),
      vitamin_b1: (topLevelVitamins.b1 !== undefined) ? topLevelVitamins.b1 : Math.round(calories * 0.03),
      vitamin_b2: (topLevelVitamins.b2 !== undefined) ? topLevelVitamins.b2 : Math.round(calories * 0.03),
      vitamin_b3: (topLevelVitamins.b3 !== undefined) ? topLevelVitamins.b3 : Math.round(calories * 0.05),
      vitamin_b5: (topLevelVitamins.b5 !== undefined) ? topLevelVitamins.b5 : Math.round(calories * 0.02),
      vitamin_b6: (topLevelVitamins.b6 !== undefined) ? topLevelVitamins.b6 : Math.round(calories * 0.03),
      vitamin_b7: (topLevelVitamins.b7 !== undefined) ? topLevelVitamins.b7 : Math.round(calories * 0.01),
      vitamin_b9: (topLevelVitamins.b9 !== undefined) ? topLevelVitamins.b9 : Math.round(calories * 0.04),
      vitamin_b12: (topLevelVitamins.b12 !== undefined) ? topLevelVitamins.b12 : Math.round(calories * 0.02),
      ...topLevelVitamins
    },
    // Complete minerals object with estimates for missing values
    minerals: {
      calcium: (topLevelMinerals.calcium !== undefined) ? topLevelMinerals.calcium : Math.round(calories * 0.2),
      chloride: (topLevelMinerals.chloride !== undefined) ? topLevelMinerals.chloride : Math.round(calories * 0.1),
      chromium: (topLevelMinerals.chromium !== undefined) ? topLevelMinerals.chromium : Math.round(calories * 0.01),
      copper: (topLevelMinerals.copper !== undefined) ? topLevelMinerals.copper : Math.round(calories * 0.03),
      fluoride: (topLevelMinerals.fluoride !== undefined) ? topLevelMinerals.fluoride : Math.round(calories * 0.02),
      iodine: (topLevelMinerals.iodine !== undefined) ? topLevelMinerals.iodine : Math.round(calories * 0.01),
      iron: (topLevelMinerals.iron !== undefined) ? topLevelMinerals.iron : Math.round(calories * 0.08),
      magnesium: (topLevelMinerals.magnesium !== undefined) ? topLevelMinerals.magnesium : Math.round(calories * 0.15),
      manganese: (topLevelMinerals.manganese !== undefined) ? topLevelMinerals.manganese : Math.round(calories * 0.05),
      molybdenum: (topLevelMinerals.molybdenum !== undefined) ? topLevelMinerals.molybdenum : Math.round(calories * 0.01),
      phosphorus: (topLevelMinerals.phosphorus !== undefined) ? topLevelMinerals.phosphorus : Math.round(calories * 0.15),
      potassium: (topLevelMinerals.potassium !== undefined) ? topLevelMinerals.potassium : Math.round(calories * 0.3),
      selenium: (topLevelMinerals.selenium !== undefined) ? topLevelMinerals.selenium : Math.round(calories * 0.02),
      sodium: (topLevelMinerals.sodium !== undefined) ? topLevelMinerals.sodium : Math.round(calories * 0.2),
      zinc: (topLevelMinerals.zinc !== undefined) ? topLevelMinerals.zinc : Math.round(calories * 0.05),
      ...topLevelMinerals
    },
    // Other nutrients with default values
    other: {
      fiber: Math.round(carbs * 0.15),
      cholesterol: Math.round(fat * 10),
      sugar: Math.round(carbs * 0.4),
      saturated_fats: Math.round(fat * 0.35),
      omega_3: Math.round(fat * 1),
      omega_6: Math.round(fat * 2)
    }
  };
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