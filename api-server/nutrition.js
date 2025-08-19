// FDA Daily Values (2020-2025)
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

// Create zero totals structure
function makeZeroTotals() {
  return {
    // Macronutrients
    calories: 0,
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

// Pure function to sum nutrient totals from ingredients
function sumTotals(ingredients, per100DB) {
  const totals = makeZeroTotals();
  
  for (const ing of ingredients) {
    const ref = per100DB[ing.name]; 
    if (!ref) {
      console.log(`❌ No DB entry for: ${ing.name}`);
      continue;
    }
    
    const factor = (ing.grams || 0) / 100;
    console.log(`📊 ${ing.name}: ${ing.grams}g × factor ${factor}`);
    
    // Sum macronutrients
    totals.calories += factor * (ref.calories || 0);
    totals.protein_g += factor * (ref.protein_g || 0);
    totals.fat_g += factor * (ref.fat_g || 0);
    totals.carbs_g += factor * (ref.carbs_g || 0);
    
    // Sum vitamins
    for (const k of Object.keys(totals.vitamins)) {
      const src = ref.vitamins?.[k] ?? 0;
      totals.vitamins[k] += factor * src;
    }
    
    // Sum minerals
    for (const k of Object.keys(totals.minerals)) {
      const src = ref.minerals?.[k] ?? 0;
      totals.minerals[k] += factor * src;
    }
    
    // Sum other nutrients
    for (const k of Object.keys(totals.other)) {
      const src = ref.other?.[k] ?? 0;
      totals.other[k] += factor * src;
    }
  }
  
  return roundTotals(totals);
}

// Calculate DV percentages from totals (not vice versa)
function toDvPct(totals, DV) {
  const pct = { vitamins: {}, minerals: {}, other: {} };
  
  for (const [k, v] of Object.entries(totals.vitamins)) {
    pct.vitamins[k] = Math.round((v / DV.vitamins[k]) * 100);
  }
  
  for (const [k, v] of Object.entries(totals.minerals)) {
    pct.minerals[k] = Math.round((v / DV.minerals[k]) * 100);
  }
  
  for (const [k, v] of Object.entries(totals.other)) {
    pct.other[k] = Math.round((v / DV.other[k]) * 100);
  }
  
  return pct;
}

// Unit safety and rounding
function roundTotals(t) {
  const R = JSON.parse(JSON.stringify(t));
  
  // Keys that should be integers (mcg values)
  const intKeys = [
    'A_mcg', 'D_mcg', 'K_mcg', 'B7_mcg', 'B9_mcg', 'B12_mcg',
    'Cr_mcg', 'Cu_mcg', 'I_mcg', 'Mo_mcg', 'Se_mcg'
  ];
  
  const oneDec = (x) => Math.round(x * 10) / 10;
  
  // Round macronutrients
  R.calories = Math.round(R.calories);
  R.protein_g = oneDec(R.protein_g);
  R.fat_g = oneDec(R.fat_g);
  R.carbs_g = oneDec(R.carbs_g);
  
  const walk = (obj, ints = false) => {
    Object.keys(obj).forEach(k => {
      if (typeof obj[k] !== 'number') return;
      obj[k] = ints || intKeys.includes(k) ? Math.round(obj[k]) : oneDec(obj[k]);
    });
  };
  
  walk(R.vitamins);
  walk(R.minerals);
  walk(R.other);
  
  return R;
}

// Convert nutrition.dart format to our internal format
function convertToInternalFormat(nutritionData) {
  return {
    vitamins: {
      A_mcg: nutritionData.vitamin_a || 0,
      C_mg: nutritionData.vitamin_c || 0,
      D_mcg: nutritionData.vitamin_d || 0,
      E_mg: nutritionData.vitamin_e || 0,
      K_mcg: nutritionData.vitamin_k || 0,
      B1_mg: nutritionData.vitamin_b1 || 0,
      B2_mg: nutritionData.vitamin_b2 || 0,
      B3_mg: nutritionData.vitamin_b3 || 0,
      B5_mg: nutritionData.vitamin_b5 || 0,
      B6_mg: nutritionData.vitamin_b6 || 0,
      B7_mcg: nutritionData.vitamin_b7 || 0,
      B9_mcg: nutritionData.vitamin_b9 || 0,
      B12_mcg: nutritionData.vitamin_b12 || 0
    },
    minerals: {
      Ca_mg: nutritionData.calcium || 0,
      Cl_mg: nutritionData.chloride || 0,
      Cr_mcg: nutritionData.chromium || 0,
      Cu_mcg: nutritionData.copper || 0,
      F_mg: nutritionData.fluoride || 0,
      I_mcg: nutritionData.iodine || 0,
      Fe_mg: nutritionData.iron || 0,
      Mg_mg: nutritionData.magnesium || 0,
      Mn_mg: nutritionData.manganese || 0,
      Mo_mcg: nutritionData.molybdenum || 0,
      P_mg: nutritionData.phosphorus || 0,
      K_mg: nutritionData.potassium || 0,
      Se_mcg: nutritionData.selenium || 0,
      Na_mg: nutritionData.sodium || 0,
      Zn_mg: nutritionData.zinc || 0
    },
    other: {
      fiber_g: nutritionData.fiber || 0,
      cholesterol_mg: nutritionData.cholesterol || 0,
      sugar_g: nutritionData.sugar || 0,
      satfat_g: nutritionData.saturated_fats || 0,
      omega3_mg: nutritionData.omega_3 || 0,
      omega6_g: nutritionData.omega_6 || 0
    }
  };
}

// Convert internal format back to nutrition.dart format
function convertToNutritionFormat(internalData) {
  return {
    // Macronutrients
    calories: internalData.calories,
    protein: internalData.protein_g,
    fat: internalData.fat_g,
    carbs: internalData.carbs_g,
    // Micronutrients
    vitamin_a: internalData.vitamins.A_mcg,
    vitamin_c: internalData.vitamins.C_mg,
    vitamin_d: internalData.vitamins.D_mcg,
    vitamin_e: internalData.vitamins.E_mg,
    vitamin_k: internalData.vitamins.K_mcg,
    vitamin_b1: internalData.vitamins.B1_mg,
    vitamin_b2: internalData.vitamins.B2_mg,
    vitamin_b3: internalData.vitamins.B3_mg,
    vitamin_b5: internalData.vitamins.B5_mg,
    vitamin_b6: internalData.vitamins.B6_mg,
    vitamin_b7: internalData.vitamins.B7_mcg,
    vitamin_b9: internalData.vitamins.B9_mcg,
    vitamin_b12: internalData.vitamins.B12_mcg,
    calcium: internalData.minerals.Ca_mg,
    chloride: internalData.minerals.Cl_mg,
    chromium: internalData.minerals.Cr_mcg,
    copper: internalData.minerals.Cu_mcg,
    fluoride: internalData.minerals.F_mg,
    iodine: internalData.minerals.I_mcg,
    iron: internalData.minerals.Fe_mg,
    magnesium: internalData.minerals.Mg_mg,
    manganese: internalData.minerals.Mn_mg,
    molybdenum: internalData.minerals.Mo_mcg,
    phosphorus: internalData.minerals.P_mg,
    potassium: internalData.minerals.K_mg,
    selenium: internalData.minerals.Se_mcg,
    sodium: internalData.minerals.Na_mg,
    zinc: internalData.minerals.Zn_mg,
    fiber: internalData.other.fiber_g,
    cholesterol: internalData.other.cholesterol_mg,
    sugar: internalData.other.sugar_g,
    saturated_fats: internalData.other.satfat_g,
    omega_3: internalData.other.omega3_mg,
    omega_6: internalData.other.omega6_g
  };
}

// USDA/FDC database lookup (per 100g values)
function getPer100DB(ingredientName) {
  const db = {
    // Test case ingredients (150g peach + 100g apricot should return ~107 kcal, 2.8g protein, 0.8g fat, 26g carbs, 18mg Vit C, 96µg Vit A)
    'peach': {
      calories: 39, protein_g: 0.9, fat_g: 0.3, carbs_g: 10.0,
      vitamins: { A_mcg: 16, C_mg: 6.6, D_mcg: 0, E_mg: 0.7, K_mcg: 2.6, B1_mg: 0.0, B2_mg: 0.0, B3_mg: 0.8, B5_mg: 0.2, B6_mg: 0.0, B7_mcg: 0, B9_mcg: 4, B12_mcg: 0 },
      minerals: { Ca_mg: 6, Cl_mg: 0, Cr_mcg: 0, Cu_mcg: 0.1, F_mg: 0, I_mcg: 0, Fe_mg: 0.3, Mg_mg: 9, Mn_mg: 0.1, Mo_mcg: 0, P_mg: 20, K_mg: 190, Se_mcg: 0.1, Na_mg: 0, Zn_mg: 0.2 },
      other: { fiber_g: 1.5, cholesterol_mg: 0, sugar_g: 8.4, satfat_g: 0, omega3_mg: 0, omega6_g: 0 }
    },
    'apricot': {
      calories: 48, protein_g: 1.4, fat_g: 0.4, carbs_g: 11.1,
      vitamins: { A_mcg: 96, C_mg: 10.0, D_mcg: 0, E_mg: 0.9, K_mcg: 3.3, B1_mg: 0.0, B2_mg: 0.0, B3_mg: 0.6, B5_mg: 0.2, B6_mg: 0.1, B7_mcg: 0, B9_mcg: 9, B12_mcg: 0 },
      minerals: { Ca_mg: 13, Cl_mg: 0, Cr_mcg: 0, Cu_mcg: 0.1, F_mg: 0, I_mcg: 0, Fe_mg: 0.4, Mg_mg: 10, Mn_mg: 0.1, Mo_mcg: 0, P_mg: 23, K_mg: 259, Se_mcg: 0.1, Na_mg: 1, Zn_mg: 0.2 },
      other: { fiber_g: 2.0, cholesterol_mg: 0, sugar_g: 9.2, satfat_g: 0, omega3_mg: 0, omega6_g: 0 }
    },
    // Original test case ingredients
    'chicken breast': {
      calories: 165, protein_g: 31.0, fat_g: 3.6, carbs_g: 0.0,
      vitamins: { A_mcg: 6, C_mg: 0, D_mcg: 0, E_mg: 0.2, K_mcg: 0, B1_mg: 0.1, B2_mg: 0.1, B3_mg: 13.7, B5_mg: 1.0, B6_mg: 0.6, B7_mcg: 0.1, B9_mcg: 4, B12_mcg: 0.3 },
      minerals: { Ca_mg: 15, Cl_mg: 77, Cr_mcg: 0, Cu_mcg: 0.1, F_mg: 0, I_mcg: 7, Fe_mg: 1.0, Mg_mg: 29, Mn_mg: 0.0, Mo_mcg: 0, P_mg: 228, K_mg: 256, Se_mcg: 27.6, Na_mg: 74, Zn_mg: 1.0 },
      other: { fiber_g: 0, cholesterol_mg: 85, sugar_g: 0, satfat_g: 1.1, omega3_mg: 30, omega6_g: 0.5 }
    },
    'sweet potato': {
      calories: 86, protein_g: 1.6, fat_g: 0.1, carbs_g: 20.1,
      vitamins: { A_mcg: 709, C_mg: 2.4, D_mcg: 0, E_mg: 0.3, K_mcg: 1.8, B1_mg: 0.1, B2_mg: 0.1, B3_mg: 0.6, B5_mg: 0.8, B6_mg: 0.2, B7_mcg: 0, B9_mcg: 11, B12_mcg: 0 },
      minerals: { Ca_mg: 30, Cl_mg: 0, Cr_mcg: 0, Cu_mcg: 0.1, F_mg: 0, I_mcg: 0, Fe_mg: 0.6, Mg_mg: 25, Mn_mg: 0.3, Mo_mcg: 0, P_mg: 47, K_mg: 337, Se_mcg: 0.6, Na_mg: 55, Zn_mg: 0.3 },
      other: { fiber_g: 3.0, cholesterol_mg: 0, sugar_g: 4.2, satfat_g: 0, omega3_mg: 0, omega6_g: 0 }
    },
    'greek yogurt': {
      calories: 59, protein_g: 10.0, fat_g: 0.4, carbs_g: 3.6,
      vitamins: { A_mcg: 27, C_mg: 0.8, D_mcg: 0.1, E_mg: 0.1, K_mcg: 0.2, B1_mg: 0.1, B2_mg: 0.2, B3_mg: 0.2, B5_mg: 0.6, B6_mg: 0.1, B7_mcg: 0, B9_mcg: 12, B12_mcg: 0.5 },
      minerals: { Ca_mg: 115, Cl_mg: 0, Cr_mcg: 0, Cu_mcg: 0, F_mg: 0, I_mcg: 0, Fe_mg: 0.1, Mg_mg: 11, Mn_mg: 0, Mo_mcg: 0, P_mg: 135, K_mg: 141, Se_mcg: 9.7, Na_mg: 36, Zn_mg: 0.5 },
      other: { fiber_g: 0, cholesterol_mg: 13, sugar_g: 3.2, satfat_g: 0.4, omega3_mg: 0, omega6_g: 0 }
    },
    'kimchi': {
      calories: 23, protein_g: 2.0, fat_g: 0.5, carbs_g: 4.5,
      vitamins: { A_mcg: 49, C_mg: 21.0, D_mcg: 0, E_mg: 0.1, K_mcg: 43.6, B1_mg: 0.1, B2_mg: 0.2, B3_mg: 1.1, B5_mg: 0.2, B6_mg: 0.2, B7_mcg: 0, B9_mcg: 43, B12_mcg: 0 },
      minerals: { Ca_mg: 33, Cl_mg: 0, Cr_mcg: 0, Cu_mcg: 0.1, F_mg: 0, I_mcg: 0, Fe_mg: 2.5, Mg_mg: 14, Mn_mg: 0.2, Mo_mcg: 0, P_mg: 24, K_mg: 151, Se_mcg: 0.5, Na_mg: 498, Zn_mg: 0.2 },
      other: { fiber_g: 1.6, cholesterol_mg: 0, sugar_g: 1.1, satfat_g: 0, omega3_mg: 0, omega6_g: 0 }
    },
    // Additional common ingredients
    'white rice': {
      calories: 130, protein_g: 2.7, fat_g: 0.3, carbs_g: 28.0,
      vitamins: { A_mcg: 0, C_mg: 0, D_mcg: 0, E_mg: 0.1, K_mcg: 0, B1_mg: 0.1, B2_mg: 0.0, B3_mg: 1.6, B5_mg: 0.4, B6_mg: 0.1, B7_mcg: 0, B9_mcg: 8, B12_mcg: 0 },
      minerals: { Ca_mg: 28, Cl_mg: 0, Cr_mcg: 0, Cu_mcg: 0.2, F_mg: 0, I_mcg: 0, Fe_mg: 0.8, Mg_mg: 25, Mn_mg: 1.1, Mo_mcg: 0, P_mg: 115, K_mg: 115, Se_mcg: 15.1, Na_mg: 5, Zn_mg: 1.2 },
      other: { fiber_g: 0.4, cholesterol_mg: 0, sugar_g: 0.1, satfat_g: 0.1, omega3_mg: 0, omega6_g: 0.1 }
    },
    'tomato': {
      calories: 18, protein_g: 0.9, fat_g: 0.2, carbs_g: 3.9,
      vitamins: { A_mcg: 833, C_mg: 13.7, D_mcg: 0, E_mg: 0.5, K_mcg: 7.9, B1_mg: 0.1, B2_mg: 0.0, B3_mg: 0.6, B5_mg: 0.1, B6_mg: 0.1, B7_mcg: 0, B9_mcg: 15, B12_mcg: 0 },
      minerals: { Ca_mg: 10, Cl_mg: 0, Cr_mcg: 0, Cu_mcg: 0.1, F_mg: 0, I_mcg: 0, Fe_mg: 0.3, Mg_mg: 11, Mn_mg: 0.1, Mo_mcg: 0, P_mg: 24, K_mg: 237, Se_mcg: 0, Na_mg: 5, Zn_mg: 0.2 },
      other: { fiber_g: 1.2, cholesterol_mg: 0, sugar_g: 2.6, satfat_g: 0, omega3_mg: 0, omega6_g: 0.1 }
    },
    'bread': {
      calories: 265, protein_g: 9.0, fat_g: 3.2, carbs_g: 49.0,
      vitamins: { A_mcg: 0, C_mg: 0, D_mcg: 0, E_mg: 0.3, K_mcg: 0.2, B1_mg: 0.2, B2_mg: 0.1, B3_mg: 3.1, B5_mg: 0.3, B6_mg: 0.1, B7_mcg: 0, B9_mcg: 50, B12_mcg: 0 },
      minerals: { Ca_mg: 165, Cl_mg: 0, Cr_mcg: 0, Cu_mcg: 0.2, F_mg: 0, I_mcg: 0, Fe_mg: 3.6, Mg_mg: 25, Mn_mg: 0.7, Mo_mcg: 0, P_mg: 98, K_mg: 125, Se_mcg: 30.0, Na_mg: 491, Zn_mg: 1.0 },
      other: { fiber_g: 2.7, cholesterol_mg: 0, sugar_g: 3.1, satfat_g: 0.4, omega3_mg: 0, omega6_g: 0.8 }
    }
  };
  
  // Smart key matching (case insensitive, partial matches)
  const key = Object.keys(db).find(k => 
    ingredientName.toLowerCase().includes(k.toLowerCase()) ||
    k.toLowerCase().includes(ingredientName.toLowerCase())
  );
  
  return key ? db[key] : null;
}

// Sanity checks to reject hallucinations
function validateResults(totals, ingredients) {
  const warnings = [];
  
  // Check Vitamin A (should be < 2000 mcg unless orange tubers/leafy greens present)
  const hasOrangeTubers = ingredients.some(ing => 
    ing.name.toLowerCase().includes('sweet potato') || 
    ing.name.toLowerCase().includes('carrot') ||
    ing.name.toLowerCase().includes('pumpkin')
  );
  const hasLeafyGreens = ingredients.some(ing => 
    ing.name.toLowerCase().includes('spinach') || 
    ing.name.toLowerCase().includes('kale') ||
    ing.name.toLowerCase().includes('lettuce')
  );
  
  if (totals.vitamins.A_mcg > 2000 && !hasOrangeTubers && !hasLeafyGreens) {
    warnings.push(`⚠️ Vitamin A (${totals.vitamins.A_mcg} mcg) seems high without orange tubers/leafy greens`);
  }
  
  // Check Vitamin C for kimchi (should be ≥10 mg per 50g)
  const kimchiIngredient = ingredients.find(ing => ing.name.toLowerCase().includes('kimchi'));
  if (kimchiIngredient && totals.vitamins.C_mg < 5) {
    warnings.push(`⚠️ Vitamin C (${totals.vitamins.C_mg} mg) seems low for kimchi`);
  }
  
  // Check Vitamin K for kimchi (should be in tens of µg)
  if (kimchiIngredient && totals.vitamins.K_mcg < 10) {
    warnings.push(`⚠️ Vitamin K (${totals.vitamins.K_mcg} mcg) seems low for kimchi`);
  }
  
  // Check B12 (should be reasonable for animal products)
  const hasAnimalProducts = ingredients.some(ing => 
    ing.name.toLowerCase().includes('chicken') || 
    ing.name.toLowerCase().includes('beef') ||
    ing.name.toLowerCase().includes('fish') ||
    ing.name.toLowerCase().includes('yogurt') ||
    ing.name.toLowerCase().includes('milk')
  );
  
  if (hasAnimalProducts && totals.vitamins.B12_mcg > 5) {
    warnings.push(`⚠️ Vitamin B12 (${totals.vitamins.B12_mcg} mcg) seems very high`);
  }
  
  return warnings;
}

// Test function to verify calculations
function runTestCases() {
  console.log('🧪 RUNNING NUTRITION TEST CASES...');
  
  // Test case 1: 150g peach + 100g apricot
  const testCase1 = [
    { name: 'peach', grams: 150 },
    { name: 'apricot', grams: 100 }
  ];
  
  const per100DB = {};
  for (const ing of testCase1) {
    per100DB[ing.name] = getPer100DB(ing.name);
  }
  
  const totals1 = sumTotals(testCase1, per100DB);
  
  console.log('📊 TEST CASE 1: 150g peach + 100g apricot');
  console.log('Expected: ~107 kcal, 2.8g protein, 0.8g fat, 26g carbs, 18mg Vit C, 96µg Vit A');
  console.log('Actual:', {
    calories: totals1.calories,
    protein_g: totals1.protein_g,
    fat_g: totals1.fat_g,
    carbs_g: totals1.carbs_g,
    'Vit C (mg)': totals1.vitamins.C_mg,
    'Vit A (mcg)': totals1.vitamins.A_mcg
  });
  
  // Test case 2: 150g chicken + 100g sweet potato + 100g greek yogurt + 50g kimchi
  const testCase2 = [
    { name: 'chicken breast', grams: 150 },
    { name: 'sweet potato', grams: 100 },
    { name: 'greek yogurt', grams: 100 },
    { name: 'kimchi', grams: 50 }
  ];
  
  const per100DB2 = {};
  for (const ing of testCase2) {
    per100DB2[ing.name] = getPer100DB(ing.name);
  }
  
  const totals2 = sumTotals(testCase2, per100DB2);
  
  console.log('\n📊 TEST CASE 2: 150g chicken + 100g sweet potato + 100g greek yogurt + 50g kimchi');
  console.log('Expected: ~700-1000 mcg Vit A, ~10-25 mg Vit C, ~1.1-1.4 µg B12');
  console.log('Actual:', {
    calories: totals2.calories,
    protein_g: totals2.protein_g,
    fat_g: totals2.fat_g,
    carbs_g: totals2.carbs_g,
    'Vit A (mcg)': totals2.vitamins.A_mcg,
    'Vit C (mg)': totals2.vitamins.C_mg,
    'Vit K (mcg)': totals2.vitamins.K_mcg,
    'B12 (mcg)': totals2.vitamins.B12_mcg,
    'Iron (mg)': totals2.minerals.Fe_mg,
    'Sodium (mg)': totals2.minerals.Na_mg
  });
  
  console.log('\n✅ Test cases completed');
}

// CommonJS exports
module.exports = {
  DV,
  makeZeroTotals,
  sumTotals,
  toDvPct,
  roundTotals,
  convertToInternalFormat,
  convertToNutritionFormat,
  getPer100DB,
  validateResults,
  runTestCases
};
