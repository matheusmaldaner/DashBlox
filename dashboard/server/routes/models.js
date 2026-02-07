// model routes - 3d generation, prompt enhancement, upload

const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const router = express.Router();
const config = require('../config');
const { enhancePrompt } = require('../services/openrouter');
const meshy = require('../services/meshy');
const tripo = require('../services/tripo');
const rodin = require('../services/rodin');
const Asset3D = require('../models/Asset3D');

// provider dispatch map
const providers = { meshy, tripo, rodin };

// multer setup for image uploads
const uploadsDir = path.join(__dirname, '..', '..', 'uploads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 }, // 10mb
  fileFilter: (_req, file, cb) => {
    const allowed = ['image/jpeg', 'image/png', 'image/webp'];
    cb(null, allowed.includes(file.mimetype));
  },
});

// POST /api/models/enhance-prompt - enhance user prompt via openrouter/gemini
router.post('/enhance-prompt', async (req, res, next) => {
  try {
    const { prompt, provider } = req.body;
    const result = await enhancePrompt({ prompt, provider });
    res.json({ success: true, data: result });
  } catch (err) {
    next(err);
  }
});

// POST /api/models/generate - create 3d generation task
router.post('/generate', async (req, res, next) => {
  try {
    const { prompt, provider, enhanced_prompt, negative_prompt, topology, target_polycount, tier, format, quality } = req.body;

    if (!prompt) {
      return res.status(400).json({ success: false, error: 'prompt is required' });
    }

    const selectedProvider = providers[provider];
    if (!selectedProvider) {
      return res.status(400).json({ success: false, error: `unknown provider: ${provider}. use meshy, tripo, or rodin` });
    }

    const textPrompt = enhanced_prompt || prompt;

    // dispatch to the selected provider
    let result;
    if (provider === 'meshy') {
      result = await meshy.createTask({ prompt: textPrompt, negativePrompt: negative_prompt, topology, targetPolycount: target_polycount });
    } else if (provider === 'tripo') {
      result = await tripo.createTask({ prompt: textPrompt });
    } else if (provider === 'rodin') {
      result = await rodin.createTask({ prompt: textPrompt, negativePrompt: negative_prompt, tier, format, quality });
    }

    // save to mongodb
    const asset = await Asset3D.create({
      name: prompt.slice(0, 60),
      prompt,
      enhanced_prompt: enhanced_prompt || null,
      provider,
      provider_task_id: result.taskId,
      status: 'processing',
      tags: [`provider:${provider}`],
    });

    res.json({
      success: true,
      data: {
        ...result,
        assetId: asset._id,
        // include subscription_key for rodin polling
        subscriptionKey: result.subscriptionKey || null,
      },
    });
  } catch (err) {
    next(err);
  }
});

// GET /api/models/status/:taskId - poll generation status
router.get('/status/:taskId', async (req, res, next) => {
  try {
    const { taskId } = req.params;
    const { provider, subscription_key } = req.query;

    if (!provider || !providers[provider]) {
      return res.status(400).json({ success: false, error: 'provider query param is required (meshy, tripo, or rodin)' });
    }

    let status;
    if (provider === 'rodin') {
      // rodin uses subscription_key for polling
      status = await rodin.getStatus(subscription_key || taskId);
    } else {
      status = await providers[provider].getStatus(taskId);
    }

    // if ready and rodin, fetch download urls
    if (provider === 'rodin' && status.status === 'ready') {
      const urls = await rodin.downloadResults(taskId);
      status.modelUrls = urls;
      status.thumbnailUrl = urls.thumbnail || null;
    }

    // update mongodb asset status if changed
    if (status.status === 'ready' || status.status === 'error') {
      await Asset3D.findOneAndUpdate(
        { provider_task_id: taskId },
        {
          status: status.status === 'ready' ? 'completed' : 'failed',
          ...(status.modelUrls?.glb ? { file_path: status.modelUrls.glb } : {}),
          ...(status.thumbnailUrl ? { thumbnail_path: status.thumbnailUrl } : {}),
        }
      );
    }

    res.json({ success: true, data: status });
  } catch (err) {
    next(err);
  }
});

// GET /api/models/download/:taskId - proxy download of generated model
router.get('/download/:taskId', async (req, res, next) => {
  try {
    const { taskId } = req.params;
    const { provider, subscription_key, format } = req.query;

    if (!provider || !providers[provider]) {
      return res.status(400).json({ success: false, error: 'provider query param is required' });
    }

    let modelUrl;

    if (provider === 'rodin') {
      const urls = await rodin.downloadResults(taskId);
      modelUrl = urls[format || 'glb'] || urls.glb;
    } else {
      const status = await providers[provider].getStatus(subscription_key || taskId);
      if (!status.modelUrls) {
        return res.status(404).json({ success: false, error: 'model not ready yet' });
      }
      modelUrl = status.modelUrls[format || 'glb'] || status.modelUrls.glb || Object.values(status.modelUrls)[0];
    }

    if (!modelUrl) {
      return res.status(404).json({ success: false, error: 'model file not found' });
    }

    // proxy the file download
    const fileRes = await fetch(modelUrl);
    if (!fileRes.ok) {
      return res.status(502).json({ success: false, error: 'failed to download from provider' });
    }

    const contentType = fileRes.headers.get('content-type') || 'model/gltf-binary';
    res.setHeader('Content-Type', contentType);
    res.setHeader('Content-Disposition', `attachment; filename="model.${format || 'glb'}"`);

    const arrayBuffer = await fileRes.arrayBuffer();
    res.send(Buffer.from(arrayBuffer));
  } catch (err) {
    next(err);
  }
});

