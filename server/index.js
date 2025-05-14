const express = require('express');
const axios = require('axios');
const cors = require('cors');
const app = express();
const port = process.env.PORT || 3000;

app.use(express.json());
app.use(cors());

// Root route for simple health check
app.get('/', (req, res) => {
  res.json({
    "message": "Food Analyzer API Server",
    "status": "operational"
  });
});

// API endpoint for food fixing
app.post('/api/fix-food', async (req, res) => {
  try {
    const { query, instructions, operation_type, food_data } = req.body;
    
    console.log('Received fix-food request:', JSON.stringify(req.body, null, 2));
    
    // Create a comprehensive prompt for DeepSeek
    let prompt = "Analyze and modify the following food based on instructions:\n\n";
    
    if (food_data) {
      prompt += `Food: ${food_data.name || 'Unknown'}\n`;
      prompt += `Total calories: ${food_data.calories || '0'}\n`;
      prompt += `Total protein: ${food_data.protein || '0'}\n`;
      prompt += `Total fat: ${food_data.fat || '0'}\n`;
      prompt += `Total carbs: ${food_data.carbs || '0'}\n`;
      
      if (food_data.ingredients && Array.isArray(food_data.ingredients)) {
        prompt += "Ingredients:\n";
        food_data.ingredients.forEach(ingredient => {
          prompt += `- ${ingredient.name} (${ingredient.amount}): ${ingredient.calories} calories, ${ingredient.protein}g protein, ${ingredient.fat}g fat, ${ingredient.carbs}g carbs\n`;
        });
      }
    }
    
    prompt += `\nInstruction: ${instructions || 'Analyze and improve this food. For each ingredient, estimate and return its calories, protein, fat, and carbs as accurately as possible, even if not present in the original data.'}\n`;
    if (operation_type) {
      prompt += `Operation type: ${operation_type}\n`;
    }
    
    prompt += "\nPlease respond with a valid JSON object using this structure:";
    prompt += `\n{\n  "name": "Updated Food Name",\n  "calories": 123,\n  "protein": 30,\n  "fat": 5,\n  "carbs": 20,\n  "ingredients": [\n    {\n      "name": "Ingredient 1",\n      "amount": "100g",\n      "calories": 100,\n      "protein": 10,\n      "fat": 2,\n      "carbs": 5\n    },\n    {\n      "name": "Ingredient 2",\n      "amount": "50g",\n      "calories": 50,\n      "protein": 5,\n      "fat": 1,\n      "carbs": 3\n    }\n  ]\n}`;
    
    console.log('Sending prompt to DeepSeek API:', prompt);
    
    // Call DeepSeek API
    const response = await axios.post(
      'https://api.deepseek.com/v1/chat/completions',
      {
        model: "deepseek-chat",
        messages: [
          {
            role: "system", 
            content: "You are a nutrition expert specialized in analyzing and improving food recipes. Always respond with valid JSON."
          },
          {
            role: "user", 
            content: prompt
          }
        ],
        temperature: 0.3,
        response_format: { type: "json_object" }
      },
      {
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${process.env.DEEPSEEK_API_KEY}`
        }
      }
    );
    
    // Return the content from DeepSeek API
    const resultContent = response.data.choices[0].message.content;
    console.log('Received response from DeepSeek:', resultContent.substring(0, 200) + '...');
    
    try {
      const parsedContent = JSON.parse(resultContent);
      console.log('Successfully parsed JSON response');
      res.json({
        success: true,
        data: parsedContent
      });
    } catch (parseError) {
      console.error('Error parsing JSON from DeepSeek:', parseError);
      // Try to extract JSON from the text if possible
      const jsonMatch = resultContent.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        try {
          const extractedJson = JSON.parse(jsonMatch[0]);
          console.log('Extracted JSON from response text');
          res.json({
            success: true,
            data: extractedJson
          });
        } catch (e) {
          res.status(500).json({
            success: false,
            error: `Error parsing JSON from response: ${parseError.message}`,
            rawContent: resultContent
          });
        }
      } else {
        res.status(500).json({
          success: false,
          error: `Error parsing JSON from response: ${parseError.message}`,
          rawContent: resultContent
        });
      }
    }
  } catch (error) {
    console.error('Error:', error.message);
    if (error.response) {
      console.error('Response data:', error.response.data);
      console.error('Response status:', error.response.status);
    }
    res.status(500).json({
      success: false,
      error: `Error processing request: ${error.message}`,
      details: error.response ? error.response.data : null
    });
  }
});

// API endpoint for nutrition calculation
app.post('/api/nutrition', async (req, res) => {
  try {
    const { food_name, serving_size, query, request_type, current_data, operation_type, instructions } = req.body;
    
    console.log('Received nutrition request:', JSON.stringify(req.body, null, 2));
    
    // Create a prompt for the nutrition calculation
    let prompt = "Calculate accurate nutrition values for the following food:";
    if (food_name) {
      prompt += `\nFood: ${food_name}`;
    }
    if (serving_size) {
      prompt += `\nServing size: ${serving_size}`;
    }
    
    // Handle complex food modification requests (compatibility with Flutter app)
    if (current_data) {
      prompt = "Analyze and modify the following food based on instructions:\n\n";
      
      prompt += `Food: ${food_name || 'Unknown'}\n`;
      
      if (current_data.calories) prompt += `Total calories: ${current_data.calories}\n`;
      if (current_data.protein) prompt += `Total protein: ${current_data.protein}\n`;
      if (current_data.fat) prompt += `Total fat: ${current_data.fat}\n`;
      if (current_data.carbs) prompt += `Total carbs: ${current_data.carbs}\n`;
      
      if (current_data.ingredients && Array.isArray(current_data.ingredients)) {
        prompt += "Ingredients:\n";
        current_data.ingredients.forEach(ingredient => {
          prompt += `- ${ingredient.name} (${ingredient.amount}): ${ingredient.calories} calories, ${ingredient.protein}g protein, ${ingredient.fat}g fat, ${ingredient.carbs}g carbs\n`;
        });
      }
      
      prompt += `\nInstruction: ${instructions || 'Analyze and improve this food'}\n`;
      if (operation_type) {
        prompt += `Operation type: ${operation_type}\n`;
      }
      
      prompt += "\nPlease respond with a valid JSON object using this structure:";
      prompt += `
{
  "name": "Updated Food Name",
  "calories": 123,
  "protein": 30,
  "fat": 5,
  "carbs": 20,
  "ingredients": [
    {
      "name": "Ingredient 1",
      "amount": "100g",
      "calories": 100,
      "protein": 10,
      "fat": 2,
      "carbs": 5
    },
    {
      "name": "Ingredient 2",
      "amount": "50g",
      "calories": 50,
      "protein": 5,
      "fat": 1,
      "carbs": 3
    }
  ]
}`;
    }
    else if (query) {
      prompt += `\nQuery: ${query}`;
      
      prompt += "\n\nPlease provide a valid JSON response with the following structure:";
      prompt += `
{
  "calories": 250,
  "protein": 20,
  "fat": 10, 
  "carbs": 15
}`;
    }
    
    console.log('Sending prompt to DeepSeek API:', prompt);
    
    // Call DeepSeek API
    const response = await axios.post(
      'https://api.deepseek.com/v1/chat/completions',
      {
        model: "deepseek-chat",
        messages: [
          {
            role: "system", 
            content: "You are a specialized nutrition calculator. Analyze food ingredients and provide accurate nutrition information in valid JSON format."
          },
          {
            role: "user", 
            content: prompt
          }
        ],
        temperature: 0.2,
        response_format: { type: "json_object" }
      },
      {
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${process.env.DEEPSEEK_API_KEY}`
        }
      }
    );
    
    // Return the content from DeepSeek API
    const resultContent = response.data.choices[0].message.content;
    console.log('Received response from DeepSeek:', resultContent.substring(0, 200) + '...');
    
    try {
      const parsedContent = JSON.parse(resultContent);
      console.log('Successfully parsed JSON response');
      res.json({
        success: true,
        data: parsedContent
      });
    } catch (parseError) {
      console.error('Error parsing JSON from DeepSeek:', parseError);
      // Try to extract JSON from the text if possible
      const jsonMatch = resultContent.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        try {
          const extractedJson = JSON.parse(jsonMatch[0]);
          console.log('Extracted JSON from response text');
          res.json({
            success: true,
            data: extractedJson
          });
        } catch (e) {
          res.status(500).json({
            success: false,
            error: `Error parsing JSON from response: ${parseError.message}`,
            rawContent: resultContent
          });
        }
      } else {
        res.status(500).json({
          success: false,
          error: `Error parsing JSON from response: ${parseError.message}`,
          rawContent: resultContent
        });
      }
    }
  } catch (error) {
    console.error('Error:', error.message);
    if (error.response) {
      console.error('Response data:', error.response.data);
      console.error('Response status:', error.response.status);
    }
    res.status(500).json({
      success: false,
      error: `Error processing request: ${error.message}`,
      details: error.response ? error.response.data : null
    });
  }
});

// Start the server
app.listen(port, () => {
  console.log(`Food Analyzer API Server listening on port ${port}`);
  console.log(`API key present: ${process.env.DEEPSEEK_API_KEY ? 'Yes' : 'No'}`);
}); 