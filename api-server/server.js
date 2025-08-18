require('dotenv').config();
const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs');
const path = require('path');
const fetch = require('node-fetch');

// Create Express app
const app = express();
const PORT = process.env.PORT || 10000;

// Ultra-fast response cache for similar images
const responseCache = new Map();
const CACHE_MAX_SIZE = 100;
const CACHE_DURATION = 10 * 60 * 1000; // 10 minutes

// Create jobs directory if it doesn't exist
const JOBS_DIR = path.join(__dirname, 'jobs');
if (!fs.existsSync(JOBS_DIR)) {
  fs.mkdirSync(JOBS_DIR, { recursive: true });
}

// Debug startup
console.log('Starting ULTRA RELIABLE server that uses real OpenAI...');
console.log('Node environment:', process.env.NODE_ENV);
console.log('Current directory:', process.cwd());
console.log('OpenAI API Key present:', process.env.OPENAI_API_KEY ? 'Yes' : 'No');

// Set trust proxy to fix the X-Forwarded-For warning
app.set('trust proxy', 1);

// Configure rate limiting
const limiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: process.env.RATE_LIMIT || 30, // Limit each IP to 30 requests per minute
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    status: 429,
    message: 'Too many requests, please try again later.'
  }
});

// Configure CORS
app.use(cors({
  origin: '*',
  methods: ['POST', 'GET', 'OPTIONS'],
  credentials: true
}));

// Body parser middleware
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));

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

// Convert flat nutrient structure from OpenAI to nested structure expected by app
function convertFlatNutrientsToNested(ingredients) {
  return ingredients.map(ingredient => {
    const converted = {
      name: ingredient.name,
      weight_g: ingredient.weight_g || 100,
      calories: ingredient.calories || 0,
      protein_g: ingredient.protein_g || 0,
      fat_g: ingredient.fat_g || 0,
      carbs_g: ingredient.carbs_g || 0,
      vitamins: {
        vitamin_A_mcg: ingredient.vitamin_A || 0,        // 0/700 mcg
        vitamin_C_mg: ingredient.vitamin_C || 0,         // 0/75 mg
        vitamin_D_mcg: ingredient.vitamin_D || 0,        // 0/15 mcg
        vitamin_E_mg: ingredient.vitamin_E || 0,         // 0/15 mg
        vitamin_K_mcg: ingredient.vitamin_K || 0,        // 0/90 mcg
        vitamin_B1_mg: ingredient.vitamin_B1 || 0,       // 0/1.1 mg
        vitamin_B2_mg: ingredient.vitamin_B2 || 0,       // 0/1.1 mg
        vitamin_B3_mg: ingredient.vitamin_B3 || 0,       // 0/14 mg
        vitamin_B5_mg: ingredient.vitamin_B5 || 0,       // 0/5 mg
        vitamin_B6_mg: ingredient.vitamin_B6 || 0,       // 0/1.3 mg
        vitamin_B7_mcg: ingredient.vitamin_B7 || 0,      // 0/30 mcg
        vitamin_B9_mcg: ingredient.vitamin_B9 || 0,      // 0/400 mcg
        vitamin_B12_mcg: ingredient.vitamin_B12 || 0     // 0/2.4 mcg
      },
      minerals: {
        calcium_mg: ingredient.calcium || 0,            // 0/1000 mg
        chloride_mg: ingredient.chloride || 0,          // 0/2300 mg
        chromium_mcg: ingredient.chromium || 0,         // 0/35 mcg
        copper_mcg: ingredient.copper || 0,             // 0/900 mcg
        fluoride_mg: ingredient.fluoride || 0,          // 0/4 mg
        iodine_mcg: ingredient.iodine || 0,             // 0/150 mcg
        iron_mg: ingredient.iron || 0,                  // 0/18 mg
        magnesium_mg: ingredient.magnesium || 0,        // 0/400 mg
        manganese_mg: ingredient.manganese || 0,        // 0/2.3 mg
        molybdenum_mcg: ingredient.molybdenum || 0,     // 0/45 mcg
        phosphorus_mg: ingredient.phosphorus || 0,      // 0/700 mg
        potassium_mg: ingredient.potassium || 0,        // 0/3500 mg
        selenium_mcg: ingredient.selenium || 0,         // 0/55 mcg
        sodium_mg: ingredient.sodium || 0,              // 0/2300 mg
        zinc_mg: ingredient.zinc || 0                   // 0/11 mg
      },
      other: {
        // Prefer unit-suffixed keys if model returned them; fallback to generic keys
        fiber_g: (ingredient.fiber_g ?? ingredient.fiber) || 0,                 // 0/30 g
        cholesterol_mg: (ingredient.cholesterol_mg ?? ingredient.cholesterol) || 0,    // 0/300 mg
        sugar_g: (ingredient.sugar_g ?? ingredient.sugar) || 0,                 // 0/100 g
        saturated_fats_g: (ingredient.saturated_fats_g ?? ingredient.saturated_fats) || 0, // 0/22 g
        omega_3_mg: (ingredient.omega_3_mg ?? ingredient.omega_3) || 0,            // 0/1500 mg
        omega_6_g: (ingredient.omega_6_g ?? ingredient.omega_6) || 0              // 0/14 g
      }
    };
    
    return converted;
  });
}

// Expand simple OpenAI response to include all 34 nutrients using real USDA nutritional knowledge
function expandToFullNutrients(simpleResponse) {
  console.log('🔬 Expanding nutrients for ingredients:', simpleResponse.ingredients.map(i => i.name));
  
  const expandedIngredients = simpleResponse.ingredients.map(ingredient => {
    const name = ingredient.name.toLowerCase();
    
    // Start with OpenAI's provided values
    const expanded = {
      name: ingredient.name,
      weight_g: ingredient.weight_g || 100,
      calories: ingredient.calories || 100,
      protein_g: ingredient.protein_g || 0,
      fat_g: ingredient.fat_g || 0,
      carbs_g: ingredient.carbs_g || 0
    };
    
    // CRITICAL FIX: Get USDA micronutrients per 100g, then scale for actual portion size
    const actualWeight = expanded.weight_g;
    const nutrients = getRealUSDANutrients(name, expanded.carbs_g, expanded.protein_g, expanded.fat_g);
    
    // Scale ALL micronutrients based on actual portion weight (USDA values are per 100g)
    const scalingFactor = actualWeight / 100.0;
    const scaledNutrients = {};
    
    Object.keys(nutrients).forEach(key => {
      scaledNutrients[key] = nutrients[key] * scalingFactor;
    });
    
    // Merge scaled nutrients into the expanded ingredient
    Object.assign(expanded, scaledNutrients);
    
    console.log(`✅ Expanded ${ingredient.name} (${actualWeight}g) with ${Object.keys(scaledNutrients).length} scaled micronutrients (factor: ${scalingFactor.toFixed(2)})`);
    return expanded;
  });
  
  return {
    ...simpleResponse,
    ingredients: expandedIngredients
  };
}

