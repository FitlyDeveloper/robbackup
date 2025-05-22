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
    
    // Check if the image size is too large for the OpenAI API
    if (image.length > 500000) {
      console.log('Image is too large, size:', image.length, 'bytes. Applying aggressive compression...');
      
      try {
        // Extract the MIME type and base64 data
        const parts = image.split(',');
        const mimeType = parts[0];
        const base64Data = parts[1] || '';
        
        // Calculate target size based on original size
        // The bigger the image, the more aggressive the compression
        const targetSize = Math.min(400000, 600000000 / image.length);
        console.log(`Target size for compressed image: ${targetSize} bytes`);
        
        // Calculate how much to keep from the original image
        const keepRatio = targetSize / (image.length || 1);
        const keepLength = Math.floor(base64Data.length * keepRatio);
        
        // Build a compressed image with truncated data
        // This is a very crude but effective way to reduce tokens
        let compressedImage;
        if (keepLength < base64Data.length) {
          compressedImage = `${mimeType},${base64Data.substring(0, keepLength)}`;
          console.log(`Compressed image by truncating to ${keepLength} chars`);
        } else {
          // If the calculation suggests we keep everything, still cap at 400K
          const maxLength = 400000;
          compressedImage = image.length > maxLength ? 
            `${mimeType},${base64Data.substring(0, maxLength)}` : image;
        }
        
        console.log('Original length:', image.length, 'Compressed length:', compressedImage.length);
        console.log('Compression ratio:', (compressedImage.length / image.length).toFixed(2));
        
        // Replace the image data with the compressed version
        image = compressedImage;
      } catch (error) {
        console.error('Error during aggressive compression:', error);
        // Fallback to simpler truncation method
        const maxLength = 400000;
        image = image.length > maxLength ? image.substring(0, maxLength) : image;
        console.log('Fallback compression applied, new length:', image.length);
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
        error: `