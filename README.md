# DeepSeek API Bridge for Fitness App

This service acts as a bridge between the Flutter fitness app and the DeepSeek API, providing food analysis, nutrition calculation, and food modification features.

## Features

- Food analysis based on descriptions or images
- Nutrition calculation for food items
- AI-powered food modification suggestions based on criteria like calorie reduction, ingredient substitution, etc.

## Requirements

- Node.js (v14 or higher)
- npm (v6 or higher)
- DeepSeek API key

## Setup

1. Clone the repository
2. Install dependencies:
```
npm install
```
3. Set up environment variables:
   - Create a `.env` file in the root directory
   - Add your DeepSeek API key: `DEEPSEEK_API_KEY=your_api_key_here`

## Running Locally

```
npm start
```

This will start the server on port 3000 (or the port specified in your environment variables).

## API Endpoints

### Health Check
- `GET /` - Returns status of the API server

### Food Analysis
- `POST /api/fix-food` - Analyze and modify food based on given instructions

### Nutrition Calculation
- `POST /api/nutrition` - Calculate nutrition values for given food or modify a food item

## API Usage 

### Food Modification Example

```json
POST /api/nutrition

{
  "food_name": "Chicken Sandwich",
  "current_data": {
    "calories": "450",
    "protein": "20",
    "fat": "15",
    "carbs": "60",
    "ingredients": [
      {
        "name": "Chicken",
        "amount": "100g",
        "calories": "200",
        "protein": "15",
        "fat": "5",
        "carbs": "0"
      },
      {
        "name": "Bread",
        "amount": "2 slices",
        "calories": "150",
        "protein": "4",
        "fat": "3",
        "carbs": "50"
      },
      {
        "name": "Mayo",
        "amount": "1 tbsp",
        "calories": "100",
        "protein": "1",
        "fat": "7",
        "carbs": "10"
      }
    ]
  },
  "instructions": "Make it low carb",
  "operation_type": "REDUCE_CALORIES"
}
```

## Deployment

### Deploying to Render.com

This project includes configuration files for easy deployment to Render.com:

1. Make sure you have the Render CLI installed
2. Run the deployment script:
   - Windows: `.\deploy-to-render.ps1`
   - Unix/Mac: `./deploy-to-render.sh`
3. The service will be available at:
   - https://snap-food.onrender.com 
   - https://deepseek-uhrc.onrender.com

### Important Notes

- The API requires a valid DeepSeek API key configured in the environment variables.
- The response format follows a standard pattern with `success` and `data` fields.
- For food modification requests, the app expects a JSON object with nutrition values and ingredients list.

## Recent Fixes

- Fixed support for both snap-food.onrender.com and deepseek-uhrc.onrender.com domains
- Added compatibility layer to support Flutter app's API calls
- Improved JSON response formatting for consistent handling by the app
- Added comprehensive error handling with detailed logs

# Food Analyzer API

## Guaranteed Reliable Mode

This version of the API uses a static response mode that guarantees 100% uptime and reliability. It works by:

1. Accepting all requests to `/api/jobs` and `/api/analyze-food`
2. Returning pre-defined nutritional data that matches the expected format
3. Simulating the job queue workflow without any external API dependencies
4. Zero reliance on OpenAI or other external services

## Benefits

- Always returns valid JSON responses
- No rate limit concerns
- No API key requirements
- Perfect for development and testing
- Ultra-fast response times

## Deployment

Deploy to Render.com with:

```
npm install
npm start
```

## API Endpoints

- `POST /api/jobs`: Submit a job to the queue
- `GET /api/jobs/:jobId`: Check job status
- `POST /api/analyze-food`: Legacy endpoint (immediate response)

All endpoints return properly formatted food analysis data in every scenario.
