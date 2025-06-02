// Test script to verify the nutrition API returns all 34 micronutrients
const fetch = require('node-fetch');

// Test image (base64 encoded small test image)
const testImageBase64 = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=';

async function testNutritionAPI() {
  try {
    console.log('🧪 Testing Nutrition API...');
    
    const response = await fetch('http://localhost:3000/api/analyze-food', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        image: testImageBase64
      })
    });

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    const result = await response.json();
    
    if (result.success && result.data) {
      const data = result.data;
      
      console.log('✅ API Response received successfully');
      console.log('📊 Meal Name:', data.meal_name);
      console.log('🍽️ Ingredients:', data.ingredients?.length || 0);
      
      // Check for all 34 nutrients
      const expectedNutrients = [
        // Vitamins (13)
        'vitamin_a', 'vitamin_c', 'vitamin_d', 'vitamin_e', 'vitamin_k',
        'vitamin_b1', 'vitamin_b2', 'vitamin_b3', 'vitamin_b5', 'vitamin_b6',
        'vitamin_b7', 'vitamin_b9', 'vitamin_b12',
        // Minerals (15)
        'calcium', 'chloride', 'chromium', 'copper', 'fluoride', 'iodine',
        'iron', 'magnesium', 'manganese', 'molybdenum', 'phosphorus',
        'potassium', 'selenium', 'sodium', 'zinc',
        // Other (6)
        'fiber', 'cholesterol', 'sugar', 'saturated_fats', 'omega_3', 'omega_6'
      ];
      
      let foundNutrients = 0;
      let missingNutrients = [];
      
      expectedNutrients.forEach(nutrient => {
        if (data.hasOwnProperty(nutrient)) {
          foundNutrients++;
          console.log(`✅ ${nutrient}: ${data[nutrient]}`);
        } else {
          missingNutrients.push(nutrient);
        }
      });
      
      console.log(`\n📈 NUTRITION ANALYSIS RESULTS:`);
      console.log(`✅ Found nutrients: ${foundNutrients}/34`);
      console.log(`❌ Missing nutrients: ${missingNutrients.length}`);
      
      if (missingNutrients.length > 0) {
        console.log(`Missing: ${missingNutrients.join(', ')}`);
      }
      
      if (foundNutrients === 34) {
        console.log('🎉 SUCCESS: All 34 micronutrients are present!');
      } else {
        console.log('⚠️ WARNING: Some micronutrients are missing from the response');
      }
      
    } else {
      console.log('❌ API Error:', result.error || 'Unknown error');
    }
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
  }
}

// Run the test
testNutritionAPI(); 