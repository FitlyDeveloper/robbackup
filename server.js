// Import required packages
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const fetch = require('node-fetch');
const fs = require('fs'); // For logging to file

// Create Express app
const app = express();
const PORT = process.env.PORT || 3000;

// Debug startup
console.log('Starting server...');
console.log('Node environment:', process.env.NODE_ENV);
console.log('Current directory:', process.cwd());
console.log('OpenAI API Key present:', process.env.OPENAI_API_KEY ? 'Yes' : 'No');

// Configure logging
const logToFile = (message) => {
  const timestamp = new Date().toISOString();
  const logMessage = `${timestamp}: ${message}\n`;
  fs.appendFileSync('api-server.log', logMessage);
  console.log(message);
};

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

// Configure CORS
app.use(cors());

// Body parser middleware
app.use(express.json({ limit: '10mb' }));

// Define routes
app.get('/', (req, res) => {
  res.json({
    message: 'Food Analyzer API Server',
    status: 'operational'
  });
});

// OpenAI proxy endpoint for food analysis
app.post('/api/analyze-food', limiter, async (req, res) => {
  try {
    logToFile('Analyze food endpoint called');
    const { image } = req.body;

    if (!image) {
      logToFile('No image provided in request');
      return res.status(400).json({
        success: false,
        error: 'Image data is required'
      });
    }

    // Debug logging
    logToFile(`Received image data, length: ${image.length}`);
    logToFile(`Image data starts with: ${image.substring(0, 50)}`);

    // Check for API key
    if (!process.env.OPENAI_API_KEY) {
      logToFile('OpenAI API key not configured');
      return res.status(500).json({
        success: false,
        error: 'Server configuration error: OpenAI API key not set'
      });
    }

    // Call OpenAI API
    logToFile('Calling OpenAI API...');
    
    // Force JSON response format
    const requestBody = {
      model: 'gpt-4o',
      temperature: 0.9,
      messages: [
        {
          role: 'system',
          content: '[STRICTLY JSON ONLY] You are a nutrition expert analyzing food images. OUTPUT MUST BE VALID JSON AND NOTHING ELSE.\n\n[CRITICAL NUTRITION ANALYSIS RULES]\nYou MUST calculate nutritional values BASED ON THE FOOD INGREDIENTS AND THEIR TYPICAL COMPOSITION:\n- Calculate protein, fats, and carbs based on actual typical nutritional composition of the identified ingredients\n- DO NOT inflate protein content - be realistic (e.g., donuts should have LOW protein, around 3-7g per serving)\n- CALORIES MUST BE PRECISE WHOLE NUMBERS - NO ROUNDING to multiples of 10 or 50\n- For example: if a food has 283 calories, return 283 (NOT 280 or 300)\n- Use common food nutrition databases as reference for standard values\n- Sweet foods should typically have higher carbs, lower protein\n- Meat dishes should have higher protein\n- Avoid unrealistic macros like high protein in desserts or high fat in fruits\n\n[CRITICAL INGREDIENT NAMING RULES]\n- EACH INGREDIENT NAME MUST BE 14 CHARACTERS OR LESS (including spaces, commas, hyphens)\n- NEVER USE THE WORD "WITH" IN INGREDIENT NAMES - split ingredients instead\n- If a full ingredient name would be longer than 14 characters, split it into SEPARATE INGREDIENTS\n- For example: "Chocolate with Nuts" is INCORRECT, instead use "Chocolate" and "Nuts" as separate ingredients\n- Another example: "Whole Wheat Bread" (17 chars) should be split into "Whole Wheat" and "Bread" as separate ingredients\n- Each component still gets its own weight and calories\n- Do not abbreviate ingredient names, split them instead\n- Be as specific and accurate as possible with each ingredient name\n\n[CRITICAL UNIT FORMAT RULES]\n- ALWAYS include units for all nutrition values\n- Protein, fats, carbs: use "g" units (e.g., "24g")\n- Calories: use "kcal" units (e.g., "283kcal")\n- Vitamin C: use "mg" units (e.g., "45mg")\n- Iron: use "mg" units (e.g., "2.5mg")\n- Calcium: use "mg" units (e.g., "120mg")\n- All other minerals should include proper units\n- Never separate numbers from their units with spaces\n\nFORMAT RULES:\n1. Return a single meal name for the entire image (e.g., "Pasta Meal")\n2. List ingredients with weights and calories (e.g., "Pasta (100g) 200kcal")\n3. Return PRECISE nutritional values that accurately reflect the food content WITH UNITS\n4. Calculate a health score (1-10) based on ingredient quality and nutritional value\n\nHEALTH SCORE CRITERIA:\n• Positive indicators (+): Whole/unprocessed foods, healthy fats, high fiber foods\n• Negative indicators (-): Highly processed/fried ingredients, added sugars, high saturated fats\n• Score meaning: 9-10 (Very healthy), 7-8 (Healthy), 5-6 (Moderate), 3-4 (Unhealthy), 1-2 (Very unhealthy)\n\nYOU WILL BE PENALIZED SEVERELY IF YOU GENERATE UNREALISTIC NUTRITIONAL VALUES, ROUNDED CALORIES, OR INGREDIENT NAMES LONGER THAN 14 CHARACTERS OR CONTAINING THE WORD "WITH".\n\nEXACT FORMAT REQUIRED:\n{\n  "meal_name": "Meal Name",\n  "ingredients": ["Item1 (weight) calories", "Item2 (weight) calories"],\n  "calories": precise calorie count with kcal unit,\n  "protein": realistic protein amount with g unit,\n  "fat": realistic fat amount with g unit,\n  "carbs": realistic carb amount with g unit,\n  "vitamin_c": realistic vitamin C amount with mg unit,\n  "calcium": amount with mg unit,\n  "iron": amount with mg unit,\n  "fiber": amount with g unit,\n  "sugar": amount with g unit,\n  "sodium": amount with mg unit,\n  "health_score": "score/10"\n}'
        },
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: "RETURN ONLY RAW JSON. Analyze this food image with the MOST ACCURATE values possible based on the typical nutritional composition of the identified ingredients. Use PRECISE CALORIE COUNTS - do not round to multiples of 10 or 50 (e.g., if a food has 283 calories, return 283, not 280 or 300). IMPORTANT: Each ingredient name MUST BE 14 CHARACTERS OR LESS - split longer names into separate ingredients with their own weights and calories. NEVER use the word \"with\" in ingredient names - split them into separate ingredients instead. Ensure all nutritional values are realistic for the type of food shown.\n\n{\n  \"meal_name\": string (single name for entire meal),\n  \"ingredients\": array of strings with weights and calories (EACH INGREDIENT NAME ≤ 14 CHARS, NO \"WITH\"),\n  \"calories\": precise calorie count (exact number, not rounded),\n  \"protein\": realistic protein amount in grams based on ingredients,\n  \"fat\": realistic fat amount in grams based on ingredients,\n  \"carbs\": realistic carb amount in grams based on ingredients,\n  \"vitamin_c\": realistic vitamin C amount in mg based on ingredients,\n  \"health_score\": string\n}"
            },
            {
              type: 'image_url',
              image_url: { url: image }
            }
          ]
        }
      ],
      max_tokens: 1000,
      response_format: { type: 'json_object' }
    };
    
    logToFile('OpenAI request payload structure:');
    logToFile(JSON.stringify({
      model: requestBody.model,
      temperature: requestBody.temperature,
      max_tokens: requestBody.max_tokens,
      response_format: requestBody.response_format,
      message_count: requestBody.messages.length
    }));
    
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
      body: JSON.stringify(requestBody)
    });

    if (!response.ok) {
      const errorData = await response.text();
      logToFile(`OpenAI API error: ${response.status} ${errorData}`);
      return res.status(response.status).json({
        success: false,
        error: `OpenAI API error: ${response.status}`,
        details: errorData
      });
    }

    logToFile('OpenAI API response received');
    const data = await response.json();
    
    // Log the full response structure but not content
    logToFile(`OpenAI response structure: ${JSON.stringify({
      id: data.id,
      object: data.object,
      created: data.created,
      model: data.model,
      choices_count: data.choices ? data.choices.length : 0,
      usage: data.usage
    })}`);
    
    if (!data.choices || 
        !data.choices[0] || 
        !data.choices[0].message || 
        !data.choices[0].message.content) {
      logToFile(`Invalid response format from OpenAI: ${JSON.stringify(data)}`);
      return res.status(500).json({
        success: false,
        error: 'Invalid response from OpenAI',
        raw_response: data
      });
    }

    const content = data.choices[0].message.content;
    logToFile(`OpenAI API response content (first 200 chars): ${content.substring(0, 200)}...`);
    
    // Process and parse the response
    try {
      // First try direct parsing
      const parsedData = JSON.parse(content);
      logToFile('Successfully parsed JSON response');
      logToFile(`Parsed data structure: ${Object.keys(parsedData).join(', ')}`);
      
      return res.json({
        success: true,
        data: parsedData
      });
    } catch (error) {
      logToFile(`Direct JSON parsing failed: ${error.message}`);
      logToFile('Attempting to extract JSON from text');
      
      // Try to extract JSON from the text
      const jsonMatch = content.match(/```json\n([\s\S]*?)\n```/) || 
                      content.match(/\{[\s\S]*\}/);
      
      if (jsonMatch) {
        const jsonContent = jsonMatch[0].replace(/```json\n|```/g, '').trim();
        logToFile(`Found JSON-like content: ${jsonContent.substring(0, 100)}...`);
        
        try {
          const parsedData = JSON.parse(jsonContent);
          logToFile('Successfully extracted and parsed JSON from text');
          return res.json({
            success: true,
            data: parsedData,
            note: 'JSON was extracted from text response'
          });
        } catch (err) {
          logToFile(`JSON extraction failed: ${err.message}`);
          // Return the raw text if JSON parsing fails
          return res.json({
            success: false,
            error: 'Failed to parse JSON',
            data: { text: content }
          });
        }
      } else {
        logToFile('No JSON pattern found in response');
        // Return the raw text if no JSON found
        return res.json({
          success: false,
          error: 'No JSON found in response',
          data: { text: content }
        });
      }
    }
  } catch (error) {
    logToFile(`Server error: ${error.message}`);
    logToFile(error.stack);
    return res.status(500).json({
      success: false,
      error: 'Server error processing request',
      message: error.message
    });
  }
});

