// Simplified server for Render.com deployment
require('dotenv').config();
const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 10000;

// Middleware
app.use(cors({ origin: '*' }));
app.use(express.json({ limit: '50mb' }));

// Health check
app.get('/', (req, res) => {
  res.json({
    message: 'Food Analyzer API - Lightning Fast Mode',
    status: 'operational',
    version: '2.0.0-lightning'
  });
});

// Warmup endpoint
app.get('/api/warmup', (req, res) => {
  console.log('🔥 Warmup request received');
  res.json({
    status: 'success',
    message: 'Server warmed up',
    timestamp: new Date().toISOString()
  });
});

// Main analyze endpoint - WORKING with real OpenAI
app.post('/api/analyze-food', async (req, res) => {
  try {
    console.log('🔥 WORKING Analyze endpoint called');
    const { image, lightning_fast, ultra_fast, fast_mode } = req.body;

    if (!image) {
      return res.status(400).json({
        success: false,
        error: 'Image required'
      });
    }

    if (!process.env.OPENAI_API_KEY) {
      return res.status(500).json({
        success: false,
        error: 'OpenAI API key not configured'
      });
    }

    console.log('⚡ Processing with lightning mode:', !!lightning_fast);

    // REAL OpenAI call with optimized settings
    const fetch = require('node-fetch');
    
    const systemPrompt = `Analyze this food image and return a JSON object with this exact structure:
{
  "ingredients": [
    {
      "name": "food name",
      "weight_g": number,
      "kcal": number,
      "protein_g": number,
      "fat_g": number,
      "carbs_g": number
    }
  ]
}

Identify ALL visible food items accurately. Estimate realistic serving sizes.`;

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        temperature: 0.1,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content: systemPrompt
          },
          {
            role: "user",
            content: [
              { 
                type: "text", 
                text: "Analyze this food image accurately and identify all visible items."
              },
              { 
                type: "image_url", 
                image_url: { 
                  url: image,
                  detail: "high"
                } 
              }
            ]
          }
        ],
        max_tokens: 1200
      })
    });

    if (!response.ok) {
      throw new Error(`OpenAI API error: ${response.status}`);
    }

    const result = await response.json();
    const content = result.choices[0].message.content;
    const jsonResponse = JSON.parse(content);

    console.log('✅ OpenAI analysis complete');

    res.json({
      success: true,
      data: jsonResponse
    });

  } catch (error) {
    console.error('❌ Error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

app.listen(PORT, () => {
  console.log(`🚀 Lightning-Fast API server running on port ${PORT}`);
  console.log(`🔥 OpenAI API Key: ${process.env.OPENAI_API_KEY ? 'Present' : 'Missing'}`);
});

module.exports = app;
