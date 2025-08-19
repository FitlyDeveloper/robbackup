// FDA Daily Values (2020-2025) - Single source of truth for %DV calculations
const DV = {
  vitamins: { 
    A_mcg: 900, C_mg: 90, D_mcg: 20, E_mg: 15, K_mcg: 120,
    B1_mg: 1.2, B2_mg: 1.3, B3_mg: 16, B5_mg: 5, B6_mg: 1.3, 
    B7_mcg: 30, B9_mcg: 400, B12_mcg: 2.4 
  },
  minerals: { 
    Ca_mg: 1300, Cl_mg: 2300, Cr_mcg: 35, Cu_mcg: 900, F_mg: 4, 
    I_mcg: 150, Fe_mg: 18, Mg_mg: 420, Mn_mg: 2.3, Mo_mcg: 45, 
    P_mg: 1250, K_mg: 4700, Se_mcg: 55, Na_mg: 2300, Zn_mg: 11 
  },
  other: { 
    fiber_g: 28, cholesterol_mg: 300, sugar_g: 50, satfat_g: 20, 
    omega3_mg: 1600, omega6_g: 17 
  }
};

// In-memory cache for FDC lookups (name -> fdcId)
const fdcCache = new Map();

// Create zero totals structure
function makeZeroTotals() {
  return {
    // Macronutrients
    calories_kcal: 0,
    protein_g: 0,
    fat_g: 0,
    carbs_g: 0,
    // Micronutrients
    vitamins: {
      A_mcg: 0, C_mg: 0, D_mcg: 0, E_mg: 0, K_mcg: 0,
      B1_mg: 0, B2_mg: 0, B3_mg: 0, B5_mg: 0, B6_mg: 0,
      B7_mcg: 0, B9_mcg: 0, B12_mcg: 0
    },
    minerals: {
      Ca_mg: 0, Cl_mg: 0, Cr_mcg: 0, Cu_mcg: 0, F_mg: 0,
      I_mcg: 0, Fe_mg: 0, Mg_mg: 0, Mn_mg: 0, Mo_mcg: 0,
      P_mg: 0, K_mg: 0, Se_mcg: 0, Na_mg: 0, Zn_mg: 0
    },
    other: {
      fiber_g: 0, cholesterol_mg: 0, sugar_g: 0, satfat_g: 0,
      omega3_mg: 0, omega6_g: 0
    }
  };
}

// Search FDC for ingredient and return fdcId
async function searchFDC(ingredientName) {
  if (!process.env.FDC_API_KEY) {
    console.log('❌ FDC_API_KEY not configured');
    return null;
  }

  // Check cache first
  if (fdcCache.has(ingredientName.toLowerCase())) {
    console.log(`✅ Cache hit for: ${ingredientName}`);
    return fdcCache.get(ingredientName.toLowerCase());
  }

  try {
    console.log(`🔍 Searching FDC for: ${ingredientName}`);
    
    const searchUrl = `https://api.nal.usda.gov/fdc/v1/foods/search?api_key=${process.env.FDC_API_KEY}&query=${encodeURIComponent(ingredientName)}&pageSize=5&dataType=Foundation,SR Legacy`;
    
    const response = await fetch(searchUrl);
    if (!response.ok) {
      console.log(`❌ FDC search failed: ${response.status}`);
      return null;
    }

    const data = await response.json();
    
    if (data.foods && data.foods.length > 0) {
      const fdcId = data.foods[0].fdcId;
      console.log(`✅ Found FDC ID ${fdcId} for: ${ingredientName}`);
      
      // Cache the result
      fdcCache.set(ingredientName.toLowerCase(), fdcId);
      return fdcId;
    } else {
      console.log(`❌ No FDC results for: ${ingredientName}`);
      return null;
    }
  } catch (error) {
    console.log(`❌ FDC search error for ${ingredientName}:`, error.message);
    return null;
  }
}