// Get real USDA nutritional values based on food type
function getRealUSDANutrients(foodName, carbs, protein, fat) {
  const nutrients = {
    // Initialize all 34 nutrients to 0
    vitamin_A: 0, vitamin_C: 0, vitamin_D: 0, vitamin_E: 0, vitamin_K: 0,
    vitamin_B1: 0, vitamin_B2: 0, vitamin_B3: 0, vitamin_B5: 0, vitamin_B6: 0,
    vitamin_B7: 0, vitamin_B9: 0, vitamin_B12: 0,
    calcium: 0, chloride: 0, chromium: 0, copper: 0, fluoride: 0, iodine: 0,
    iron: 0, magnesium: 0, manganese: 0, molybdenum: 0, phosphorus: 0,
    potassium: 0, selenium: 0, sodium: 0, zinc: 0,
    fiber: 0, cholesterol: 0, sugar: 0, saturated_fats: 0, omega_3: 0, omega_6: 0
  };
  
  // COMPREHENSIVE USDA FOOD DATABASE (per 100g)
  
  // FRUITS
  if (foodName.includes('pineapple')) {
    nutrients.vitamin_A = 3; nutrients.vitamin_C = 47.8; nutrients.vitamin_K = 0.7;
    nutrients.vitamin_B1 = 0.079; nutrients.vitamin_B6 = 0.112; nutrients.vitamin_B9 = 18;
    nutrients.calcium = 13; nutrients.iron = 0.29; nutrients.magnesium = 12;
    nutrients.phosphorus = 8; nutrients.potassium = 109; nutrients.sodium = 1;
    nutrients.zinc = 0.12; nutrients.fiber = 1.4; nutrients.sugar = 9.85;
  }
  else if (foodName.includes('watermelon')) {
    nutrients.vitamin_A = 28; nutrients.vitamin_C = 8.1; nutrients.vitamin_B1 = 0.033;
    nutrients.vitamin_B5 = 0.221; nutrients.vitamin_B6 = 0.045; nutrients.calcium = 7;
    nutrients.iron = 0.24; nutrients.magnesium = 10; nutrients.phosphorus = 11;
    nutrients.potassium = 112; nutrients.sodium = 1; nutrients.zinc = 0.1;
    nutrients.fiber = 0.4; nutrients.sugar = 6.2;
  }
  else if (foodName.includes('apple')) {
    nutrients.vitamin_A = 3; nutrients.vitamin_C = 4.6; nutrients.vitamin_K = 2.2;
    nutrients.calcium = 6; nutrients.iron = 0.12; nutrients.magnesium = 5;
    nutrients.phosphorus = 11; nutrients.potassium = 107; nutrients.fiber = 2.4;
    nutrients.sugar = 10.4;
  }
  else if (foodName.includes('banana')) {
    nutrients.vitamin_A = 3; nutrients.vitamin_C = 8.7; nutrients.vitamin_B6 = 0.367;
    nutrients.calcium = 5; nutrients.iron = 0.26; nutrients.magnesium = 27;
    nutrients.phosphorus = 22; nutrients.potassium = 358; nutrients.fiber = 2.6;
    nutrients.sugar = 12.2;
  }
  else if (foodName.includes('orange')) {
    nutrients.vitamin_A = 11; nutrients.vitamin_C = 53.2; nutrients.vitamin_B1 = 0.087;
    nutrients.vitamin_B9 = 40; nutrients.calcium = 40; nutrients.iron = 0.1;
    nutrients.magnesium = 10; nutrients.phosphorus = 14; nutrients.potassium = 181;
    nutrients.fiber = 2.4; nutrients.sugar = 9.4;
  }
  else if (foodName.includes('strawberry') || foodName.includes('strawberries')) {
    nutrients.vitamin_A = 1; nutrients.vitamin_C = 58.8; nutrients.vitamin_K = 2.2;
    nutrients.vitamin_B9 = 24; nutrients.calcium = 16; nutrients.iron = 0.41;
    nutrients.magnesium = 13; nutrients.phosphorus = 24; nutrients.potassium = 153;
    nutrients.fiber = 2.0; nutrients.sugar = 4.9;
  }
  else if (foodName.includes('grape') || foodName.includes('grapes')) {
    nutrients.vitamin_A = 3; nutrients.vitamin_C = 10.8; nutrients.vitamin_K = 14.6;
    nutrients.calcium = 10; nutrients.iron = 0.36; nutrients.magnesium = 7;
    nutrients.phosphorus = 20; nutrients.potassium = 191; nutrients.fiber = 0.9;
    nutrients.sugar = 16.25;
  }
  
  // VEGETABLES
  else if (foodName.includes('broccoli')) {
    nutrients.vitamin_A = 31; nutrients.vitamin_C = 89.2; nutrients.vitamin_K = 101.6;
    nutrients.vitamin_B9 = 63; nutrients.calcium = 47; nutrients.iron = 0.73;
    nutrients.magnesium = 21; nutrients.phosphorus = 66; nutrients.potassium = 316;
    nutrients.fiber = 2.6; nutrients.sugar = 1.5;
  }
  else if (foodName.includes('spinach')) {
    nutrients.vitamin_A = 469; nutrients.vitamin_C = 28.1; nutrients.vitamin_K = 483;
    nutrients.vitamin_B9 = 194; nutrients.calcium = 99; nutrients.iron = 2.71;
    nutrients.magnesium = 79; nutrients.phosphorus = 49; nutrients.potassium = 558;
    nutrients.fiber = 2.2; nutrients.sugar = 0.4;
  }
  else if (foodName.includes('carrot')) {
    nutrients.vitamin_A = 835; nutrients.vitamin_C = 5.9; nutrients.vitamin_K = 13.2;
    nutrients.calcium = 33; nutrients.iron = 0.3; nutrients.magnesium = 12;
    nutrients.phosphorus = 35; nutrients.potassium = 320; nutrients.fiber = 2.8;
    nutrients.sugar = 4.7;
  }
  else if (foodName.includes('tomato')) {
    nutrients.vitamin_A = 42; nutrients.vitamin_C = 13.7; nutrients.vitamin_K = 7.9;
    nutrients.calcium = 10; nutrients.iron = 0.27; nutrients.magnesium = 11;
    nutrients.phosphorus = 24; nutrients.potassium = 237; nutrients.fiber = 1.2;
    nutrients.sugar = 2.6;
  }
  else if (foodName.includes('cucumber')) {
    nutrients.vitamin_A = 7; nutrients.vitamin_C = 2.8; nutrients.vitamin_K = 16.4;
    nutrients.calcium = 16; nutrients.iron = 0.28; nutrients.magnesium = 13;
    nutrients.phosphorus = 24; nutrients.potassium = 147; nutrients.fiber = 0.5;
    nutrients.sugar = 1.7;
  }
  else if (foodName.includes('pepper') || foodName.includes('bell pepper')) {
    nutrients.vitamin_A = 157; nutrients.vitamin_C = 127.7; nutrients.vitamin_K = 4.9;
    nutrients.calcium = 7; nutrients.iron = 0.34; nutrients.magnesium = 10;
    nutrients.phosphorus = 20; nutrients.potassium = 175; nutrients.fiber = 1.7;
    nutrients.sugar = 2.4;
  }
  else if (foodName.includes('onion')) {
    nutrients.vitamin_A = 0; nutrients.vitamin_C = 7.4; nutrients.vitamin_B6 = 0.12;
    nutrients.calcium = 23; nutrients.iron = 0.21; nutrients.magnesium = 10;
    nutrients.phosphorus = 29; nutrients.potassium = 146; nutrients.fiber = 1.7;
    nutrients.sugar = 4.2;
  }
  else if (foodName.includes('lettuce')) {
    nutrients.vitamin_A = 166; nutrients.vitamin_C = 9.2; nutrients.vitamin_K = 126.3;
    nutrients.vitamin_B9 = 38; nutrients.calcium = 18; nutrients.iron = 0.86;
    nutrients.magnesium = 13; nutrients.phosphorus = 20; nutrients.potassium = 194;
    nutrients.fiber = 1.3; nutrients.sugar = 0.8;
  }
  
  // PROTEINS & MEATS
  else if (foodName.includes('sausage')) {
    nutrients.vitamin_B1 = 0.4; nutrients.vitamin_B3 = 4.5; nutrients.vitamin_B12 = 1.2;
    nutrients.iron = 1.5; nutrients.zinc = 2.4; nutrients.phosphorus = 180;
    nutrients.selenium = 15; nutrients.sodium = 1200; nutrients.magnesium = 18;
    nutrients.potassium = 250; nutrients.saturated_fats = 8.5; nutrients.cholesterol = 65;
  }
  else if (foodName.includes('chicken')) {
    nutrients.vitamin_B3 = 8.5; nutrients.vitamin_B6 = 0.5; nutrients.vitamin_B12 = 0.3;
    nutrients.phosphorus = 200; nutrients.selenium = 22; nutrients.iron = 0.9;
    nutrients.zinc = 1.3; nutrients.magnesium = 25; nutrients.potassium = 256;
    if (foodName.includes('breast')) {
      nutrients.protein_g = 31; nutrients.fat_g = 3.6;
    }
  }
  else if (foodName.includes('beef')) {
    nutrients.vitamin_B3 = 5.8; nutrients.vitamin_B12 = 2.6; nutrients.iron = 2.6;
    nutrients.zinc = 4.8; nutrients.phosphorus = 198; nutrients.selenium = 14.2;
    nutrients.magnesium = 21; nutrients.potassium = 318;
  }
  else if (foodName.includes('pork')) {
    nutrients.vitamin_B1 = 0.7; nutrients.vitamin_B3 = 4.6; nutrients.vitamin_B12 = 0.7;
    nutrients.iron = 0.9; nutrients.zinc = 2.4; nutrients.phosphorus = 230;
    nutrients.selenium = 38; nutrients.potassium = 423;
  }
  else if (foodName.includes('salmon')) {
    nutrients.vitamin_D = 11; nutrients.vitamin_B12 = 3.2; nutrients.omega_3 = 2260;
    nutrients.selenium = 36.5; nutrients.phosphorus = 252; nutrients.magnesium = 30;
    nutrients.potassium = 363; nutrients.iron = 0.8;
  }
  else if (foodName.includes('tuna')) {
    nutrients.vitamin_D = 5.7; nutrients.vitamin_B12 = 9.4; nutrients.omega_3 = 1280;
    nutrients.selenium = 90.6; nutrients.phosphorus = 254; nutrients.magnesium = 30;
    nutrients.potassium = 252; nutrients.iron = 1.0;
  }
  else if (foodName.includes('egg')) {
    nutrients.vitamin_A = 160; nutrients.vitamin_D = 2; nutrients.vitamin_B12 = 0.9;
    nutrients.vitamin_B2 = 0.4; nutrients.selenium = 30.7; nutrients.phosphorus = 198;
    nutrients.iron = 1.75; nutrients.zinc = 1.3; nutrients.cholesterol = 372;
  }
  
  // GRAINS & STARCHES
  else if (foodName.includes('rice')) {
    nutrients.vitamin_B1 = 0.07; nutrients.vitamin_B3 = 1.6; nutrients.iron = 0.8;
    nutrients.magnesium = 25; nutrients.phosphorus = 115; nutrients.potassium = 115;
    nutrients.zinc = 1.1; nutrients.fiber = 1.3;
    if (foodName.includes('brown')) {
      nutrients.fiber = 1.8; nutrients.magnesium = 43;
    }
  }
  else if (foodName.includes('potato')) {
    nutrients.vitamin_C = 19.7; nutrients.vitamin_B6 = 0.3; nutrients.potassium = 429;
    nutrients.phosphorus = 57; nutrients.magnesium = 23; nutrients.iron = 0.8;
    nutrients.fiber = 2.1;
  }
  else if (foodName.includes('bread')) {
    nutrients.vitamin_B1 = 0.5; nutrients.vitamin_B3 = 4.3; nutrients.iron = 3.6;
    nutrients.calcium = 149; nutrients.magnesium = 22; nutrients.phosphorus = 89;
    nutrients.zinc = 0.7; nutrients.fiber = 2.7;
  }
  else if (foodName.includes('pasta')) {
    nutrients.vitamin_B1 = 0.1; nutrients.vitamin_B3 = 1.7; nutrients.iron = 1.3;
    nutrients.magnesium = 18; nutrients.phosphorus = 58; nutrients.potassium = 44;
    nutrients.fiber = 1.8;
  }
  
  // DAIRY
  else if (foodName.includes('milk')) {
    nutrients.vitamin_A = 46; nutrients.vitamin_D = 1.3; nutrients.vitamin_B12 = 0.4;
    nutrients.calcium = 113; nutrients.phosphorus = 84; nutrients.potassium = 132;
    nutrients.magnesium = 10; nutrients.zinc = 0.4;
  }
  else if (foodName.includes('cheese')) {
    nutrients.vitamin_A = 337; nutrients.vitamin_B12 = 0.8; nutrients.calcium = 721;
    nutrients.phosphorus = 512; nutrients.zinc = 3.1; nutrients.selenium = 14.5;
    nutrients.saturated_fats = 18.9;
  }
  else if (foodName.includes('yogurt')) {
    nutrients.vitamin_B12 = 0.5; nutrients.calcium = 110; nutrients.phosphorus = 135;
    nutrients.potassium = 141; nutrients.magnesium = 11; nutrients.zinc = 0.6;
  }
  
  // NUTS & SEEDS
  else if (foodName.includes('almond')) {
    nutrients.vitamin_E = 25.6; nutrients.calcium = 269; nutrients.magnesium = 270;
    nutrients.phosphorus = 481; nutrients.potassium = 733; nutrients.iron = 3.9;
    nutrients.zinc = 3.1; nutrients.fiber = 12.5;
  }
  else if (foodName.includes('walnut')) {
    nutrients.omega_3 = 9080; nutrients.omega_6 = 38100; nutrients.magnesium = 158;
    nutrients.phosphorus = 346; nutrients.potassium = 441; nutrients.iron = 2.9;
    nutrients.zinc = 3.1; nutrients.fiber = 6.7;
  }
  
  // OILS & FATS
  else if (foodName.includes('olive oil')) {
    nutrients.vitamin_E = 14.4; nutrients.vitamin_K = 60.2;
  }
  else if (foodName.includes('avocado')) {
    nutrients.vitamin_K = 21; nutrients.vitamin_E = 2.1; nutrients.vitamin_C = 10;
    nutrients.vitamin_B9 = 81; nutrients.potassium = 485; nutrients.magnesium = 29;
    nutrients.fiber = 6.7; nutrients.omega_3 = 111;
  }
  
  // ENHANCED Generic estimates for unmatched foods - ENSURE ALL FOODS GET NUTRIENTS
  else if (foodName.includes('fruit') || foodName.includes('berry')) {
    nutrients.vitamin_C = Math.max(carbs * 3, 15);
    nutrients.vitamin_A = Math.max(carbs * 2, 8);
    nutrients.potassium = Math.max(carbs * 12, 120);
    nutrients.fiber = Math.max(carbs * 0.4, 2);
    nutrients.sugar = Math.max(carbs * 0.8, 6);
    nutrients.calcium = Math.max(carbs * 1.5, 10);
    nutrients.iron = Math.max(carbs * 0.05, 0.3);
    nutrients.magnesium = Math.max(carbs * 1, 8);
  }
  else if (foodName.includes('vegetable') || foodName.includes('green') || foodName.includes('salad')) {
    nutrients.vitamin_A = Math.max(carbs * 8, 25);
    nutrients.vitamin_C = Math.max(carbs * 4, 20);
    nutrients.vitamin_K = Math.max(carbs * 3, 15);
    nutrients.iron = Math.max(protein * 0.6, 0.8);
    nutrients.calcium = Math.max(carbs * 10, 25);
    nutrients.fiber = Math.max(carbs * 0.5, 2.5);
    nutrients.potassium = Math.max(carbs * 15, 150);
    nutrients.magnesium = Math.max(carbs * 2, 12);
  }
  else if (foodName.includes('meat') || foodName.includes('protein')) {
    nutrients.vitamin_B12 = Math.max(protein * 0.4, 1.5);
    nutrients.vitamin_B3 = Math.max(protein * 2, 6);
    nutrients.iron = Math.max(protein * 0.5, 1.2);
    nutrients.zinc = Math.max(protein * 0.4, 1.5);
    nutrients.phosphorus = Math.max(protein * 10, 180);
    nutrients.selenium = Math.max(protein * 3, 15);
    nutrients.potassium = Math.max(protein * 12, 200);
    nutrients.magnesium = Math.max(protein * 1.5, 20);
  }
  else if (foodName.includes('fish') || foodName.includes('seafood')) {
    nutrients.vitamin_D = Math.max(protein * 0.6, 3);
    nutrients.vitamin_B12 = Math.max(protein * 0.5, 2.5);
    nutrients.omega_3 = Math.max(fat * 60, 800);
    nutrients.selenium = Math.max(protein * 4, 25);
    nutrients.phosphorus = Math.max(protein * 12, 220);
    nutrients.potassium = Math.max(protein * 15, 280);
    nutrients.iron = Math.max(protein * 0.3, 0.8);
  }
  else {
    // FALLBACK for ANY unrecognized food - ensure it gets SOME nutrients
    nutrients.vitamin_C = Math.max(carbs * 1.5, 5);
    nutrients.vitamin_A = Math.max(carbs * 1, 3);
    nutrients.calcium = Math.max(carbs * 2 + protein * 3, 15);
    nutrients.iron = Math.max(protein * 0.3 + carbs * 0.1, 0.5);
    nutrients.magnesium = Math.max(carbs * 1.5 + protein * 1, 10);
    nutrients.potassium = Math.max(carbs * 8 + protein * 5, 100);
    nutrients.phosphorus = Math.max(protein * 6 + carbs * 2, 50);
    nutrients.zinc = Math.max(protein * 0.2, 0.5);
    nutrients.fiber = Math.max(carbs * 0.2, 1);
    nutrients.vitamin_B3 = Math.max(protein * 0.8, 2);
    nutrients.vitamin_B6 = Math.max(protein * 0.1, 0.1);
  }
  
  console.log(`🔬 Generated ${Object.keys(nutrients).filter(k => nutrients[k] > 0).length} nutrients for ${foodName}`);
  return nutrients;
}

