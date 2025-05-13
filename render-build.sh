#!/bin/bash
# Build script for Render.com deployment

# Copy necessary files
cp api-server/server.js server.js

# Install dependencies
npm install

# Create a basic .env file if it doesn't exist
if [ ! -f .env ]; then
  echo "Creating .env file..."
  echo "# Configuration for Food Analyzer API" > .env
  echo "PORT=3000" >> .env
  echo "NODE_ENV=production" >> .env
  
  # The actual value should be set in Render.com environment variables
  echo "# OpenAI API key - set in Render Dashboard" >> .env
  echo "OPENAI_API_KEY=${OPENAI_API_KEY}" >> .env
fi

echo "Build completed successfully!" 