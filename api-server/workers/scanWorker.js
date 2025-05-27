// Import required packages
require('dotenv').config();
const { Worker } = require('bullmq');
const Redis = require('ioredis');
const fetch = require('node-fetch');
const path = require('path');
const fs = require('fs');

// Create Redis connections
const redisConfig = {
  host: process.env.REDIS_HOST || 'localhost',
  port: process.env.REDIS_PORT || 6379,
  password: process.env.REDIS_PASSWORD,
};

// Create Redis client for job storage and status tracking
const redisClient = new Redis(redisConfig);

// Create token bucket for rate limiting
// OpenAI has a limit of 10,000 TPM per org by default
const TOKEN_BUCKET_KEY = 'token-bucket';
const MAX_TOKENS_PER_MINUTE = parseInt(process.env.MAX_TOKENS_PER_MINUTE, 10) || 30000;
const REFILL_RATE = MAX_TOKENS_PER_MINUTE / 60; // tokens per second
const IMAGE_TOKEN_COST_ESTIMATE = 300; // Base cost for image API calls (conservative estimate)
const MAX_RESPONSE_TOKENS = 4000; // Maximum response tokens
const SYSTEM_PROMPT_TOKENS = 300; // Estimated system prompt tokens
const USER_PROMPT_TOKENS = 100; // Estimated user prompt tokens (excluding image)

console.log(`Starting worker with token bucket rate limit: ${MAX_TOKENS_PER_MINUTE} tokens per minute`);
console.log(`Refill rate: ${REFILL_RATE.toFixed(2)} tokens per second`);

// Initialize token bucket if it doesn't exist
async function initializeTokenBucket() {
  const exists = await redisClient.exists(TOKEN_BUCKET_KEY);
  if (!exists) {
    console.log(`Initializing token bucket with ${MAX_TOKENS_PER_MINUTE} tokens`);
    await redisClient.set(TOKEN_BUCKET_KEY, MAX_TOKENS_PER_MINUTE);
  }
}

// Get tokens from the bucket
async function getTokens(tokensNeeded) {
  // Atomic Redis operations to check and take tokens if available
  const lua = `
    local current = tonumber(redis.call('get', KEYS[1])) or 0
    local tokensNeeded = tonumber(ARGV[1])
    
    if current >= tokensNeeded then
      redis.call('decrby', KEYS[1], tokensNeeded)
      return tokensNeeded
    else
      return 0
    end
  `;
  
  const result = await redisClient.eval(
    lua, 
    1, 
    TOKEN_BUCKET_KEY, 
    tokensNeeded.toString()
  );
  
  return parseInt(result, 10);
}

// Refill tokens in the bucket
async function refillTokens() {
  // Refill tokens every second
  setInterval(async () => {
    try {
      const lua = `
        local current = tonumber(redis.call('get', KEYS[1])) or 0
        local refillAmount = tonumber(ARGV[1])
        local maxTokens = tonumber(ARGV[2])
        
        local newAmount = math.min(current + refillAmount, maxTokens)
        redis.call('set', KEYS[1], newAmount)
        return newAmount
      `;
      
      await redisClient.eval(
        lua,
        1,
        TOKEN_BUCKET_KEY,
        REFILL_RATE.toString(),
        MAX_TOKENS_PER_MINUTE.toString()
      );
    } catch (error) {
      console.error('Error refilling token bucket:', error);
    }
  }, 1000);
}

// Compress image if needed
async function processImage(imageData) {
  try {
    // Parse base64 image data
    const parts = imageData.split(',');
    const mimeType = parts[0];
    const base64Data = parts[1] || '';
    
    // Check if the image size is too large
    const targetSizeBytes = 700 * 1024; // 700KB (0.7MB)
    
    if (imageData.length > targetSizeBytes) {
      console.log(`Image is too large (${Math.round(imageData.length/1024)}KB), compressing to 700KB...`);
      
      // Calculate how much to keep
      const keepRatio = targetSizeBytes / imageData.length;
      const keepLength = Math.floor(base64Data.length * keepRatio);
      
      // Build a compressed image with truncated data
      const compressedImage = `${mimeType},${base64Data.substring(0, keepLength)}`;
      console.log(`Compressed image from ${Math.round(imageData.length/1024)}KB to ${Math.round(compressedImage.length/1024)}KB (${(compressedImage.length / imageData.length * 100).toFixed(1)}%)`);
      
      return compressedImage;
    } else {
      console.log(`Image is already below 700KB (${Math.round(imageData.length/1024)}KB), no compression needed`);
      return imageData;
    }
  } catch (error) {
    console.error('Error processing image:', error);
    return imageData; // Return original on error
  }
}