// Process image and analyze with OpenAI using TEXT format instead of JSON (avoids parsing errors)
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

    // Client already compresses to 700KB properly - no need for server compression
    console.log(`Received image size: ${processedImage.length} bytes (${(processedImage.length / 1024 / 1024).toFixed(1)}MB)`);
    
    // Update progress
    await updateJobStatus(jobId, {
      progress: 30,
      message: 'Image processed, calling OpenAI API...'
    });

    // CLEAN prompt - let OpenAI analyze the actual image
    const systemPrompt = `You are a professional chef and food analyst. Give this dish an APPETIZING RESTAURANT NAME, then identify ingredients.

Estimate the actual serving size of each item based on what you observe in the image.

Return ONLY valid JSON:

{
  "meal_name": "GOURMET RESTAURANT NAME (like 'Mediterranean Chicken Bowl' or 'Artisan Beef Sandwich')",
  "ingredients": [
    {
      "name": "specific food item",
      "weight_g": 150,
      "calories": 75,
      "protein_g": 3,
      "fat_g": 1.5,
      "carbs_g": 15
    }
  ]
}

Rules:
1. Identify ALL food items visible in the image
2. Estimate weight_g based on the actual portion size you see
3. Use specific food names
4. Break down complex dishes into components
5. Include all visible ingredients, garnishes, and components
6. NO extra text outside JSON structure`;

    let finalResponse = null;
    
    if (process.env.OPENAI_API_KEY) {
      try {
        // Use AbortController for timeout
        const controller = new AbortController();
        const timeoutId = setTimeout(() => {
          console.log(`OpenAI API call timeout for job ${jobId}`);
          controller.abort();
        }, 120000); // Increased to 120 seconds for image analysis
        
        // Use GPT-4o with image analysis capability
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
      },
          signal: controller.signal,
      body: JSON.stringify({
            model: "gpt-4o-mini", // cheaper image-capable model
            temperature: 0.1,  // Lower temperature for more predictable outputs
            response_format: { type: "json_object" },
        messages: [
          {
                role: "system",
                content: systemPrompt
              },
              {
                role: "user",
                content: [
                  { type: "text", text: "Analyze this food image and identify every ingredient you can see. Estimate the actual serving size of each item based on what you observe in the image." },
                  { type: "image_url", image_url: { url: processedImage } }
                ]
              }
            ],
            max_tokens: 1500
      })
    });

        clearTimeout(timeoutId);
        
        if (response.ok) {
          const responseData = await response.json();
          const content = responseData.choices[0].message.content.trim();
          
          try {
            // Parse JSON response first before logging
            const jsonResponse = JSON.parse(content);
            
            // Only log after successful parsing to avoid partial logging
            console.log('OpenAI API response successfully parsed');
            console.log('Response structure:', {
              hasIngredients: !!jsonResponse.ingredients,
              ingredientCount: jsonResponse.ingredients?.length || 0,
              hasMealName: !!jsonResponse.meal_name
            });
            
            // Check if we have valid ingredients
            if (jsonResponse.ingredients && jsonResponse.ingredients.length > 0) {
              console.log(`Detected ${jsonResponse.ingredients.length} ingredients for job ${jobId}`);
              
              // Expand simple response to full nutrient profile using real nutritional knowledge
              const expandedResponse = expandToFullNutrients(jsonResponse);
              const finalResponse = processVisionResponse(expandedResponse);
              
              // Update job status with success
              await updateJobStatus(jobId, {
                status: 'completed',
                progress: 100,
                message: 'Analysis complete',
                completedAt: Date.now(),
                result: finalResponse
              });
              
              console.log(`Job ${jobId} marked completed at ${new Date().toISOString()}`);
            } else {
              // No ingredients found - return error
              console.log('No ingredients detected by API');
              await updateJobStatus(jobId, {
                status: 'failed',
                progress: 100,
                completedAt: Date.now(),
                error: 'No food ingredients could be detected in the image'
              });
              
              console.log(`Job ${jobId} marked failed at ${new Date().toISOString()}`);
            }
          } catch (parseError) {
            console.error(`JSON parse error for job ${jobId}:`, parseError.message);
            console.log('Raw OpenAI response length:', content.length);
            console.log('Raw OpenAI response preview (first 500 chars):', content.substring(0, 500));
            console.log('Raw OpenAI response preview (last 500 chars):', content.substring(Math.max(0, content.length - 500)));
            
            // Try to find and fix common JSON issues
            let cleanedContent = content.trim();
            
            // Remove markdown code blocks if present
            cleanedContent = cleanedContent.replace(/^```json\s*/, '').replace(/\s*```$/, '');
            
            // Remove any leading/trailing whitespace
            cleanedContent = cleanedContent.trim();
            
            // Fix common JSON issues
            cleanedContent = cleanedContent
              .replace(/,\s*}/g, '}')     // Remove trailing commas before }
              .replace(/,\s*]/g, ']')     // Remove trailing commas before ]
              .replace(/"\s*:\s*,/g, '": null,')  // Fix empty values
              .replace(/:\s*,/g, ': null,')       // Fix missing values
              .replace(/,\s*,/g, ',');            // Fix double commas
            
            // Try to parse the cleaned response
            if (cleanedContent !== content) {
              try {
                console.log('Attempting to parse cleaned JSON...');
                const jsonResponse = JSON.parse(cleanedContent);
                console.log('Cleaned JSON parsed successfully!');
                
                if (jsonResponse.ingredients && jsonResponse.ingredients.length > 0) {
                  // Expand simple response to full nutrient profile using real nutritional knowledge
                  const expandedResponse = expandToFullNutrients(jsonResponse);
                  const finalResponse = processVisionResponse(expandedResponse);
                  
                  await updateJobStatus(jobId, {
                    status: 'completed',
                    progress: 100,
                    message: 'Analysis complete (cleaned JSON)',
                    completedAt: Date.now(),
                    result: finalResponse
                  });
                  
                  console.log(`Job ${jobId} marked completed (cleaned JSON) at ${new Date().toISOString()}`);
                  return; // Exit early on success
                }
              } catch (cleanError) {
                console.log('JSON clean attempt failed:', cleanError.message);
              }
            }
            
            // Save the cleaned response for debugging without logging to console
            await updateJobStatus(jobId, {
              status: 'failed',
              progress: 100,
              completedAt: Date.now(),
              error: 'Invalid response format from image analysis',
              raw_response_size: content.length // Include size instead of content
            });
            
            console.log(`Job ${jobId} marked failed (JSON parse error) at ${new Date().toISOString()}`);
        }
          } else {
      const errorData = await response.text();
      console.error('OpenAI API error:', response.status, errorData);
          await updateJobStatus(jobId, {
            status: 'failed',
            progress: 100,
            completedAt: Date.now(),
            error: `Image analysis failed: ${response.status}`
          });
          
          console.log(`Job ${jobId} marked failed (API error ${response.status}) at ${new Date().toISOString()}`);
    }
  } catch (error) {
        console.error(`API call failed for job ${jobId}:`, error);
        
        let errorMessage = `API call error: ${error.message}`;
        if (error.type === 'request-timeout' || error.message.includes('timeout')) {
          errorMessage = 'Request timeout - image analysis took too long. Please try again with a smaller image.';
        } else if (error.message.includes('network')) {
          errorMessage = 'Network error - please check your connection and try again.';
        }
        
        await updateJobStatus(jobId, {
          status: 'failed',
          progress: 100,
          completedAt: Date.now(),
          error: errorMessage
        });
        
        console.log(`Job ${jobId} marked failed (API call error) at ${new Date().toISOString()}`);
        }
      } else {
      console.log('No OpenAI API key available');
      await updateJobStatus(jobId, {
        status: 'failed',
        progress: 100,
        completedAt: Date.now(),
        error: 'API key not configured'
      });
      
      console.log(`Job ${jobId} marked failed (no API key) at ${new Date().toISOString()}`);
    }
    
    console.log(`Job ${jobId} processing completed`);
  } catch (error) {
    console.error(`Error processing job ${jobId}:`, error);
    await updateJobStatus(jobId, {
      status: 'failed',
      progress: 100,
      completedAt: Date.now(),
      error: `Server error: ${error.message}`
    });
    
    console.log(`Job ${jobId} marked failed (server error) at ${new Date().toISOString()}`);
  }
}