// Text-based food analysis endpoint for nutrition calculation
app.post('/api/nutrition', limiter, async (req, res) => {
  try {
    logToFile('Nutrition calculation endpoint called');
    const { food_name, serving_size, operation_type, instructions, current_data } = req.body;

    // Log the request data
    logToFile(`Food name: ${food_name}, Serving size: ${serving_size}`);
    if (operation_type) logToFile(`Operation type: ${operation_type}`);
    if (instructions) logToFile(`Instructions: ${instructions}`);
    
    // Check if we have the minimal required data
    if (!food_name) {
      logToFile('No food name provided in request');
      return res.status(400).json({
        success: false,
        error: 'Food name is required'
      });
    }

    // Check for API key
    if (!process.env.OPENAI_API_KEY) {
      logToFile('OpenAI API key not configured');
      return res.status(500).json({
        success: false,
        error: 'Server configuration error: OpenAI API key not set'
      });
    }

    // Build the prompt based on request type
    let systemPrompt, userPrompt;
    
    if (operation_type === 'GENERAL' || operation_type === 'REDUCE_CALORIES' || 
        operation_type === 'INCREASE_CALORIES' || operation_type === 'REMOVE_INGREDIENT' || 
        operation_type === 'ADD_INGREDIENT') {
      // Food modification prompt
      systemPrompt = 'You are a nutrition expert. Analyze the provided food description and make modifications based on instructions. Return a JSON with the updated nutritional values and ingredients.';
      
      let foodDescription = `Food: ${food_name}\n`;
      
      if (current_data) {
        if (current_data.calories) foodDescription += `Total calories: ${current_data.calories}\n`;
        if (current_data.protein) foodDescription += `Total protein: ${current_data.protein}\n`;
        if (current_data.fat) foodDescription += `Total fat: ${current_data.fat}\n`;
        if (current_data.carbs) foodDescription += `Total carbs: ${current_data.carbs}\n`;
        
        if (current_data.ingredients && current_data.ingredients.length > 0) {
          foodDescription += 'Ingredients:\n';
          for (const ingredient of current_data.ingredients) {
            let ingredientDesc = `- ${ingredient.name}`;
            if (ingredient.amount) ingredientDesc += ` (${ingredient.amount})`;
            if (ingredient.calories) ingredientDesc += `: ${ingredient.calories} calories`;
            if (ingredient.protein) ingredientDesc += `, ${ingredient.protein}g protein`;
            if (ingredient.fat) ingredientDesc += `, ${ingredient.fat}g fat`;
            if (ingredient.carbs) ingredientDesc += `, ${ingredient.carbs}g carbs`;
            foodDescription += ingredientDesc + '\n';
          }
        }
      }
      
      if (instructions) {
        foodDescription += `\nPlease ${operation_type === 'GENERAL' ? 'analyze and update' : operation_type.toLowerCase().replace('_', ' ')} the food according to the following instruction: '${instructions}'`;
      }
      
      userPrompt = foodDescription;
    } else {
      // Basic nutrition calculation prompt
      systemPrompt = 'You are a nutrition expert. Calculate accurate nutritional values for the provided food and serving size. Return a JSON with calories, protein, fat, and carbs.';
      userPrompt = `Calculate accurate nutritional values for ${food_name}, serving size: ${serving_size || '1 serving'}. Return only the JSON with calories, protein, fat, and carbs.`;
    }

    // Prepare request body for OpenAI
    const requestBody = {
      model: 'gpt-4o',
      temperature: 0.5,
      messages: [
        {
          role: 'system',
          content: systemPrompt
        },
        {
          role: 'user',
          content: userPrompt
        }
      ],
      max_tokens: 1000,
      response_format: { type: 'json_object' }
    };
    
    logToFile('OpenAI request payload prepared');
    
    // Call OpenAI API
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
      body: JSON.stringify(requestBody)
    });

    if (!response.ok) {
      const errorData = await response.text();
      logToFile(`OpenAI API error: ${response.status} ${errorData}`);
      return res.status(response.status).json({
        success: false,
        error: `OpenAI API error: ${response.status}`,
        details: errorData
      });
    }

    logToFile('OpenAI API response received');
    const data = await response.json();
    
    if (!data.choices || !data.choices[0] || !data.choices[0].message || !data.choices[0].message.content) {
      logToFile(`Invalid response format from OpenAI: ${JSON.stringify(data)}`);
      return res.status(500).json({
        success: false,
        error: 'Invalid response from OpenAI',
        raw_response: data
      });
    }

    const content = data.choices[0].message.content;
    
    try {
      // Parse the content as JSON
      const parsedData = JSON.parse(content);
      logToFile('Successfully parsed JSON response for nutrition data');
      
      return res.json({
        success: true,
        data: parsedData
      });
    } catch (error) {
      logToFile(`JSON parsing failed: ${error.message}`);
      return res.status(500).json({
        success: false,
        error: 'Failed to parse nutrition data',
        message: error.message
      });
    }
  } catch (error) {
    logToFile(`Server error: ${error.message}`);
    logToFile(error.stack);
    return res.status(500).json({
      success: false,
      error: 'Server error processing nutrition request',
      message: error.message
    });
  }
});

// Start the server
app.listen(PORT, () => {
  logToFile(`Server running on port ${PORT}`);
  logToFile(`API Key configured: ${process.env.OPENAI_API_KEY ? 'Yes' : 'No'}`);
}); 