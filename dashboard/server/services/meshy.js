// meshy api client - text-to-3d generation

const config = require('../config');

const BASE_URL = 'https://api.meshy.ai/openapi/v2';

function getHeaders() {
  const apiKey = config.meshyApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('MESHY_API_KEY not configured'), { status: 503 });
  }
  return {
    Authorization: `Bearer ${apiKey}`,
    'Content-Type': 'application/json',
  };
}

// create a text-to-3d preview task
async function createTask({ prompt, topology, targetPolycount }) {
  if (!prompt || prompt.trim().length === 0) {
    throw Object.assign(new Error('prompt is required'), { status: 400 });
  }

  const body = {
    mode: 'preview',
    prompt: prompt.trim(),
    ai_model: 'meshy-6',
    topology: topology || 'triangle',
    target_polycount: targetPolycount || 30000,
  };

  const response = await fetch(`${BASE_URL}/text-to-3d`, {
    method: 'POST',
    headers: getHeaders(),
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`meshy api error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  const data = await response.json();
  return { taskId: data.result, provider: 'meshy' };
}

// check task status
async function getStatus(taskId) {
  const response = await fetch(`${BASE_URL}/text-to-3d/${taskId}`, {
    headers: getHeaders(),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`meshy status error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  const data = await response.json();

  // normalize status to common format
  const statusMap = {
    PENDING: 'waiting',
    IN_PROGRESS: 'generating',
    SUCCEEDED: 'ready',
    FAILED: 'error',
    CANCELED: 'error',
  };

  return {
    taskId: data.id,
    status: statusMap[data.status] || 'waiting',
    progress: data.progress || 0,
    modelUrls: data.model_urls || null,
    thumbnailUrl: data.thumbnail_url || null,
  };
}

module.exports = { createTask, getStatus };