// Process Vision API response into our expected format
function processVisionResponse(visionResponse) {
  console.log('🔄 Processing vision response with ingredients:', visionResponse.ingredients?.length || 0);
  
  const { ingredients, total } = visionResponse;
  
  if (!ingredients || !Array.isArray(ingredients)) {
    console.error('❌ No valid ingredients array in vision response');
    return null;
  }
  
  console.log('🔄 Converting flat nutrients to nested format...');
  
  // Convert the flat nutrient structure to nested structure expected by app
  const convertedIngredients = convertFlatNutrientsToNested(ingredients);
  
  console.log('✅ Converted ingredients:', convertedIngredients.length);
  console.log('🔍 First ingredient vitamins keys:', Object.keys(convertedIngredients[0]?.vitamins || {}));
  
  // Helper function to clean ingredient names
  function cleanIngredientName(name) {
    if (!name) return name;
    
    // Convert to lowercase for processing
    let cleaned = name.toLowerCase().trim();
    
    // Remove common descriptive words and cooking methods
    const wordsToRemove = [
      'grilled', 'fried', 'baked', 'roasted', 'steamed', 'boiled',
      'sliced', 'diced', 'chopped', 'minced', 'fresh', 'cooked',
      'seasoned', 'marinated', 'sautéed', 'pan-fried', 'deep-fried',
      'organic', 'raw', 'frozen', 'canned', 'dried', 'smoked',
      'boneless', 'skinless', 'lean', 'extra', 'large', 'small',
      'medium', 'whole', 'half', 'quarter', 'piece', 'pieces'
    ];
    
    // Remove descriptive words
    wordsToRemove.forEach(word => {
      const regex = new RegExp(`\\b${word}\\s+`, 'gi');
      cleaned = cleaned.replace(regex, '');
    });
    
    // Specific ingredient simplifications
    const simplifications = {
      'chicken breast': 'chicken',
      'chicken thigh': 'chicken', 
      'chicken wing': 'chicken',
      'chicken drumstick': 'chicken',
      'beef steak': 'beef',
      'ground beef': 'beef',
      'pork chop': 'pork',
      'pork tenderloin': 'pork',
      'cherry tomatoes': 'tomatoes',
      'roma tomatoes': 'tomatoes',
      'grape tomatoes': 'tomatoes',
      'bell pepper': 'peppers',
      'red pepper': 'peppers',
      'green pepper': 'peppers',
      'sweet potato': 'potato',
      'russet potato': 'potato',
      'red potato': 'potato',
      'brown rice': 'rice',
      'white rice': 'rice',
      'jasmine rice': 'rice',
      'basmati rice': 'rice',
      'olive oil': 'oil',
      'vegetable oil': 'oil',
      'canola oil': 'oil',
      'italian sausage': 'sausages',
      'turkey sausage': 'sausages',
      'pork sausage': 'sausages'
    };
    
    // Apply simplifications
    for (const [long, short] of Object.entries(simplifications)) {
      if (cleaned.includes(long)) {
        cleaned = short;
        break;
      }
    }
    
    // Clean up extra spaces and capitalize first letter
    cleaned = cleaned.trim().replace(/\s+/g, ' ');
    return cleaned.charAt(0).toUpperCase() + cleaned.slice(1);
  }
  
  // Helper function to generate appropriate meal name
  function generateMealName(ingredientNames) {
    if (!ingredientNames || ingredientNames.length === 0) {
      return "Mixed Plate";
    }
    
    // Use the meal_name from API response if it exists and is reasonable
    if (visionResponse.meal_name && 
        visionResponse.meal_name.length < 30 && 
        !visionResponse.meal_name.includes(' with ') &&
        !visionResponse.meal_name.includes(' and ') &&
        !visionResponse.meal_name.toLowerCase().includes('ingredients')) {
      return visionResponse.meal_name;
    }
    
    const ingredients = ingredientNames.map(name => name.toLowerCase());
    
    // Enhanced meal pattern recognition with specific combinations
    if (ingredients.some(ing => ing.includes('pizza'))) {
      return "Pizza";
    }
    
    // Pasta dishes with specific types
    if (ingredients.some(ing => ing.includes('pasta') || ing.includes('spaghetti') || ing.includes('noodles'))) {
      if (ingredients.some(ing => ing.includes('carbonara'))) return "Carbonara Pasta";
      if (ingredients.some(ing => ing.includes('alfredo'))) return "Alfredo Pasta";
      if (ingredients.some(ing => ing.includes('marinara') || ing.includes('tomato'))) return "Marinara Pasta";
      if (ingredients.some(ing => ing.includes('pesto'))) return "Pesto Pasta";
      return "Pasta Dish";
    }
    
    // Taco variations
    if (ingredients.some(ing => ing.includes('taco') || ing.includes('tortilla'))) {
      if (ingredients.some(ing => ing.includes('beef') || ing.includes('meat'))) return "Meat Tacos";
      if (ingredients.some(ing => ing.includes('chicken'))) return "Chicken Tacos";
      if (ingredients.some(ing => ing.includes('fish'))) return "Fish Tacos";
      return "Tacos";
    }
    
    if (ingredients.some(ing => ing.includes('burger') || ing.includes('bun'))) {
      return "Burger";
    }
    
    // Salad variations
    if (ingredients.some(ing => ing.includes('salad') || ing.includes('lettuce')) && 
        ingredients.length >= 3) {
      if (ingredients.some(ing => ing.includes('caesar'))) return "Caesar Salad";
      if (ingredients.some(ing => ing.includes('chicken'))) return "Chicken Salad";
      if (ingredients.some(ing => ing.includes('greek'))) return "Greek Salad";
      return "Salad";
    }
    
    if (ingredients.some(ing => ing.includes('soup'))) {
      return "Soup";
    }
    
    if (ingredients.some(ing => ing.includes('sandwich'))) {
      return "Sandwich";
    }
    
    // Rice bowl variations
    if (ingredients.some(ing => ing.includes('rice')) && ingredients.length >= 2) {
      if (ingredients.some(ing => ing.includes('chicken'))) return "Chicken Rice Bowl";
      if (ingredients.some(ing => ing.includes('beef'))) return "Beef Rice Bowl";
      if (ingredients.some(ing => ing.includes('pork'))) return "Pork Rice Bowl";
      return "Rice Bowl";
    }
    
    // Protein-based dishes
    if (ingredients.some(ing => ing.includes('steak') || ing.includes('beef'))) {
      return "Steak Dinner";
    }
    
    if (ingredients.some(ing => ing.includes('chicken'))) {
      if (ingredients.some(ing => ing.includes('wings'))) return "Chicken Wings";
      if (ingredients.some(ing => ing.includes('grilled'))) return "Grilled Chicken";
      return "Chicken Dish";
    }
    
    if (ingredients.some(ing => ing.includes('fish') || ing.includes('salmon') || ing.includes('tuna'))) {
      if (ingredients.some(ing => ing.includes('salmon'))) return "Salmon Dish";
      if (ingredients.some(ing => ing.includes('tuna'))) return "Tuna Dish";
      return "Fish Dish";
    }
    
    if (ingredients.some(ing => ing.includes('pork'))) {
      return "Pork Dish";
    }
    
    // Breakfast items
    if (ingredients.some(ing => ing.includes('eggs') || ing.includes('pancake') || ing.includes('waffle'))) {
      return "Breakfast";
    }
    
    // Generic names based on number of ingredients and content
    if (ingredients.length === 1) {
      return ingredientNames[0];
    } else if (ingredients.length <= 2) {
      return "Light Meal";
    } else if (ingredients.length <= 4) {
      return "Dinner Plate";
    } else {
      return "Mixed Plate";
    }
  }
  
  // Map ingredients to our format with comprehensive nutrition data and clean names
  const mappedIngredients = convertedIngredients.map(item => {
    const cleanName = cleanIngredientName(item.name);
    const weight = item.weight_g || 100.0;
    const calories = item.calories || 0;
    
    const ingredient = {
      name: cleanName,
      weight_g: weight,
      calories: calories,
      protein_g: item.protein_g || 0,
      fat_g: item.fat_g || 0,
      carbs_g: item.carbs_g || 0,
      // Aliases for client compatibility
      amount: `${weight}g`,
      protein: item.protein_g || 0,
      fat: item.fat_g || 0,
      carbs: item.carbs_g || 0
    };

    // Log warning if OpenAI failed to provide weight
    if (!item.weight_g) {
      console.warn(`⚠️  OpenAI failed to provide weight_g for ingredient: ${item.name}, using fallback 100g`);
    }

    // Add vitamins if present
    if (item.vitamins) {
      ingredient.vitamins = item.vitamins;
    }

    // Add minerals if present
    if (item.minerals) {
      ingredient.minerals = item.minerals;
    }

    // Add other nutrients if present
    if (item.other) {
      ingredient.other = item.other;
    }

    return ingredient;
  });
  
  // Generate appropriate meal name
  const foodNames = mappedIngredients.map(item => item.name);
  const mealName = generateMealName(foodNames);
  
  // Build comprehensive response with all nutrition data
  const response = {
    meal_name: mealName,
    ingredients: mappedIngredients,
    health_score: calculateHealthScore(mappedIngredients),
    // Basic macronutrients
    calories: total?.calories || mappedIngredients.reduce((sum, ing) => sum + (ing.calories || 0), 0),
    protein: total?.protein_g || mappedIngredients.reduce((sum, ing) => sum + (ing.protein_g ?? ing.protein ?? 0), 0),
    fat: total?.fat_g || mappedIngredients.reduce((sum, ing) => sum + (ing.fat_g ?? ing.fat ?? 0), 0),
    carbs: total?.carbs_g || mappedIngredients.reduce((sum, ing) => sum + (ing.carbs_g ?? ing.carbs ?? 0), 0)
  };

  // Compute meal-level micronutrient totals from ingredients and FLATTEN
  // Helper: sum from mapped nested fields, with fallback to pre-mapped flat fields
  const sumNested = (getterMapped, getterFlat) => {
    let sum = 0;
    // Prefer mapped ingredients (nested objects)
    sum = mappedIngredients.reduce((s, ing) => {
      try {
        const v = getterMapped(ing);
        return s + (typeof v === 'number' && !Number.isNaN(v) ? v : 0);
      } catch { return s; }
    }, 0);
    if (sum > 0) return sum;
    // Fallback: read from convertedIngredients before mapping (flat keys like 'fiber')
    try {
      sum = convertedIngredients.reduce((s, ing) => {
        const v = getterFlat ? getterFlat(ing) : 0;
        return s + (typeof v === 'number' && !Number.isNaN(v) ? v : 0);
      }, 0);
    } catch {}
    return sum;
  };

  // Vitamins (13)
  const vitaminsMap = {
    vitamin_A_mcg: 'vitamin_a',
    vitamin_C_mg: 'vitamin_c',
    vitamin_D_mcg: 'vitamin_d',
    vitamin_E_mg: 'vitamin_e',
    vitamin_K_mcg: 'vitamin_k',
    vitamin_B1_mg: 'vitamin_b1',
    vitamin_B2_mg: 'vitamin_b2',
    vitamin_B3_mg: 'vitamin_b3',
    vitamin_B5_mg: 'vitamin_b5',
    vitamin_B6_mg: 'vitamin_b6',
    vitamin_B7_mcg: 'vitamin_b7',
    vitamin_B9_mcg: 'vitamin_b9',
    vitamin_B12_mcg: 'vitamin_b12'
  };
  Object.entries(vitaminsMap).forEach(([nestedKey, flatKey]) => {
    const val = sumNested(
      ing => ing.vitamins ? ing.vitamins[nestedKey] : 0,
      ing => ing[nestedKey.replace(/_.+$/, '')] // rough fallback, usually 0 for vitamins
    );
    if (val > 0) response[flatKey] = +(val.toFixed(2));
  });

  // Minerals (15)
  const mineralsMap = {
    calcium_mg: 'calcium',
    chloride_mg: 'chloride',
    chromium_mcg: 'chromium',
    copper_mg: 'copper',
    fluoride_mg: 'fluoride',
    iodine_mcg: 'iodine',
    iron_mg: 'iron',
    magnesium_mg: 'magnesium',
    manganese_mg: 'manganese',
    molybdenum_mcg: 'molybdenum',
    phosphorus_mg: 'phosphorus',
    potassium_mg: 'potassium',
    selenium_mcg: 'selenium',
    sodium_mg: 'sodium',
    zinc_mg: 'zinc'
  };
  Object.entries(mineralsMap).forEach(([nestedKey, flatKey]) => {
    const val = sumNested(
      ing => ing.minerals ? ing.minerals[nestedKey] : 0,
      ing => ing[nestedKey.replace(/_.+$/, '')]
    );
    if (val > 0) response[flatKey] = +(val.toFixed(2));
  });

  // Other (6)
  const otherMap = {
    fiber_g: 'fiber',
    cholesterol_mg: 'cholesterol',
    sugar_g: 'sugar',
    saturated_fats_g: 'saturated_fats',
    omega_3_mg: 'omega_3',
    omega_6_g: 'omega_6'
  };
  Object.entries(otherMap).forEach(([nestedKey, flatKey]) => {
    const val = sumNested(
      ing => ing.other ? ing.other[nestedKey] : 0,
      ing => {
        // Map nested key back to flat (e.g., fiber_g -> fiber)
        const flat = nestedKey.replace(/_(g|mg)$/,'');
        return ing[flat];
      }
    );
    if (val > 0) response[flatKey] = +(val.toFixed(2));
  });

  // Also include ingredient_nutrients array for detailed per-ingredient nutrition
  if (mappedIngredients.length > 0) {
    response.ingredient_nutrients = mappedIngredients.map(ingredient => ({
      name: ingredient.name,
      vitamins: ingredient.vitamins || {},
      minerals: ingredient.minerals || {},
      other: ingredient.other || {}
    }));
  }

  // Optional concise debug: per-ingredient macros (off by default)
  try {
    const logMacros = (process.env.LOG_INGREDIENT_MACROS === '1' || process.env.LOG_INGREDIENT_MACROS === 'true');
    if (logMacros) {
      console.log('\n🥗 INGREDIENT MACROS:');
      mappedIngredients.forEach((ing, idx) => {
        const p = (ing.protein ?? ing.protein_g ?? 0);
        const f = (ing.fat ?? ing.fat_g ?? 0);
        const c = (ing.carbs ?? ing.carbs_g ?? 0);
        console.log(`  ${idx + 1}. ${ing.name} (${ing.amount || ing.weight_g + 'g'}): P ${p}g, F ${f}g, C ${c}g`);
      });
    }
  } catch {}

  // Ensure ingredient macros present. If all zeros but totals exist, distribute by calories
  const totalCalories = mappedIngredients.reduce((s, i) => s + (i.calories || 0), 0) || 1;
  const sumP = mappedIngredients.reduce((s, i) => s + (i.protein ?? i.protein_g ?? 0), 0);
  const sumF = mappedIngredients.reduce((s, i) => s + (i.fat ?? i.fat_g ?? 0), 0);
  const sumC = mappedIngredients.reduce((s, i) => s + (i.carbs ?? i.carbs_g ?? 0), 0);
  const needP = sumP === 0 && (response.protein || 0) > 0;
  const needF = sumF === 0 && (response.fat || 0) > 0;
  const needC = sumC === 0 && (response.carbs || 0) > 0;
  if (needP || needF || needC) {
    mappedIngredients.forEach(i => {
      const share = (i.calories || 0) / totalCalories;
      if (needP) i.protein = +(response.protein * share).toFixed(1);
      if (needF) i.fat = +(response.fat * share).toFixed(1);
      if (needC) i.carbs = +(response.carbs * share).toFixed(1);
    });
  }

  return response;
}