// Fetch nutrient data from FDC by fdcId
async function fetchFDCData(fdcId) {
  if (!process.env.FDC_API_KEY) {
    console.log('❌ FDC_API_KEY not configured');
    return null;
  }

  try {
    console.log(`📊 Fetching FDC data for ID: ${fdcId}`);
    
    const url = `https://api.nal.usda.gov/fdc/v1/food/${fdcId}?api_key=${process.env.FDC_API_KEY}`;
    
    const response = await fetch(url);
    if (!response.ok) {
      console.log(`❌ FDC fetch failed: ${response.status}`);
      return null;
    }

    const data = await response.json();
    return data;
  } catch (error) {
    console.log(`❌ FDC fetch error for ${fdcId}:`, error.message);
    return null;
  }
}

// Extract nutrients from FDC data
function extractNutrients(fdcData) {
  if (!fdcData || !fdcData.foodNutrients) {
    return null;
  }

  const nutrients = makeZeroTotals();
  
  // FDC nutrient mapping
  const nutrientMap = {
    // Macronutrients
    '203': 'protein_g',      // Protein
    '204': 'fat_g',          // Total lipid (fat)
    '205': 'carbs_g',        // Carbohydrate, by difference
    '208': 'calories_kcal',  // Energy
    
    // Vitamins
    '320': 'vitamins.A_mcg', // Vitamin A, IU (convert to mcg)
    '401': 'vitamins.C_mg',  // Vitamin C
    '328': 'vitamins.D_mcg', // Vitamin D (D2 + D3)
    '323': 'vitamins.E_mg',  // Vitamin E (alpha-tocopherol)
    '430': 'vitamins.K_mcg', // Vitamin K (phylloquinone)
    '404': 'vitamins.B1_mg', // Thiamin
    '405': 'vitamins.B2_mg', // Riboflavin
    '406': 'vitamins.B3_mg', // Niacin
    '410': 'vitamins.B5_mg', // Pantothenic acid
    '415': 'vitamins.B6_mg', // Vitamin B-6
    '418': 'vitamins.B12_mcg', // Vitamin B-12
    '435': 'vitamins.B9_mcg', // Folate, total
    '421': 'vitamins.B7_mcg', // Biotin
    
    // Minerals
    '301': 'minerals.Ca_mg', // Calcium
    '601': 'minerals.cholesterol_mg', // Cholesterol
    '303': 'minerals.Fe_mg', // Iron
    '304': 'minerals.Mg_mg', // Magnesium
    '305': 'minerals.P_mg',  // Phosphorus
    '306': 'minerals.K_mg',  // Potassium
    '307': 'minerals.Na_mg', // Sodium
    '309': 'minerals.Zn_mg', // Zinc
    '312': 'minerals.Cu_mcg', // Copper
    '315': 'minerals.Mn_mg', // Manganese
    '317': 'minerals.Se_mcg', // Selenium
    '291': 'other.fiber_g',  // Fiber, total dietary
    '269': 'other.sugar_g',  // Sugars, total including NLEA
    '606': 'other.satfat_g', // Fatty acids, total saturated
    '645': 'other.omega3_mg', // Fatty acids, total monounsaturated (approximation)
    '646': 'other.omega6_g'  // Fatty acids, total polyunsaturated (approximation)
  };

  for (const nutrient of fdcData.foodNutrients) {
    const nutrientId = nutrient.nutrientId?.toString();
    const value = nutrient.value || 0;
    
    if (nutrientMap[nutrientId]) {
      const path = nutrientMap[nutrientId].split('.');
      let target = nutrients;
      
      // Navigate to the nested property
      for (let i = 0; i < path.length - 1; i++) {
        target = target[path[i]];
      }
      
      // Set the value
      target[path[path.length - 1]] = value;
    }
  }

  // Special handling for Vitamin A (convert IU to mcg if needed)
  if (nutrients.vitamins.A_mcg > 1000) {
    // Likely in IU, convert to mcg (1 IU = 0.3 mcg for retinol)
    nutrients.vitamins.A_mcg = Math.round(nutrients.vitamins.A_mcg * 0.3);
  }

  return nutrients;
}

