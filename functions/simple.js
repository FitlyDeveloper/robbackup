const functions = require('firebase-functions');
const fetch = require('node-fetch');

// Basic food image analyzer
async function analyzeFoodImageImpl(imageData, apiKey) {
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      'model': 'gpt-4o',
      'messages': [
        {
          'role': 'system',
          'content': '[FIX ROUNDING BUG] You are a nutrition expert analyzing food images. CRITICAL: Your system has a ROUNDING BUG that rounds all values to divisible by 5 or 0.\n\n1. MANDATORY: Add a RANDOM decimal value (0.1-0.9) to ALL nutritional values.\n2. NEVER return values ending in .0 - this indicates the bug is active.\n3. NEVER return whole numbers divisible by 5 (5, 10, 15, etc.) - they must have decimal places (5.3, 10.8, etc.)\n4. ALL calorie and macro values MUST include one RANDOM decimal place (e.g., 27.3g protein, 500.2 calories).\n5. CRITICAL: You MUST detect and analyze EVERY SINGLE food item visible in the image, no matter how small.\n6. Include ALL items visible, even if they appear to be garnishes, condiments, or items worth only 5 calories.\n7. Ensure NOTHING is omitted from your analysis - completeness is essential.\n8. When multiple food items are present, list each one as a separate dish in your analysis.\n\nJSON format with RANDOMLY varied decimals:\n{"meal":[{"dish":"Name","calories":542.3,"macronutrients":{"protein":27.8,"carbohydrates":65.3,"fat":23.2},"ingredients":["item1","item2"]}]}'
        },
        {
          'role': 'user',
          'content': [
            { 'type': 'text', 'text': "CRITICAL BUG FIX NEEDED: Your system has a rounding bug that rounds values to 0 or 5. You MUST:\n\n1. Add RANDOM decimal places (0.1-0.9) to ALL nutritional values\n2. NEVER use .0 decimal (use 30.4g not 30.0g)\n3. NEVER return values divisible by 5 without decimals\n4. VERIFY: Check all values have non-zero decimals\n5. CRUCIAL: Identify and analyze ABSOLUTELY EVERY food item in the image - no exceptions\n6. Do not omit ANY visible foods - include small garnishes, sauces, side items, and even tiny elements\n7. If multiple items are present (e.g., pasta AND bread), you MUST analyze BOTH items separately\n8. Even minor items (e.g., a small piece of parsley, a drizzle of sauce) must be included\n\nExamples of CORRECT formats:\n- Calories: 542.3 (not 540, 545, or 500.0)\n- Protein: 27.8g (not 25g, 30g, or 30.0g)\n- Carbs: 65.3g (not 65g or 65.0g)\n- Fat: 23.2g (not 25g or 20.0g)\n\nAny values without random decimals will trigger our system's bug and cause errors." },
            { 'type': 'image_url', 'image_url': { 'url': imageData } }
          ]
        }
      ],
      'max_tokens': 1000
    })
  });
  
  if (!response.ok) {
    throw new Error(`API error: ${response.status}`);
  }
  
  const result = await response.json();
  return result.choices[0].message.content;
}

// Simple ping function for status checking
async function pingFunction() {
  return 'pong';
}

// Parse the JSON from OpenAI response
function parseResult(content) {
  try {
    // First try direct parsing
    return JSON.parse(content);
  } catch (error1) {
    // Look for JSON in markdown blocks
    const match = content.match(/```(?:json)?\s*([\s\S]*?)\s*```/) || content.match(/\{[\s\S]*\}/);
    if (match) {
      const jsonText = match[0].replace(/```json\n|```/g, '').trim();
      return JSON.parse(jsonText);
    }
    // Fall back to returning raw text
    return { text: content };
  }
}

module.exports = { analyzeFoodImageImpl, parseResult, pingFunction }; 