// Calculate health score
function calculateHealthScore(ingredients) {
  // Simple algorithm: higher protein and lower fat/carbs = better score
  let totalProtein = 0;
  let totalFat = 0;
  let totalCarbs = 0;
  
  for (const ingredient of ingredients) {
    totalProtein += ingredient.protein_g || 0;
    totalFat += ingredient.fat_g || 0;
    totalCarbs += ingredient.carbs_g || 0;
  }
  
  // Calculate ratio: protein / (fat + carbs)
  const ratio = totalProtein / (totalFat + totalCarbs + 0.1);
  
  // Convert to score from 1-10
  let score = Math.round(5 + ratio * 2);
  score = Math.max(1, Math.min(10, score)); // Limit to 1-10
  
  return `${score}/10`;
}

// Define routes
app.get('/', (req, res) => {
  console.log('Health check endpoint called');
  res.json({
    message: 'Food Analyzer API Server with real OpenAI integration',
    status: 'operational'
  });
});

// Warmup endpoint to prevent cold starts
app.get('/api/warmup', (req, res) => {
  console.log('🔥 Warmup request received - keeping server warm');
  
  // Perform lightweight operations to warm up the server
  const startTime = Date.now();
  
  // Simulate some processing to warm up modules
  const testData = { message: 'warmup', timestamp: Date.now() };
  JSON.stringify(testData);
  
  const responseTime = Date.now() - startTime;
  
  res.json({
    status: 'success',
    message: 'Server warmed up successfully',
    responseTime: `${responseTime}ms`,
    timestamp: new Date().toISOString(),
    serverUptime: process.uptime()
  });
});