// POST /api/models/generate-image - image-to-3d generation
router.post('/generate-image', upload.single('image'), async (req, res, next) => {
  try {
    const { provider, negative_prompt, tier, format, quality } = req.body;
    const file = req.file;

    if (!file) {
      return res.status(400).json({ success: false, error: 'image file is required' });
    }

    const selectedProvider = providers[provider];
    if (!selectedProvider) {
      return res.status(400).json({ success: false, error: `unknown provider: ${provider}` });
    }

    let result;
    if (provider === 'meshy') {
      // meshy needs a url, so we base64 encode and use data url
      const base64 = file.buffer.toString('base64');
      const dataUrl = `data:${file.mimetype};base64,${base64}`;
      result = await meshy.createImageTask({ imageUrl: dataUrl });
    } else if (provider === 'tripo') {
      const imageToken = await tripo.uploadImage(file.buffer, file.originalname);
      result = await tripo.createImageTask({ imageToken });
    } else if (provider === 'rodin') {
      result = await rodin.createImageTask({
        imageBuffer: file.buffer,
        filename: file.originalname,
        tier,
        format,
        quality,
      });
    }

    // save to mongodb
    const promptText = `image-to-3d: ${file.originalname}`;
    const asset = await Asset3D.create({
      name: file.originalname.slice(0, 60),
      prompt: promptText,
      enhanced_prompt: negative_prompt || null,
      provider,
      provider_task_id: result.taskId,
      status: 'processing',
      tags: [`provider:${provider}`, 'image-to-3d'],
    });

    res.json({
      success: true,
      data: {
        ...result,
        assetId: asset._id,
        subscriptionKey: result.subscriptionKey || null,
      },
    });
  } catch (err) {
    next(err);
  }
});

// POST /api/models/upload-roblox - upload to roblox open cloud
router.post('/upload-roblox', async (req, res, next) => {
  try {
    const { model_url, name, description } = req.body;

    if (!model_url) {
      return res.status(400).json({ success: false, error: 'model_url is required' });
    }

    const apiKey = config.robloxApiKey;
    if (!apiKey) {
      return res.status(503).json({ success: false, error: 'ROBLOX_API_KEY not configured' });
    }

    // download the model file
    const fileRes = await fetch(model_url);
    if (!fileRes.ok) {
      return res.status(502).json({ success: false, error: 'failed to download model file' });
    }
    const modelBuffer = Buffer.from(await fileRes.arrayBuffer());

    // determine content type
    const isGlb = model_url.includes('.glb') || model_url.includes('gltf');
    const contentType = isGlb ? 'model/gltf-binary' : 'model/fbx';
    const ext = isGlb ? 'glb' : 'fbx';

    // build multipart request for roblox open cloud
    const boundary = `----RobloxBoundary${Date.now()}`;
    const crlf = '\r\n';

    const metadata = JSON.stringify({
      assetType: 'Model',
      displayName: name || 'Generated Model',
      description: description || 'AI-generated 3D model from RobloxDashboard',
      creationContext: { creator: { userId: 'self' } },
    });

    const metaPart = Buffer.from(
      `--${boundary}${crlf}Content-Disposition: form-data; name="request"${crlf}Content-Type: application/json${crlf}${crlf}${metadata}${crlf}`
    );
    const fileHeader = Buffer.from(
      `--${boundary}${crlf}Content-Disposition: form-data; name="fileContent"; filename="model.${ext}"${crlf}Content-Type: ${contentType}${crlf}${crlf}`
    );
    const endBoundary = Buffer.from(`${crlf}--${boundary}--${crlf}`);
    const body = Buffer.concat([metaPart, fileHeader, modelBuffer, endBoundary]);

    const robloxRes = await fetch('https://apis.roblox.com/assets/v1/assets', {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'Content-Type': `multipart/form-data; boundary=${boundary}`,
      },
      body,
    });

    if (!robloxRes.ok) {
      const errText = await robloxRes.text();
      return res.status(robloxRes.status).json({
        success: false,
        error: `roblox upload failed: ${robloxRes.status}`,
        details: errText,
      });
    }

    const robloxData = await robloxRes.json();

    res.json({ success: true, data: robloxData });
  } catch (err) {
    next(err);
  }
});

// GET /api/models/history - list previous generations from mongodb
router.get('/history', async (_req, res, next) => {
  try {
    const assets = await Asset3D.find()
      .sort({ created_at: -1 })
      .limit(50)
      .lean();

    res.json({ success: true, data: assets });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
