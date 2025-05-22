// Import required packages
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const fetch = require('node-fetch');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs');
const path = require('path');

// Create Express app
const app = express();
const PORT = process.env.PORT || 10000;

// Create jobs directory if it doesn't exist
const JOBS_DIR = path.join(__dirname, 'jobs');
if (!fs.existsSync(JOBS_DIR)) {
  fs.mkdirSync(JOBS_DIR, { recursive: true });
}

// Simple in-memory job queue (for demonstration)
const pendingJobs = {};
const activeJobs = {};
const completedJobs = {};
const failedJobs = {};

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

// Helper function to update job status
async function updateJobStatus(jobId, updates) {
  const jobFile = path.join(JOBS_DIR, `${jobId}.json`);
  let jobData = {};
  
  // Read existing job data if it exists
  if (fs.existsSync(jobFile)) {
    try {
      const data = fs.readFileSync(jobFile, 'utf8');
      jobData = JSON.parse(data);
    } catch (error) {
      console.error(`Error reading job file for ${jobId}:`, error);
    }
  }
  
  // Update job data
  jobData = { ...jobData, ...updates };
  
  // Write updated job data
  try {
    fs.writeFileSync(jobFile, JSON.stringify(jobData, null, 2));
  } catch (error) {
    console.error(`Error writing job file for ${jobId}:`, error);
  }
  
  return jobData;
}

// Helper function to get job status
function getJobStatus(jobId) {
  const jobFile = path.join(JOBS_DIR, `${jobId}.json`);
  
  // Check if job file exists
  if (!fs.existsSync(jobFile)) {
    return null;
  }
  
  // Read job data
  try {
    const data = fs.readFileSync(jobFile, 'utf8');
    return JSON.parse(data);
  } catch (error) {
    console.error(`Error reading job file for ${jobId}:`, error);
    return null;
  }
}

// Process image and analyze with OpenAI
async function processAndAnalyzeImage(jobId, userId, image) {
  try {
    // Update job status to processing
    await updateJobStatus(jobId, {
      status: 'processing',
      progress: 10,
      message: 'Processing image...'
    });
    
    // Create a mutable copy of the image data that we can modify
    let processedImage = image;

    // Check if the image size is too large
    if (processedImage.length > 700000) {
      console.log('Image is larger than 700KB, size:', processedImage.length, 'bytes. Applying compression...');
      
      try {
        // Extract the MIME type and base64 data
        const parts = processedImage.split(',');
        const mimeType = parts[0];
        const base64Data = parts[1] || '';
        
        // Target size is 700KB
        const targetSize = 700000;
        
        console.log(`Target size for compressed image: ${targetSize} bytes`);
        
        // Calculate how much to keep
        const keepRatio = targetSize / processedImage.length;
        const keepLength = Math.floor(base64Data.length * keepRatio);
        
        console.log(`Will keep ${keepLength} characters of base64 data (ratio: ${keepRatio.toFixed(4)})`);
        
        // Build a compressed image with truncated data
        const compressedImage = `${mimeType},${base64Data.substring(0, keepLength)}`;
        console.log(`Compressed image from ${processedImage.length} to ${compressedImage.length} bytes (${(compressedImage.length / processedImage.length * 100).toFixed(1)}%)`);
        
        // Replace the image data with the compressed version
        processedImage = compressedImage;
      } catch (error) {
        console.error('Error during compression:', error);
      }
    }
    
    // Update progress
    await updateJobStatus(jobId, {
      progress: 30,
      message: 'Image processed, calling OpenAI API...'
    });

    // Shortened system prompt to reduce token usage
    const shorterSystemPrompt = '[JSON ONLY] Nutrition expert: Analyze food image and provide JSON with meal_name, ingredients (with weights and calories), and ingredient_nutrients arrays. Each ingredient_nutrient must include: ingredient_name_ref (matching ingredients array), calories, macros (protein, fat, carbs in g), vitamins (a,c,d,e,k,b1-b12 in mg), minerals (ca,fe,mg,p,k,na,zn,cu,mn,se,i,cr,mo,f,cl in mg), and other nutrients (fiber, cholesterol, sugar, saturated_fats, omega_3, omega_6). Format ALL values with exactly one decimal point.';

    // Call OpenAI API
    console.log('Calling OpenAI API for job', jobId);
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
            content: shorterSystemPrompt
          },
          {
            role: 'user',
            content: `Analyze this food image and provide nutritional breakdown: ${processedImage}`
          }
        ],
        max_tokens: 4000,
        response_format: { type: 'json_object' }
      })
    });

    if (!response.ok) {
      const errorData = await response.text();
      console.error('OpenAI API error:', response.status, errorData);
      
      let errorMessage = 'API error';
      try {
        const errorObj = JSON.parse(errorData);
        errorMessage = errorObj.error && errorObj.error.message ? errorObj.error.message : 'API error';
      } catch (e) {
        errorMessage = errorData;
      }
      
      await updateJobStatus(jobId, {
        status: 'failed',
        error: errorMessage,
        failedAt: Date.now()
      });
      
      return;
    }

    // Parse the response
    const responseData = await response.json();
    const content = responseData.choices[0].message.content;
    const result = JSON.parse(content);
    
    // Update progress and store result
    await updateJobStatus(jobId, {
      status: 'completed',
      progress: 100,
      message: 'Analysis complete',
      completedAt: Date.now(),
      result
    });
    
    console.log(`Job ${jobId} completed successfully`);
  } catch (error) {
    console.error(`Error processing job ${jobId}:`, error);
    
    // Store error in job status
    await updateJobStatus(jobId, {
      status: 'failed',
      error: error.message,
      failedAt: Date.now()
    });
  }
}