// NEW JOB SUBMISSION ENDPOINT
app.post('/api/jobs', limiter, async (req, res) => {
  try {
    console.log('Job submission endpoint called');
    const { image, userId = 'anonymous' } = req.body;

    if (!image) {
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

    // Process job in background
    processAndAnalyzeImage(jobId, userId, image).catch(console.error);

    // Return job ID immediately
    return res.status(201).json({
      success: true,
      jobId,
      status: 'pending'
    });
  } catch (error) {
    console.error('Job submission error:', error.message);
    return res.status(500).json({
      success: false,
      error: `Job submission failed: ${error.message}`
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
          status: 'completed',
          progress: 100,
          createdAt: jobData.createdAt,
          completedAt: jobData.completedAt || Date.now(),
          data: jobData.result
        });
      } else {
        return res.status(500).json({
          success: false,
          status: 'error',
          error: 'Analysis completed but no results available'
        });
      }
    } else if (jobData.status === 'failed') {
      // Return error status with 200 code so client can parse it properly
      return res.status(200).json({
        success: false,
        status: 'failed',
        error: jobData.error || 'Unknown error during processing',
        progress: 100,
        createdAt: jobData.createdAt,
        completedAt: jobData.completedAt || Date.now()
      });
    }

    // For non-completed jobs, return status info (always read from stored status)
    return res.json({
      success: true,
      status: jobData.status || 'pending', // Always use stored status
      progress: jobData.progress || 0,
      createdAt: jobData.createdAt,
      message: jobData.message || null
    });
  } catch (error) {
    console.error('Job status error:', error.message);
    return res.status(500).json({
      success: false,
      error: `Server error: ${error.message}`
    });
  }
});

