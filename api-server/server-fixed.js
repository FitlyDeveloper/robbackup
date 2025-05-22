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
    const { image: originalImage } = req.body;

    if (!originalImage) {
      console.error('No image provided in request');
      return res.status(400).json({
        success: false,
        error: 'Image data is required'
      });
    }

    // Debug logging
    console.log('Received image data, length:', originalImage.length);
    console.log('Image data starts with:', originalImage.substring(0, 50));
    
    // Create a mutable copy of the image data that we can modify
    let processedImage = originalImage;
    
    // Check if the image size is too large for the OpenAI API
    if (processedImage.length > 500000) {
      console.log('Image is too large, size:', processedImage.length, 'bytes. Applying compression...');
      
      try {
        // Extract the MIME type and base64 data
        const parts = processedImage.split(',');
        const mimeType = parts[0];
        const base64Data = parts[1] || '';
        
        // Set reasonable minimum and maximum sizes
        const MIN_SIZE = 200000; // 200KB minimum
        const MAX_SIZE = 400000; // 400KB maximum
        
        // Calculate target size - larger images get more compression
        let targetSize;
        if (processedImage.length > 1000000) {
          // Very large images (>1MB) get compressed to 300KB
          targetSize = 300000;
        } else {
          // Images between 500KB-1MB get compressed to 400KB
          targetSize = MAX_SIZE;
        }
        
        console.log(`Target size for compressed image: ${targetSize} bytes`);
        
        // Calculate how much to keep
        const keepRatio = targetSize / processedImage.length;
        const keepLength = Math.max(MIN_SIZE, Math.floor(base64Data.length * keepRatio));
        
        console.log(`Will keep ${keepLength} characters of base64 data`);
        
        // Build a compressed image with truncated data
        const compressedImage = `${mimeType},${base64Data.substring(0, keepLength)}`;
        console.log(`Compressed image from ${processedImage.length} to ${compressedImage.length} bytes`);
        
        // Replace the image data with the compressed version
        processedImage = compressedImage;
      } catch (error) {
        console.error('Error during compression:', error);
        
        // Simple fallback approach if the main approach fails
        const MIN_SIZE = 200000;
        const MAX_SIZE = 400000;
        
        if (processedImage.length > MAX_SIZE) {
          // Extract parts and truncate to 400KB
          try {
            const parts = processedImage.split(',');
            if (parts.length >= 2) {
              const mimeType = parts[0];
              const base64Data = parts[1];
              processedImage = `${mimeType},${base64Data.substring(0, MAX_SIZE)}`;
            } else {
              // Simple truncation if split fails
              processedImage = processedImage.substring(0, MAX_SIZE);
            }
          } catch (e) {
            // Last resort - simple truncation
            processedImage = processedImage.substring(0, MAX_SIZE);
          }
          console.log('Fallback compression applied, new length:', processedImage.length);
        } else {
          console.log('Image already within size limits:', processedImage.length);
        }
      }
    }
    
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
            content: `Analyze the nutritional content of this food image. Provide a comprehensive breakdown with all macronutrients and micronutrients. The image data is: ${processedImage}`
          }
        ],
        max_tokens: 4000,
        response_format: { type: 'json_object' }
      })
    });

    if (!response.ok) {
      const errorData = await response.text();
      console.error('OpenAI API error:', response.status, errorData);
      
      // Handle rate limit errors specifically
      if (response.status === 429) {
        try {
          const errorObj = JSON.parse(errorData);
          const errorMessage = errorObj.error && errorObj.error.message ? errorObj.error.message : 'Rate limit exceeded';
          
          // Check if it's a token-related error
          if (errorMessage.includes('tokens per min') || errorMessage.includes('Request too large')) {
            console.error('Token rate limit error detected. Image may be too large or complex.');
            
            return res.status(413).json({
              success: false,
              error: 'Image is too large or complex for analysis. Please try with a smaller or simpler image.',
              details: 'The AI model has reached its processing limits. Try a smaller, clearer image with less detail.'
            });
          }
          
          // Regular rate limit
          return res.status(429).json({
            success: false,
            error: 'Analysis service temporarily overloaded. Please try again in a few minutes.',
            details: errorMessage
          });
        } catch (parseError) {
          // Fallback if JSON parsing fails
          return res.status(429).json({
            success: false,
            error: 'Rate limit exceeded. Please try again later.',
            details: errorData
          });
        }
      }
      
      return res.status(response.status).json({
        success: false,
        error: `OpenAI API error: ${response.status}`
      });
    }

    // Process the response
    const responseData = await response.json();
    return res.json({
      success: true,
      data: responseData
    });
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
  console.log(`Server running on port ${PORT}`);
});