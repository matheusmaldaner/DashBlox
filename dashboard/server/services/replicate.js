// replicate api client - trellis image-to-3d generation

const config = require('../config');

const BASE_URL = 'https://api.replicate.com/v1';
const TRELLIS_VERSION = 'e8f6c45206993f297372f5436b90350817bd9b4a0d52d2a76df50c1c8afa2b3c';

function getHeaders() {
  const apiKey = config.replicateApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('REPLICATE_API_KEY not configured'), { status: 503 });
  }
  return {
    Authorization: `Bearer ${apiKey}`,
    'Content-Type': 'application/json',
  };
}

// text-to-3d is not supported by trellis
async function createTask() {
  throw Object.assign(
    new Error('replicate/trellis only supports image-to-3d mode'),
    { status: 400 }
  );
}

// create an image-to-3d prediction via trellis
async function createImageTask({ imageUrl }) {
  if (!imageUrl) {
    throw Object.assign(new Error('image url is required'), { status: 400 });
  }

  const body = {
    version: TRELLIS_VERSION,
    input: {
      images: [imageUrl],
      generate_model: true,
      generate_color: true,
      generate_normal: false,
      save_gaussian_ply: false,
      mesh_simplify: 0.95,
      texture_size: 1024,
      ss_sampling_steps: 12,
      ss_guidance_strength: 7.5,
      slat_sampling_steps: 12,
      slat_guidance_strength: 3,
      randomize_seed: true,
    },
  };

  const response = await fetch(`${BASE_URL}/predictions`, {
    method: 'POST',
    headers: getHeaders(),
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`replicate api error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  const data = await response.json();
  return { taskId: data.id, provider: 'replicate' };
}

// poll prediction status
async function getStatus(taskId) {
  const response = await fetch(`${BASE_URL}/predictions/${taskId}`, {
    headers: { Authorization: `Bearer ${config.replicateApiKey}` },
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`replicate status error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  const data = await response.json();

  // normalize replicate statuses to common format
  const statusMap = {
    starting: 'waiting',
    processing: 'generating',
    succeeded: 'ready',
    failed: 'error',
    canceled: 'error',
  };

  // extract model urls from output
  let modelUrls = null;
  let thumbnailUrl = null;
  if (data.output) {
    modelUrls = {};
    if (data.output.model_file) modelUrls.glb = data.output.model_file;
    if (data.output.color_video) thumbnailUrl = data.output.color_video;
  }

  // estimate progress from status
  let progress = 0;
  if (data.status === 'processing') progress = 50;
  else if (data.status === 'succeeded') progress = 100;

  return {
    taskId: data.id,
    status: statusMap[data.status] || 'waiting',
    progress,
    modelUrls,
    thumbnailUrl,
  };
}

module.exports = { createTask, createImageTask, getStatus };