// Calculate totals from ingredients using FDC data
async function calculateTotalsFromFDC(ingredients) {
  const totals = makeZeroTotals();
  
  for (const ing of ingredients) {
    console.log(`🔍 Processing: ${ing.name} (${ing.grams}g)`);
    
    // Search FDC for this ingredient
    const fdcId = await searchFDC(ing.name);
    if (!fdcId) {
      console.log(`❌ No FDC data found for: ${ing.name}`);
      continue;
    }
    
    // Fetch nutrient data
    const fdcData = await fetchFDCData(fdcId);
    if (!fdcData) {
      console.log(`❌ Failed to fetch FDC data for: ${ing.name}`);
      continue;
    }
    
    // Extract nutrients
    const nutrients = extractNutrients(fdcData);
    if (!nutrients) {
      console.log(`❌ Failed to extract nutrients for: ${ing.name}`);
      continue;
    }
    
    // Scale by grams/100
    const factor = (ing.grams || 0) / 100;
    console.log(`📊 ${ing.name}: ${ing.grams}g × factor ${factor.toFixed(2)}`);
    
    // Sum macronutrients
    totals.calories_kcal += factor * nutrients.calories_kcal;
    totals.protein_g += factor * nutrients.protein_g;
    totals.fat_g += factor * nutrients.fat_g;
    totals.carbs_g += factor * nutrients.carbs_g;
    
    // Sum vitamins
    for (const [k, v] of Object.entries(nutrients.vitamins)) {
      totals.vitamins[k] += factor * v;
    }
    
    // Sum minerals
    for (const [k, v] of Object.entries(nutrients.minerals)) {
      totals.minerals[k] += factor * v;
    }
    
    // Sum other nutrients
    for (const [k, v] of Object.entries(nutrients.other)) {
      totals.other[k] += factor * v;
    }
  }
  
  return roundTotals(totals);
}

// Calculate DV percentages from totals
function calculateDVPct(totals) {
  const dvPct = { vitamins: {}, minerals: {}, other: {} };
  
  // Calculate vitamin percentages
  for (const [k, v] of Object.entries(totals.vitamins)) {
    const dv = DV.vitamins[k] || 1;
    dvPct.vitamins[k] = Math.round((v / dv) * 100);
  }
  
  // Calculate mineral percentages
  for (const [k, v] of Object.entries(totals.minerals)) {
    const dv = DV.minerals[k] || 1;
    dvPct.minerals[k] = Math.round((v / dv) * 100);
  }
  
  // Calculate other nutrient percentages
  for (const [k, v] of Object.entries(totals.other)) {
    const dv = DV.other[k] || 1;
    dvPct.other[k] = Math.round((v / dv) * 100);
  }
  
  return dvPct;
}

// Round totals appropriately
function roundTotals(totals) {
  const rounded = JSON.parse(JSON.stringify(totals));
  
  // Round macronutrients
  rounded.calories_kcal = Math.round(rounded.calories_kcal);
  rounded.protein_g = Math.round(rounded.protein_g * 10) / 10;
  rounded.fat_g = Math.round(rounded.fat_g * 10) / 10;
  rounded.carbs_g = Math.round(rounded.carbs_g * 10) / 10;
  
  // Round vitamins (mcg values to integers, mg to 1 decimal)
  const mcgVitamins = ['A_mcg', 'D_mcg', 'K_mcg', 'B7_mcg', 'B9_mcg', 'B12_mcg'];
  for (const [k, v] of Object.entries(rounded.vitamins)) {
    rounded.vitamins[k] = mcgVitamins.includes(k) ? Math.round(v) : Math.round(v * 10) / 10;
  }
  
  // Round minerals (mcg values to integers, mg to 1 decimal)
  const mcgMinerals = ['Cr_mcg', 'Cu_mcg', 'I_mcg', 'Mo_mcg', 'Se_mcg'];
  for (const [k, v] of Object.entries(rounded.minerals)) {
    rounded.minerals[k] = mcgMinerals.includes(k) ? Math.round(v) : Math.round(v * 10) / 10;
  }
  
  // Round other nutrients
  for (const [k, v] of Object.entries(rounded.other)) {
    rounded.other[k] = Math.round(v * 10) / 10;
  }
  
  return rounded;
}

