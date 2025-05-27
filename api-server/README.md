# SnapFood API Server with Job Queue

A scalable API server for SnapFood that uses a job queue system to handle food image analysis at scale without hitting OpenAI's rate limits.

## Architecture

This system is designed to handle up to 10,000 concurrent users by:

1. **Memory-based Job Queue**: Using better-queue to manage analysis requests
2. **Token Bucket Rate Limiting**: Ensuring OpenAI API calls respect your organization's TPM (tokens per minute) limit
3. **File-based Job Storage**: Persisting job status on disk for reliability
4. **Progressive Status Updates**: Providing real-time job status to clients

## Prerequisites

- Node.js 16+
- OpenAI API key

## Setup

1. Install dependencies:
   ```
   npm install
   ```

2. Copy `.env.example` to `.env` and fill in your configuration:
   ```
   cp .env.example .env
   ```

3. Create a `jobs` directory for storing job data:
   ```
   mkdir -p jobs
   ```

## Starting the Server

Run the server:

```
npm start
```

For development with auto-reload:

```
npm run dev
```

## Scaling for Production

For high volume on Render.com:

1. Set `MAX_TOKENS_PER_MINUTE` to your organization's limit (default OpenAI is 10,000 TPM)

2. Ensure the `/jobs` directory exists and is writable 

3. To scale horizontally, use Render.com's auto-scaling features

## API Endpoints

### Submit a Job

```
POST /api/jobs
```

Request body:
```json
{
  "image": "data:image/jpeg;base64,/9j/4AAQSkZJRgABA...",
  "userId": "optional-user-id"
}
```

Response:
```json
{
  "success": true,
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "pending"
}
```

### Check Job Status

```
GET /api/jobs/:jobId
```

Response (pending):
```json
{
  "success": true,
  "status": "processing",
  "progress": 30,
  "message": "Image processed, waiting for analysis..."
}
```

Response (completed):
```json
{
  "success": true,
  "status": "completed",
  "progress": 100,
  "data": {
    "meal_name": "Grilled Salmon with Vegetables",
    "ingredients": [...],
    "ingredient_nutrients": [...]
  }
}
```

### Legacy API (Backward Compatible)

```
POST /api/analyze-food
```

This endpoint is maintained for backward compatibility and internally uses the job queue system.

## Client Integration

The Flutter client has been updated to work with the new job queue system. It:

1. Submits jobs via the new `/api/jobs` endpoint
2. Polls the `/api/jobs/:jobId` endpoint until job completion
3. Provides progress updates to the user

## Monitoring

Monitor Redis queue health with tools like Redis Commander or Redis Insight. 