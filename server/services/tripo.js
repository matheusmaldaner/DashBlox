// tripo3d api client - text-to-3d generation

const config = require('../config');

const BASE_URL = 'https://api.tripo3d.ai/v2/openapi';

function getHeaders() {
  const apiKey = config.tripoApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('TRIPO_API_KEY not configured'), { status: 503 });
  }
  return {
    Authorization: `Bearer ${apiKey}`,
    'Content-Type': 'application/json',
  };
}

// create a text-to-3d task
async function createTask({ prompt }) {
  if (!prompt || prompt.trim().length === 0) {
    throw Object.assign(new Error('prompt is required'), { status: 400 });
  }

  const body = {
    type: 'text_to_model',
    prompt: prompt.trim(),
  };

  const response = await fetch(`${BASE_URL}/task`, {
    method: 'POST',
    headers: getHeaders(),
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`tripo api error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  const data = await response.json();

  if (data.code !== 0) {
    throw Object.assign(
      new Error(`tripo api error: ${data.message || 'unknown'}`),
      { status: 400 }
    );
  }

  return { taskId: data.data.task_id, provider: 'tripo' };
}

// check task status
async function getStatus(taskId) {
  const response = await fetch(`${BASE_URL}/task/${taskId}`, {
    headers: getHeaders(),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`tripo status error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  const data = await response.json();
  const task = data.data;

  // normalize status
  const statusMap = {
    submitted: 'waiting',
    processing: 'generating',
    success: 'ready',
    failed: 'error',
  };

  return {
    taskId: task.task_id,
    status: statusMap[task.status] || 'waiting',
    progress: task.status === 'success' ? 100 : task.status === 'processing' ? 50 : 0,
    modelUrls: task.output
      ? { glb: task.output.model, pbr_glb: task.output.pbr_model }
      : null,
    thumbnailUrl: null,
  };
}

module.exports = { createTask, getStatus };