// Legacy endpoint with real OpenAI - NO FALLBACKS, FAIL PROPERLY
app.post('/api/analyze-food', limiter, async (req, res) => {
  try {
    console.log('🔥 Legacy analyze food endpoint called - NO FALLBACKS');
    const { image, fast_mode, ultra_fast, lightning_fast } = req.body;
    
    // Log optimization modes
    if (lightning_fast) {
      console.log('⚡⚡⚡ LIGHTNING-FAST mode - 15 SECOND TARGET!');
    } else if (ultra_fast) {
      console.log('⚡⚡ ULTRA-FAST mode enabled - MAXIMUM SPEED');
    } else if (fast_mode) {
      console.log('⚡ Fast mode enabled - optimizing for speed');
    }

    if (!image) {
      console.error('No image provided in request');
      return res.status(400).json({
        success: false,
        error: 'Image data is required'
      });
    }

    // LIGHTNING cache check for similar images - enhanced for speed
    if (lightning_fast || ultra_fast) {
      const imageHash = require('crypto').createHash('md5').update(image.substring(0, 1500)).digest('hex');
      const cached = responseCache.get(imageHash);
      
      if (cached && (Date.now() - cached.timestamp) < CACHE_DURATION) {
        console.log(lightning_fast ? '⚡⚡⚡ LIGHTNING CACHE HIT - INSTANT!' : '⚡⚡ CACHE HIT - Instant response!');
        return res.json({
          success: true,
          data: cached.data,
          cached: true,
          mode: lightning_fast ? 'lightning' : 'ultra_fast'
        });
      }
    }

    if (!process.env.OPENAI_API_KEY) {
      console.log('🔥 No OpenAI API key - FAILING');
      return res.status(500).json({
        success: false,
        error: 'OpenAI API key not configured'
      });
    }

    try {
      // Use the original image without compression
      const processedImage = image;
      
      // CLEAN prompt - let OpenAI analyze the actual image with proper format
      const systemPrompt = `You are a professional food analyst. ANALYZE THE VISUAL DETAILS CAREFULLY:

VISUAL ANALYSIS CHECKLIST:
- Orange/golden cubes = likely sweet potato or regular potato
- White creamy substance = likely yogurt, cream, or sauce
- Meat pieces = identify by texture and color (chicken, beef, etc.)
- Fermented vegetables = kimchi, sauerkraut (often reddish/orange with cabbage texture)
- White chunks = could be cheese, tofu, or other protein
- Look at TEXTURES, COLORS, and SHAPES - don't guess based on assumptions

CRITICAL RULES:
- Identify by VISUAL CHARACTERISTICS, not assumptions
- Sweet potato = orange/golden cubes with smooth texture
- Greek yogurt = white, creamy, smooth consistency  
- Kimchi = fermented cabbage, often reddish/orange color
- Chicken = white/light meat pieces with fibrous texture

Return ONLY valid JSON:

{
  "meal_name": "ACCURATE DESCRIPTIVE NAME based on what you see",
  "ingredients": [
    {
      "name": "ONLY ingredients you can clearly see",
      "weight_g": 150,
      "calories": 75,
      "protein_g": 3,
      "fat_g": 1.5,
      "carbs_g": 15
    }
  ]
}

Rules:
1. Identify ALL food items visible in the image
2. Estimate weight_g based on the actual portion size you see
3. Use specific food names
4. Break down complex dishes into components
5. Include all visible ingredients, garnishes, and components
6. NO extra text outside JSON structure`;

      // Make OpenAI API call with timeout
      const controller = new AbortController();
      const timeoutMs = lightning_fast ? 45000 : (ultra_fast ? 60000 : (fast_mode ? 75000 : 90000)); // Lightning: 45s, Ultra: 60s, Fast: 75s, Normal: 90s
      const timeoutId = setTimeout(() => {
        console.log(`🔥 OpenAI timeout - FAILING (aborting at ${timeoutMs/1000}s)`);
        controller.abort();
      }, timeoutMs);

      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`
        },
        signal: controller.signal,
        body: JSON.stringify({
          model: "gpt-4o-mini", // Always use mini for speed
          temperature: lightning_fast ? 0.001 : (ultra_fast ? 0.01 : (fast_mode ? 0.05 : 0.1)), // EXTREME temperature for lightning
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
                  text: lightning_fast ? 
                    "VISUAL ANALYSIS: Look at colors, textures, shapes. Orange cubes = sweet potato. White creamy = yogurt/sauce. Meat pieces = chicken/beef by texture. Reddish fermented vegetables = kimchi. Be PRECISE about what you observe visually, don't assume based on typical combinations." :
                    (ultra_fast ? 
                      "Analyze visual characteristics: colors, textures, shapes. Identify by what you see, not what you expect." :
                      (fast_mode ? 
                        "Look at visual details: orange cubes, white cream, meat texture, fermented vegetables." : 
                        "Carefully analyze visual characteristics and identify ingredients by their appearance."))
                },
                { 
                  type: "image_url", 
                  image_url: { 
                    url: processedImage,
                    detail: lightning_fast ? "high" : "low" // High detail for lightning accuracy
                  } 
                }
              ]
            }
          ],
          max_tokens: lightning_fast ? 1200 : (ultra_fast ? 1000 : (fast_mode ? 1200 : 1500)), // Restored tokens for accuracy
          stream: false // Ensure no streaming for fastest response
        })
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        console.log('🔥 OpenAI API error - FAILING:', response.status);
        const errorText = await response.text();
        let errorMsg = errorText;
        try {
          const parsed = JSON.parse(errorText);
          errorMsg = parsed?.error?.message || errorText;
        } catch (_) {}
        return res.status(response.status).json({
          success: false,
          error: `OpenAI API error: ${response.status} - ${errorMsg}`
        });
      }

      const responseData = await response.json();
      const content = responseData.choices[0].message.content.trim();
      
      console.log('🔥 OpenAI response received, length:', content.length);
      
      try {
        // Try to parse the response
        const jsonResponse = JSON.parse(content);
        
        if (!jsonResponse.ingredients || !Array.isArray(jsonResponse.ingredients) || jsonResponse.ingredients.length === 0) {
          console.log('🔥 No valid ingredients in response - FAILING');
          return res.status(500).json({
            success: false,
            error: 'No food ingredients detected in the image'
          });
        }

        console.log('🔥 Valid ingredients found:', jsonResponse.ingredients.length);
        
        // Expand simple response to full nutrient profile using real nutritional knowledge
        const expandedResponse = expandToFullNutrients(jsonResponse);
        const finalResponse = processVisionResponse(expandedResponse);
        
        // Cache lightning/ultra-fast responses for instant future access
        if (lightning_fast || ultra_fast) {
          const imageHash = require('crypto').createHash('md5').update(image.substring(0, 1500)).digest('hex');
          
          // Manage cache size
          if (responseCache.size >= CACHE_MAX_SIZE) {
            const firstKey = responseCache.keys().next().value;
            responseCache.delete(firstKey);
          }
          
          responseCache.set(imageHash, {
            data: finalResponse,
            timestamp: Date.now(),
            mode: lightning_fast ? 'lightning' : 'ultra_fast'
          });
          
          console.log(lightning_fast ? '⚡⚡⚡ LIGHTNING response cached!' : '⚡⚡ Response cached for ultra-fast future access');
        }
        
        return res.json({
          success: true,
          data: finalResponse
        });
      } catch (parseError) {
        console.log('🔥 JSON parse failed - FAILING:', parseError.message);
        return res.status(500).json({
          success: false,
          error: 'OpenAI generated invalid JSON that could not be repaired'
        });
      }
    } catch (error) {
      if (error.name === 'AbortError') {
        console.log('🔥 OpenAI call aborted due to timeout');
        return res.status(504).json({
          success: false,
          error: 'OpenAI request timed out'
        });
      }
      console.log('🔥 OpenAI call failed - FAILING:', error.message);
      return res.status(500).json({
        success: false,
        error: `API call error: ${error.message}`
      });
    }
  } catch (error) {
    console.log('🔥 Server error - FAILING:', error.message);
    return res.status(500).json({
      success: false,
      error: `Server error: ${error.message}`
    });
  }
});

// Start the server
app.listen(PORT, () => {
  console.log(`Server with real OpenAI integration running on port ${PORT}`);
});