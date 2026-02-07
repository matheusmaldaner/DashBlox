// rodin/hyper3d api client - text-to-3d generation

const config = require('../config');

const BASE_URL = 'https://api.hyper3d.com/api/v2';

function getAuth() {
  const apiKey = config.rodinApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('RODIN_API_KEY not configured'), { status: 503 });
  }
  return `Bearer ${apiKey}`;
}

// create a text-to-3d task
async function createTask({ prompt, negativePrompt, tier, format, quality }) {
  if (!prompt || prompt.trim().length === 0) {
    throw Object.assign(new Error('prompt is required'), { status: 400 });
  }

  // rodin uses multipart form data
  const boundary = `----RodinBoundary${Date.now()}`;
  const parts = [];

  parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="prompt"\r\n\r\n${prompt.trim()}`);
  if (negativePrompt) {
    parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="negative_prompt"\r\n\r\n${negativePrompt.trim()}`);
  }
  parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="tier"\r\n\r\n${tier || 'Regular'}`);
  parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="geometry_file_format"\r\n\r\n${format || 'glb'}`);
  parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="material"\r\n\r\nPBR`);
  parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="quality"\r\n\r\n${quality || 'medium'}`);
  parts.push(`--${boundary}--\r\n`);

  const body = parts.join('\r\n');

  const response = await fetch(`${BASE_URL}/rodin`, {
    method: 'POST',
    headers: {
      Authorization: getAuth(),
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
    },
    body,
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`rodin api error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  const data = await response.json();

  if (data.error) {
    throw Object.assign(new Error(`rodin error: ${data.error}`), { status: 400 });
  }

  return {
    taskId: data.uuid,
    subscriptionKey: data.jobs?.subscription_key,
    provider: 'rodin',
  };
}

// check task status
async function getStatus(subscriptionKey) {
  const response = await fetch(`${BASE_URL}/status`, {
    method: 'POST',
    headers: {
      Authorization: getAuth(),
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ subscription_key: subscriptionKey }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`rodin status error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  const data = await response.json();
  const job = data.jobs?.[0];

  if (!job) {
    return { taskId: subscriptionKey, status: 'waiting', progress: 0, modelUrls: null, thumbnailUrl: null };
  }

  // normalize status
  const statusMap = {
    Waiting: 'waiting',
    Generating: 'generating',
    Done: 'ready',
    Failed: 'error',
  };

  return {
    taskId: subscriptionKey,
    status: statusMap[job.status] || 'waiting',
    progress: job.status === 'Done' ? 100 : job.status === 'Generating' ? 50 : 0,
    modelUrls: null, // urls come from download endpoint
    thumbnailUrl: null,
  };
}

// download generated model files
async function downloadResults(taskUuid) {
  const response = await fetch(`${BASE_URL}/download`, {
    method: 'POST',
    headers: {
      Authorization: getAuth(),
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ task_uuid: taskUuid }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`rodin download error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  const data = await response.json();

  if (data.error) {
    throw Object.assign(new Error(`rodin download error: ${data.error}`), { status: 400 });
  }

  // extract model urls from the list
  const urls = {};
  for (const item of data.list || []) {
    if (item.name.endsWith('.glb')) urls.glb = item.url;
    else if (item.name.endsWith('.fbx')) urls.fbx = item.url;
    else if (item.name.endsWith('.obj')) urls.obj = item.url;
    else if (item.name.endsWith('.webp') || item.name.endsWith('.png')) urls.thumbnail = item.url;
  }

  return urls;
}

// create an image-to-3d task
async function createImageTask({ imageBuffer, filename, tier, format, quality }) {
  if (!imageBuffer) {
    throw Object.assign(new Error('image is required'), { status: 400 });
  }

  const boundary = `----RodinBoundary${Date.now()}`;
  const crlf = '\r\n';
  const contentType = filename?.endsWith('.png') ? 'image/png' : 'image/jpeg';

  // image file part
  const fileHeader = `--${boundary}${crlf}Content-Disposition: form-data; name="images"; filename="${filename || 'image.jpg'}"${crlf}Content-Type: ${contentType}${crlf}${crlf}`;
  const fileFooter = crlf;

  const fileHeaderBuf = Buffer.from(fileHeader);
  const fileFooterBuf = Buffer.from(fileFooter);
  const filePart = Buffer.concat([fileHeaderBuf, imageBuffer, fileFooterBuf]);

  const paramParts = [];
  const addParamBuf = (name, value) => {
    paramParts.push(Buffer.from(`--${boundary}${crlf}Content-Disposition: form-data; name="${name}"${crlf}${crlf}${value}${crlf}`));
  };

  addParamBuf('tier', tier || 'Regular');
  addParamBuf('geometry_file_format', format || 'glb');
  addParamBuf('material', 'PBR');
  addParamBuf('quality', quality || 'medium');

  const endBoundary = Buffer.from(`--${boundary}--${crlf}`);
  const body = Buffer.concat([filePart, ...paramParts, endBoundary]);

  const response = await fetch(`${BASE_URL}/rodin`, {
    method: 'POST',
    headers: {
      Authorization: getAuth(),
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
    },
    body,
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`rodin image-to-3d error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  const data = await response.json();

  if (data.error) {
    throw Object.assign(new Error(`rodin error: ${data.error}`), { status: 400 });
  }

  return {
    taskId: data.uuid,
    subscriptionKey: data.jobs?.subscription_key,
    provider: 'rodin',
  };
}

module.exports = { createTask, createImageTask, getStatus, downloadResults };
