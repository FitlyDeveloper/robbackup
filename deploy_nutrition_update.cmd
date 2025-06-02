@echo off
echo 🚀 Deploying Enhanced Nutrition Analysis Server to Render.com...
echo.
echo 📊 Features:
echo   - Complete 34 micronutrient analysis
echo   - Ingredient-by-ingredient breakdown
echo   - Permanent storage integration
echo   - Enhanced OpenAI prompts
echo.

echo 📝 Adding files to git...
git add server.js
git add api-server/100_percent_reliable.js
git add lib/NewScreens/SnapFood.dart
git add test_nutrition_api.js

echo 💾 Committing changes...
git commit -m "Enhanced nutrition analysis: Complete 34 micronutrient extraction and permanent storage integration"

echo 🌐 Pushing to Render.com...
git push origin main

echo.
echo ✅ Deployment complete!
echo 🔗 Your enhanced nutrition API should be live at: https://snap-food.onrender.com
echo.
echo 🧪 Test the API with: node test_nutrition_api.js
echo.
pause 