// Define routes
app.get('/', (req, res) => {
  console.log('Health check endpoint called');
  res.json({
    message: 'Food Analyzer API Server',
    status: 'operational'
  });
});

// NEW JOB SUBMISSION ENDPOINT
app.post('/api/jobs', limiter, checkApiKey, async (req, res) => {
  try {
    console.log('Job submission endpoint called');
    const { image: originalImage, userId = 'anonymous' } = req.body;

    if (!originalImage) {
      console.error('No image provided in request');
      return res.status(400).json({
        success: false,
        error: 'Image data is required'
      });
    }

    // Generate unique job ID
    const jobId = uuidv4();
    console.log(`Creating new job ${jobId} for user ${userId}`);

    // Create initial job status
    await updateJobStatus(jobId, {
      status: 'pending',
      createdAt: Date.now(),
      userId,
      progress: 0,
    });

    // Process job in background (non-blocking)
    processAndAnalyzeImage(jobId, userId, originalImage).catch(console.error);

    // Return job ID immediately
    return res.status(201).json({
      success: true,
      jobId,
      status: 'pending'
    });
  } catch (error) {
    console.error('Job submission error:', error.message, error.stack);
    return res.status(500).json({
      success: false,
      error: `Server error: ${error.message}`
    });
  }
});

// JOB STATUS ENDPOINT
app.get('/api/jobs/:jobId', async (req, res) => {
  try {
    const { jobId } = req.params;
    console.log(`Checking status for job ${jobId}`);

    // Get job status
    const jobData = getJobStatus(jobId);

    if (!jobData) {
      return res.status(404).json({
        success: false,
        error: 'Job not found'
      });
    }

    // If job is completed, include results
    if (jobData.status === 'completed') {
      if (jobData.result) {
        return res.json({
          success: true,
          status: jobData.status,
          progress: 100,
          createdAt: jobData.createdAt,
          completedAt: jobData.completedAt || Date.now(),
          data: jobData.result
        });
      } else {
        // Job marked as completed but no result found
        return res.json({
          success: true,
          status: 'error',
          error: 'Result data not found'
        });
      }
    }

    // For non-completed jobs, return status info
    return res.json({
      success: true,
      status: jobData.status,
      progress: jobData.progress || 0,
      createdAt: jobData.createdAt,
      message: jobData.message || null,
      error: jobData.error
    });
  } catch (error) {
    console.error('Job status error:', error.message);
    return res.status(500).json({
      success: false,
      error: `Server error: ${error.message}`
    });
  }
});

// OpenAI proxy endpoint for food analysis (legacy endpoint)
app.post('/api/analyze-food', limiter, checkApiKey, async (req, res) => {
  try {
    console.log('Legacy analyze food endpoint called - redirecting to job queue');
    const { image: originalImage } = req.body;

    if (!originalImage) {
      console.error('No image provided in request');
      return res.status(400).json({
        success: false,
        error: 'Image data is required'
      });
    }

    // Generate job ID
    const jobId = uuidv4();
    console.log(`Creating legacy job ${jobId}`);

    // Create initial job status
    await updateJobStatus(jobId, {
      status: 'pending',
      createdAt: Date.now(),
      userId: 'legacy-api',
      progress: 0,
    });

    // Start processing the job
    processAndAnalyzeImage(jobId, 'legacy-api', originalImage).catch(console.error);

    // For legacy endpoint, wait for job completion with timeout
    let attempts = 0;
    const maxAttempts = 60; // 30 seconds with 500ms interval
    
    while (attempts < maxAttempts) {
      attempts++;
      await new Promise(resolve => setTimeout(resolve, 500));
      
      // Check job status
      const jobData = getJobStatus(jobId);
      
      if (jobData && jobData.status === 'completed') {
        if (jobData.result) {
          return res.json({
            success: true,
            data: jobData.result
          });
        }
        break;
      } else if (jobData && jobData.status === 'failed') {
        return res.status(500).json({
          success: false,
          error: jobData.error || 'Job processing failed'
        });
      }
    }
    
    // If we get here, the job hasn't completed in the timeout period
    return res.status(202).json({
      success: true,
      message: 'Job processing in progress',
      jobId
    });
  } catch (error) {
    console.error('Server error:', error.message, error.stack);
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