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

// Set trust proxy for proper IP detection behind reverse proxies (fixes express-rate-limit warning)
app.set('trust proxy', 1);

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
      temperature: 0.3,
      messages: [
        {
          role: 'system',
          content: 'You are a nutrition expert. Analyze food images and return detailed nutritional information in JSON format. Include all vitamins, minerals, and macronutrients with proper units.'
        },
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: `Please analyze this food image and return a JSON object with complete nutritional information. Include:

1. Basic info: meal_name, ingredients (with weights), calories, protein, fat, carbs
2. All 13 vitamins: A, C, D, E, K, B1, B2, B3, B5, B6, B7, B9, B12 (with proper units)
3. All 15 minerals: calcium, chloride, chromium, copper, fluoride, iodine, iron, magnesium, manganese, molybdenum, phosphorus, potassium, selenium, sodium, zinc (with proper units)
4. Other nutrients: fiber, cholesterol, sugar, saturated_fats, omega_3, omega_6 (with proper units)
5. Health score (1-10)

Use realistic nutritional values based on standard food databases. Return only valid JSON.

Example format:
{
  "meal_name": "Food Name",
  "ingredients": ["Item1 (100g) 200kcal", "Item2 (50g) 150kcal"],
  "calories": "350kcal",
  "protein": "15g",
  "fat": "12g", 
  "carbs": "45g",
  "vitamin_a": "500mcg",
  "vitamin_c": "30mg",
  "vitamin_d": "2mcg",
  "vitamin_e": "5mg",
  "vitamin_k": "15mcg",
  "vitamin_b1": "0.8mg",
  "vitamin_b2": "0.6mg",
  "vitamin_b3": "8mg",
  "vitamin_b5": "3mg",
  "vitamin_b6": "1mg",
  "vitamin_b7": "20mcg",
  "vitamin_b9": "150mcg",
  "vitamin_b12": "1mcg",
  "calcium": "200mg",
  "chloride": "300mg",
  "chromium": "5mcg",
  "copper": "200mcg",
  "fluoride": "0.5mg",
  "iodine": "20mcg",
  "iron": "3mg",
  "magnesium": "80mg",
  "manganese": "1mg",
  "molybdenum": "10mcg",
  "phosphorus": "150mg",
  "potassium": "400mg",
  "selenium": "15mcg",
  "sodium": "500mg",
  "zinc": "2mg",
  "fiber": "8g",
  "cholesterol": "50mg",
  "sugar": "20g",
  "saturated_fats": "4g",
  "omega_3": "200mg",
  "omega_6": "1g",
  "health_score": "7/10"
}`
            },
            {
              type: 'image_url',
              image_url: { url: image }
            }
          ]
        }
      ],
      max_tokens: 1500,
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
      
      // 🔬 LOG ALL 34 MICRONUTRIENTS TO TERMINAL
      if (parsedData) {
        console.log('\n🔬 ===== COMPLETE MICRONUTRIENT ANALYSIS =====');
        console.log(`📊 Meal: ${parsedData.meal_name || 'Unknown'}`);
        console.log(`🍽️ Total Calories: ${parsedData.calories || 0}`);
        console.log(`🥩 Protein: ${parsedData.protein || 0}g`);
        console.log(`🧈 Fat: ${parsedData.fat || 0}g`);
        console.log(`🍞 Carbs: ${parsedData.carbs || 0}g`);
        
        console.log('\n💊 VITAMINS (13):');
        console.log(`  Vitamin A: ${parsedData.vitamin_a || 0} mcg`);
        console.log(`  Vitamin C: ${parsedData.vitamin_c || 0} mg`);
        console.log(`  Vitamin D: ${parsedData.vitamin_d || 0} mcg`);
        console.log(`  Vitamin E: ${parsedData.vitamin_e || 0} mg`);
        console.log(`  Vitamin K: ${parsedData.vitamin_k || 0} mcg`);
        console.log(`  Vitamin B1 (Thiamine): ${parsedData.vitamin_b1 || 0} mg`);
        console.log(`  Vitamin B2 (Riboflavin): ${parsedData.vitamin_b2 || 0} mg`);
        console.log(`  Vitamin B3 (Niacin): ${parsedData.vitamin_b3 || 0} mg`);
        console.log(`  Vitamin B5 (Pantothenic): ${parsedData.vitamin_b5 || 0} mg`);
        console.log(`  Vitamin B6 (Pyridoxine): ${parsedData.vitamin_b6 || 0} mg`);
        console.log(`  Vitamin B7 (Biotin): ${parsedData.vitamin_b7 || 0} mcg`);
        console.log(`  Vitamin B9 (Folate): ${parsedData.vitamin_b9 || 0} mcg`);
        console.log(`  Vitamin B12 (Cobalamin): ${parsedData.vitamin_b12 || 0} mcg`);
        
        console.log('\n⚗️ MINERALS (15):');
        console.log(`  Calcium: ${parsedData.calcium || 0} mg`);
        console.log(`  Chloride: ${parsedData.chloride || 0} mg`);
        console.log(`  Chromium: ${parsedData.chromium || 0} mcg`);
        console.log(`  Copper: ${parsedData.copper || 0} mcg`);
        console.log(`  Fluoride: ${parsedData.fluoride || 0} mg`);
        console.log(`  Iodine: ${parsedData.iodine || 0} mcg`);
        console.log(`  Iron: ${parsedData.iron || 0} mg`);
        console.log(`  Magnesium: ${parsedData.magnesium || 0} mg`);
        console.log(`  Manganese: ${parsedData.manganese || 0} mg`);
        console.log(`  Molybdenum: ${parsedData.molybdenum || 0} mcg`);
        console.log(`  Phosphorus: ${parsedData.phosphorus || 0} mg`);
        console.log(`  Potassium: ${parsedData.potassium || 0} mg`);
        console.log(`  Selenium: ${parsedData.selenium || 0} mcg`);
        console.log(`  Sodium: ${parsedData.sodium || 0} mg`);
        console.log(`  Zinc: ${parsedData.zinc || 0} mg`);
        
        console.log('\n🥗 OTHER NUTRIENTS (6):');
        console.log(`  Fiber: ${parsedData.fiber || 0} g`);
        console.log(`  Cholesterol: ${parsedData.cholesterol || 0} mg`);
        console.log(`  Sugar: ${parsedData.sugar || 0} g`);
        console.log(`  Saturated Fats: ${parsedData.saturated_fats || 0} g`);
        console.log(`  Omega-3: ${parsedData.omega_3 || 0} mg`);
        console.log(`  Omega-6: ${parsedData.omega_6 || 0} mg`);
        
        if (parsedData.ingredients && parsedData.ingredients.length > 0) {
          console.log('\n🔬 INGREDIENT BREAKDOWN:');
          parsedData.ingredients.forEach((ingredient, index) => {
            console.log(`  ${index + 1}. ${ingredient.name} (${ingredient.amount || 'N/A'})`);
            console.log(`     Calories: ${ingredient.calories || 0}, Protein: ${ingredient.protein || 0}g, Fat: ${ingredient.fat || 0}g, Carbs: ${ingredient.carbs || 0}g`);
          });
        }
        
        console.log('🔬 ============================================\n');
      }
      
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
          
          // 🔬 LOG ALL 34 MICRONUTRIENTS TO TERMINAL (FALLBACK PATH)
          if (parsedData) {
            console.log('\n🔬 ===== COMPLETE MICRONUTRIENT ANALYSIS (FALLBACK) =====');
            console.log(`📊 Meal: ${parsedData.meal_name || 'Unknown'}`);
            console.log(`🍽️ Total Calories: ${parsedData.calories || 0}`);
            console.log(`🥩 Protein: ${parsedData.protein || 0}g`);
            console.log(`🧈 Fat: ${parsedData.fat || 0}g`);
            console.log(`🍞 Carbs: ${parsedData.carbs || 0}g`);
            
            console.log('\n💊 VITAMINS (13):');
            console.log(`  Vitamin A: ${parsedData.vitamin_a || 0} mcg`);
            console.log(`  Vitamin C: ${parsedData.vitamin_c || 0} mg`);
            console.log(`  Vitamin D: ${parsedData.vitamin_d || 0} mcg`);
            console.log(`  Vitamin E: ${parsedData.vitamin_e || 0} mg`);
            console.log(`  Vitamin K: ${parsedData.vitamin_k || 0} mcg`);
            console.log(`  Vitamin B1 (Thiamine): ${parsedData.vitamin_b1 || 0} mg`);
            console.log(`  Vitamin B2 (Riboflavin): ${parsedData.vitamin_b2 || 0} mg`);
            console.log(`  Vitamin B3 (Niacin): ${parsedData.vitamin_b3 || 0} mg`);
            console.log(`  Vitamin B5 (Pantothenic): ${parsedData.vitamin_b5 || 0} mg`);
            console.log(`  Vitamin B6 (Pyridoxine): ${parsedData.vitamin_b6 || 0} mg`);
            console.log(`  Vitamin B7 (Biotin): ${parsedData.vitamin_b7 || 0} mcg`);
            console.log(`  Vitamin B9 (Folate): ${parsedData.vitamin_b9 || 0} mcg`);
            console.log(`  Vitamin B12 (Cobalamin): ${parsedData.vitamin_b12 || 0} mcg`);
            
            console.log('\n⚗️ MINERALS (15):');
            console.log(`  Calcium: ${parsedData.calcium || 0} mg`);
            console.log(`  Chloride: ${parsedData.chloride || 0} mg`);
            console.log(`  Chromium: ${parsedData.chromium || 0} mcg`);
            console.log(`  Copper: ${parsedData.copper || 0} mcg`);
            console.log(`  Fluoride: ${parsedData.fluoride || 0} mg`);
            console.log(`  Iodine: ${parsedData.iodine || 0} mcg`);
            console.log(`  Iron: ${parsedData.iron || 0} mg`);
            console.log(`  Magnesium: ${parsedData.magnesium || 0} mg`);
            console.log(`  Manganese: ${parsedData.manganese || 0} mg`);
            console.log(`  Molybdenum: ${parsedData.molybdenum || 0} mcg`);
            console.log(`  Phosphorus: ${parsedData.phosphorus || 0} mg`);
            console.log(`  Potassium: ${parsedData.potassium || 0} mg`);
            console.log(`  Selenium: ${parsedData.selenium || 0} mcg`);
            console.log(`  Sodium: ${parsedData.sodium || 0} mg`);
            console.log(`  Zinc: ${parsedData.zinc || 0} mg`);
            
            console.log('\n🥗 OTHER NUTRIENTS (6):');
            console.log(`  Fiber: ${parsedData.fiber || 0} g`);
            console.log(`  Cholesterol: ${parsedData.cholesterol || 0} mg`);
            console.log(`  Sugar: ${parsedData.sugar || 0} g`);
            console.log(`  Saturated Fats: ${parsedData.saturated_fats || 0} g`);
            console.log(`  Omega-3: ${parsedData.omega_3 || 0} mg`);
            console.log(`  Omega-6: ${parsedData.omega_6 || 0} mg`);
            
            if (parsedData.ingredients && parsedData.ingredients.length > 0) {
              console.log('\n🔬 INGREDIENT BREAKDOWN:');
              parsedData.ingredients.forEach((ingredient, index) => {
                console.log(`  ${index + 1}. ${ingredient.name || ingredient} (${ingredient.amount || 'N/A'})`);
                console.log(`     Calories: ${ingredient.calories || 0}, Protein: ${ingredient.protein || 0}g, Fat: ${ingredient.fat || 0}g, Carbs: ${ingredient.carbs || 0}g`);
              });
            }
            
            console.log('🔬 ============================================\n');
          }
          
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
      max_tokens: 1500,
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