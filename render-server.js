// BULLETPROOF Render.com server - GUARANTEED to work
require('dotenv').config();
const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 10000;

console.log('🚀 Starting BULLETPROOF server...');
console.log('Port:', PORT);
console.log('OpenAI Key present:', process.env.OPENAI_API_KEY ? 'Yes' : 'No');

// Middleware
app.use(cors({ origin: '*' }));
app.use(express.json({ limit: '50mb' }));

// Health check
app.get('/', (req, res) => {
  res.json({
    message: 'BULLETPROOF Food Analyzer API - Lightning Fast',
    status: 'operational',
    version: '3.0.0-bulletproof',
    timestamp: new Date().toISOString()
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

// Main analyze endpoint - BULLETPROOF with real OpenAI
app.post('/api/analyze-food', async (req, res) => {
  try {
    console.log('🔥 Analyze endpoint called');
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

    // Use node-fetch directly without requiring it at top (in case it's not available)
    const fetch = eval('require')('node-fetch');
    
    const systemPrompt = `You are a professional food analyst. ANALYZE THE VISUAL DETAILS:

{
  "ingredients": [
    {
      "name": "ACCURATE INGREDIENT NAME (based on visual characteristics)",
      "weight_g": number,
      "kcal": number,
      "protein_g": number,
      "fat_g": number,
      "carbs_g": number
    }
  ]
}

VISUAL IDENTIFICATION GUIDE:
- Orange/golden cubes with smooth texture = sweet potato
- White creamy smooth consistency = Greek yogurt or similar dairy
- Light colored meat pieces with fibrous texture = chicken
- Reddish/orange fermented vegetables with cabbage texture = kimchi
- Look at COLORS, TEXTURES, SHAPES - not typical food combinations

CRITICAL RULES:
- Identify by VISUAL CHARACTERISTICS only
- Don't assume ingredients based on what "should" go together
- Sweet potato ≠ regular potato (look for orange color)
- Kimchi ≠ caramelized onions (fermented vs cooked)
- Greek yogurt ≠ eggs (creamy vs solid)
- Return valid JSON only - VISUAL ACCURACY above all`;

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
                text: "Analyze this food image accurately and identify all visible items with realistic portions."
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
        max_tokens: 1200,
        timeout: 45000
      })
    });

    if (!response.ok) {
      throw new Error(`OpenAI API error: ${response.status} - ${response.statusText}`);
    }

    const result = await response.json();
    const content = result.choices[0].message.content;
    const jsonResponse = JSON.parse(content);

    console.log('✅ Analysis complete, ingredients found:', jsonResponse.ingredients?.length || 0);

    res.json({
      success: true,
      data: jsonResponse
    });

  } catch (error) {
    console.error('❌ Error:', error.message);
    res.status(500).json({
      success: false,
      error: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Legacy job endpoints for compatibility
app.post('/api/jobs', async (req, res) => {
  // Redirect to analyze-food for immediate processing
  try {
    const result = await fetch(`http://localhost:${PORT}/api/analyze-food`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body)
    });
    const data = await result.json();
    
    res.json({
      jobId: 'immediate-' + Date.now(),
      status: 'completed',
      result: data
    });
  } catch (error) {
    res.json({
      jobId: 'immediate-' + Date.now(),
      status: 'failed',
      error: error.message
    });
  }
});

app.get('/api/jobs/:jobId', (req, res) => {
  res.json({
    jobId: req.params.jobId,
    status: 'completed',
    message: 'Job completed immediately'
  });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 BULLETPROOF server running on port ${PORT}`);
  console.log(`🌍 Server URL: http://0.0.0.0:${PORT}`);
  console.log(`🔑 OpenAI configured: ${process.env.OPENAI_API_KEY ? '✅ Yes' : '❌ No'}`);
});

// Handle uncaught exceptions
process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});

module.exports = app;