// Convert to nutrition.dart format
function convertToNutritionFormat(totals, dvPct) {
  return {
    // Macronutrients
    calories: totals.calories_kcal,
    protein: totals.protein_g,
    fat: totals.fat_g,
    carbs: totals.carbs_g,
    // Micronutrients
    vitamin_a: totals.vitamins.A_mcg,
    vitamin_c: totals.vitamins.C_mg,
    vitamin_d: totals.vitamins.D_mcg,
    vitamin_e: totals.vitamins.E_mg,
    vitamin_k: totals.vitamins.K_mcg,
    vitamin_b1: totals.vitamins.B1_mg,
    vitamin_b2: totals.vitamins.B2_mg,
    vitamin_b3: totals.vitamins.B3_mg,
    vitamin_b5: totals.vitamins.B5_mg,
    vitamin_b6: totals.vitamins.B6_mg,
    vitamin_b7: totals.vitamins.B7_mcg,
    vitamin_b9: totals.vitamins.B9_mcg,
    vitamin_b12: totals.vitamins.B12_mcg,
    calcium: totals.minerals.Ca_mg,
    chloride: totals.minerals.Cl_mg,
    chromium: totals.minerals.Cr_mcg,
    copper: totals.minerals.Cu_mcg,
    fluoride: totals.minerals.F_mg,
    iodine: totals.minerals.I_mcg,
    iron: totals.minerals.Fe_mg,
    magnesium: totals.minerals.Mg_mg,
    manganese: totals.minerals.Mn_mg,
    molybdenum: totals.minerals.Mo_mcg,
    phosphorus: totals.minerals.P_mg,
    potassium: totals.minerals.K_mg,
    selenium: totals.minerals.Se_mcg,
    sodium: totals.minerals.Na_mg,
    zinc: totals.minerals.Zn_mg,
    fiber: totals.other.fiber_g,
    cholesterol: totals.other.cholesterol_mg,
    sugar: totals.other.sugar_g,
    saturated_fats: totals.other.satfat_g,
    omega_3: totals.other.omega3_mg,
    omega_6: totals.other.omega6_g
  };
}

// Test function to verify FDC integration
async function runFDCTest() {
  console.log('🧪 RUNNING FDC INTEGRATION TEST...');
  
  const testIngredients = [
    { name: 'chicken breast', grams: 150 },
    { name: 'sweet potato', grams: 100 },
    { name: 'greek yogurt', grams: 100 },
    { name: 'kimchi', grams: 50 }
  ];
  
  try {
    const totals = await calculateTotalsFromFDC(testIngredients);
    const dvPct = calculateDVPct(totals);
    
    console.log('📊 FDC TEST RESULTS:');
    console.log('Macros:', {
      calories: totals.calories_kcal,
      protein: totals.protein_g,
      fat: totals.fat_g,
      carbs: totals.carbs_g
    });
    console.log('Key Vitamins:', {
      'Vit A (mcg)': totals.vitamins.A_mcg,
      'Vit C (mg)': totals.vitamins.C_mg,
      'Vit K (mcg)': totals.vitamins.K_mcg,
      'B12 (mcg)': totals.vitamins.B12_mcg
    });
    console.log('Key Minerals:', {
      'Iron (mg)': totals.minerals.Fe_mg,
      'Sodium (mg)': totals.minerals.Na_mg,
      'Calcium (mg)': totals.minerals.Ca_mg
    });
    console.log('Cache size:', fdcCache.size);
    
  } catch (error) {
    console.log('❌ FDC test failed:', error.message);
  }
}

// CommonJS exports
module.exports = {
  DV,
  makeZeroTotals,
  calculateTotalsFromFDC,
  calculateDVPct,
  roundTotals,
  convertToNutritionFormat,
  runFDCTest,
  searchFDC,
  fetchFDCData,
  extractNutrients
};