// Call OpenAI API with retries and rate limiting
async function callOpenAI(processedImage) {
  // Shortened system prompt to reduce token usage
  const shorterSystemPrompt = '[JSON ONLY] Nutrition expert: Analyze food image and provide JSON with meal_name, ingredients (with weights and calories), and ingredient_nutrients arrays. Each ingredient_nutrient must include: ingredient_name_ref (matching ingredients array), calories, macros (protein, fat, carbs in g), vitamins (a,c,d,e,k,b1-b12 in mg), minerals (ca,fe,mg,p,k,na,zn,cu,mn,se,i,cr,mo,f,cl in mg), and other nutrients (fiber, cholesterol, sugar, saturated_fats, omega_3, omega_6). Format ALL values with exactly one decimal point.';

  // Estimate tokens for this request (image + prompts + expected response)
  const imageSize = processedImage.length;
  const imageSizeKB = Math.round(imageSize / 1024);
  
  // Conservative token estimate based on image size
  const estimatedImageTokens = Math.min(Math.max(IMAGE_TOKEN_COST_ESTIMATE, imageSizeKB / 4), 4000);
  const totalTokensNeeded = estimatedImageTokens + SYSTEM_PROMPT_TOKENS + USER_PROMPT_TOKENS + MAX_RESPONSE_TOKENS;
  
  console.log(`Estimated tokens needed for request: ${totalTokensNeeded} (image: ~${estimatedImageTokens}, system: ${SYSTEM_PROMPT_TOKENS}, user: ${USER_PROMPT_TOKENS}, response: ${MAX_RESPONSE_TOKENS})`);
  
  // Try to get tokens from the bucket
  let tokensReceived = 0;
  let waitTime = 1000; // start with 1 second
  let maxRetries = 12; // maximum number of retries (12 attempts = ~1 minute max wait)
  let attempts = 0;

  while (tokensReceived === 0 && attempts < maxRetries) {
    attempts++;
    tokensReceived = await getTokens(totalTokensNeeded);
    
    if (tokensReceived === 0) {
      console.log(`Insufficient tokens in bucket, waiting ${waitTime/1000}s before retry (attempt ${attempts}/${maxRetries})`);
      await new Promise(resolve => setTimeout(resolve, waitTime));
      waitTime = Math.min(waitTime * 1.5, 10000); // exponential backoff up to 10 seconds
    }
  }
  
  if (tokensReceived === 0) {
    throw new Error('Rate limit exceeded: Could not acquire enough tokens after multiple retries');
  }

  console.log(`Acquired ${tokensReceived} tokens from bucket, calling OpenAI API...`);

  // Make the API call with retry logic for 429 errors
  let openAIAttempts = 0;
  const maxOpenAIRetries = 3;
  let openAIWaitTime = 2000;
  
  while (openAIAttempts < maxOpenAIRetries) {
    openAIAttempts++;
    
    try {
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
          max_tokens: MAX_RESPONSE_TOKENS,
          response_format: { type: 'json_object' }
        })
      });

      if (response.ok) {
        const data = await response.json();
        // Extract and parse content
        const content = data.choices[0].message.content;
        return JSON.parse(content);
      } else {
        const errorData = await response.text();
        
        // Check for rate limit errors
        if (response.status === 429) {
          if (openAIAttempts < maxOpenAIRetries) {
            console.error(`OpenAI rate limit error, retrying in ${openAIWaitTime/1000}s...`);
            await new Promise(resolve => setTimeout(resolve, openAIWaitTime));
            openAIWaitTime *= 2; // exponential backoff
            continue;
          }
        }
        
        throw new Error(`OpenAI API error: ${response.status}, ${errorData}`);
      }
    } catch (error) {
      if (openAIAttempts < maxOpenAIRetries && error.message.includes('429')) {
        console.error(`OpenAI request failed with rate limit error, retrying in ${openAIWaitTime/1000}s...`);
        await new Promise(resolve => setTimeout(resolve, openAIWaitTime));
        openAIWaitTime *= 2; // exponential backoff
      } else {
        throw error;
      }
    }
  }
  
  throw new Error('Failed to get response from OpenAI after multiple retries');
}

// Main worker function
async function startWorker() {
  // Initialize token bucket
  await initializeTokenBucket();
  
  // Start token refill process
  refillTokens();
  
  // Create BullMQ worker
  const worker = new Worker('food-scan-queue', async job => {
    const { jobId, userId, image, isLegacy = false } = job.data;
    console.log(`Processing job ${jobId} for user ${userId}`);
    
    try {
      // Update job status
      await redisClient.hset(`job:${jobId}`, {
        status: 'processing',
        startedAt: Date.now(),
        progress: 10,
        message: 'Processing image...'
      });
      
      // Process and compress the image if needed
      const processedImage = await processImage(image);
      
      // Update progress
      await redisClient.hset(`job:${jobId}`, {
        progress: 30,
        message: 'Image processed, waiting for analysis...'
      });
      
      // Call OpenAI API with rate limiting
      const analysisResult = await callOpenAI(processedImage);
      
      // Update progress
      await redisClient.hset(`job:${jobId}`, {
        progress: 90,
        message: 'Analysis complete, saving results...'
      });
      
      // Store the result in Redis
      await redisClient.set(`result:${jobId}`, JSON.stringify(analysisResult));
      
      // Mark job as completed
      await redisClient.hset(`job:${jobId}`, {
        status: 'completed',
        completedAt: Date.now(),
        progress: 100,
        message: 'Analysis complete'
      });
      
      console.log(`Job ${jobId} completed successfully`);
      return { success: true, jobId };
    } catch (error) {
      console.error(`Error processing job ${jobId}:`, error);
      
      // Store error in Redis
      await redisClient.hset(`job:${jobId}`, {
        status: 'failed',
        error: error.message,
        failedAt: Date.now()
      });
      
      throw error;
    }
  }, { 
    connection: redisConfig,
    concurrency: 5 // Process up to 5 jobs concurrently
  });
  
  worker.on('completed', job => {
    console.log(`Job ${job.data.jobId} completed successfully`);
  });
  
  worker.on('failed', (job, err) => {
    console.error(`Job ${job.data.jobId} failed with error:`, err);
  });
  
  console.log('Worker started and ready to process jobs');
}

// Start the worker
startWorker().catch(error => {
  console.error('Failed to start worker:', error);
  process.exit(1);
}); 