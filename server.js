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
              text: `Please analyze this food image and return a JSON object with complete nutritional information. Use REALISTIC nutritional values based on USDA nutritional database standards.\n\nIMPORTANT NUTRITIONAL GUIDELINES:\n- Vitamin A: Most foods contain 0-200 mcg (not mg!), fruits typically 5-50 mcg\n- Vitamin C: Fruits 10-90mg, vegetables 5-120mg, meats 0-5mg\n- Vitamin D: Most foods contain 0-10 mcg, very few natural sources\n- B vitamins: Usually 0.1-5mg each, B12 mostly in animal products\n- Minerals: Calcium 10-300mg, Iron 0.5-18mg, Potassium 100-800mg\n- Fiber: Fruits 1-10g, vegetables 2-15g, grains 3-25g\n- Omega-6: Most foods 0.1-2g, nuts/oils higher\n\nProvide realistic portion sizes (50-200g typically) and ensure nutritional values match actual food composition.\n\nReturn JSON with this EXACT structure:\n{\n  "meal_name": "Food Name",\n  "ingredients": ["Grilled Chicken (150g) 248kcal", "Mixed Salad (45g) 12kcal"],\n  "calories": "416",\n  "protein": "35",\n  "fat": "8", \n  "carbs": "45",\n  "vitamin_a": "50",\n  "vitamin_c": "30",\n  "vitamin_d": "2",\n  "vitamin_e": "5",\n  "vitamin_k": "15",\n  "vitamin_b1": "0.8",\n  "vitamin_b2": "0.6",\n  "vitamin_b3": "8",\n  "vitamin_b5": "3",\n  "vitamin_b6": "1",\n  "vitamin_b7": "20",\n  "vitamin_b9": "150",\n  "vitamin_b12": "1",\n  "calcium": "200",\n  "chloride": "300",\n  "chromium": "5",\n  "copper": "200",\n  "fluoride": "0.5",\n  "iodine": "20",\n  "iron": "3",\n  "magnesium": "80",\n  "manganese": "1",\n  "molybdenum": "10",\n  "phosphorus": "150",\n  "potassium": "400",\n  "selenium": "15",\n  "sodium": "500",\n  "zinc": "2",\n  "fiber": "8",\n  "cholesterol": "50",\n  "sugar": "20",\n  "saturated_fats": "4",\n  "omega_3": "200",\n  "omega_6": "1",\n  "health_score": "7/10"\n}\n\nEnsure all values are nutritionally accurate for the actual foods shown. Use this exact flat structure - do NOT nest ingredients as objects.`
            },
            {
              type: 'image_url',
              image_url: { url: image }
            }
          ]
        }
      ],
      max_tokens: 2000,
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
        console.log(`🍽️ Total Calories: ${parsedData.calories || parsedData.total_calories || 0}`);
        console.log(`🥩 Protein: ${parsedData.protein || parsedData.total_protein || 0}g`);
        console.log(`🧈 Fat: ${parsedData.fat || parsedData.total_fat || 0}g`);
        console.log(`🍞 Carbs: ${parsedData.carbs || parsedData.total_carbs || 0}g`);
        
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
            // Handle both string and object ingredient formats
            let name, amount, calories, protein, fat, carbs;
            
            if (typeof ingredient === 'string') {
              name = ingredient;
              amount = 'N/A';
              calories = protein = fat = carbs = 0;
            } else {
              name = ingredient.name || `Ingredient ${index + 1}`;
              amount = ingredient.amount || ingredient.weight_g ? `${ingredient.weight_g}g` : 'N/A';
              calories = ingredient.calories || 0;
              protein = ingredient.protein || ingredient.protein_g || 0;
              fat = ingredient.fat || ingredient.fat_g || 0;
              carbs = ingredient.carbs || ingredient.carbs_g || 0;
            }
            
            console.log(`  ${index + 1}. ${name} (${amount})`);
            console.log(`     Calories: ${calories}, Protein: ${protein}g, Fat: ${fat}g, Carbs: ${carbs}g`);
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
            console.log(`🍽️ Total Calories: ${parsedData.calories || parsedData.total_calories || 0}`);
            console.log(`🥩 Protein: ${parsedData.protein || parsedData.total_protein || 0}g`);
            console.log(`🧈 Fat: ${parsedData.fat || parsedData.total_fat || 0}g`);
            console.log(`🍞 Carbs: ${parsedData.carbs || parsedData.total_carbs || 0}g`);
            
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
                // Handle both string and object ingredient formats
                let name, amount, calories, protein, fat, carbs;
                
                if (typeof ingredient === 'string') {
                  name = ingredient;
                  amount = 'N/A';
                  calories = protein = fat = carbs = 0;
                } else {
                  name = ingredient.name || `Ingredient ${index + 1}`;
                  amount = ingredient.amount || ingredient.weight_g ? `${ingredient.weight_g}g` : 'N/A';
                  calories = ingredient.calories || 0;
                  protein = ingredient.protein || ingredient.protein_g || 0;
                  fat = ingredient.fat || ingredient.fat_g || 0;
                  carbs = ingredient.carbs || ingredient.carbs_g || 0;
                }
                
                console.log(`  ${index + 1}. ${name} (${amount})`);
                console.log(`     Calories: ${calories}, Protein: ${protein}g, Fat: ${fat}g, Carbs: ${carbs}g`);
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
      max_tokens: 2000,
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