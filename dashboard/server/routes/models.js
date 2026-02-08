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
const replicate = require('../services/replicate');
const Asset3D = require('../models/Asset3D');
const converter = require('../services/converter');

// provider dispatch map
const providers = { meshy, tripo, rodin, replicate };

// multer setup for image uploads
const uploadsDir = path.join(__dirname, '..', '..', 'uploads');
const thumbnailsDir = path.join(uploadsDir, 'thumbnails');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}
if (!fs.existsSync(thumbnailsDir)) {
  fs.mkdirSync(thumbnailsDir, { recursive: true });
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
      return res.status(400).json({ success: false, error: `unknown provider: ${provider}. use meshy, tripo, rodin, or replicate` });
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
    } else if (provider === 'replicate') {
      result = await replicate.createTask({ prompt: textPrompt });
    }

    // save to mongodb
    const asset = await Asset3D.create({
      name: prompt.slice(0, 60),
      prompt,
      enhanced_prompt: enhanced_prompt || null,
      provider,
      provider_task_id: result.taskId,
      status: 'generating',
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
      // check if asset already has a local thumbnail (from image upload)
      const existingAsset = await Asset3D.findOne({ provider_task_id: taskId }).lean();
      const hasLocalThumb = existingAsset?.thumbnail_path?.startsWith('/uploads/');

      const updateFields = {
        status: status.status === 'ready' ? 'ready' : 'error',
        ...(status.modelUrls?.glb ? { file_path: status.modelUrls.glb } : {}),
      };

      // only set thumbnail if there's no local one already saved
      if (!hasLocalThumb && status.thumbnailUrl) {
        // download external thumbnail and save locally
        try {
          const thumbRes = await fetch(status.thumbnailUrl);
          if (thumbRes.ok) {
            const contentType = thumbRes.headers.get('content-type') || '';
            const thumbExt = contentType.includes('mp4') ? '.mp4' : contentType.includes('webm') ? '.webm' : '.jpg';
            const thumbFilename = `${taskId}${thumbExt}`;
            const thumbPath = path.join(thumbnailsDir, thumbFilename);
            const buffer = Buffer.from(await thumbRes.arrayBuffer());
            fs.writeFileSync(thumbPath, buffer);
            updateFields.thumbnail_path = `/uploads/thumbnails/${thumbFilename}`;
          }
        } catch (thumbErr) {
          console.warn('failed to download thumbnail:', thumbErr.message);
        }
      }

      await Asset3D.findOneAndUpdate({ provider_task_id: taskId }, updateFields);
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

    const arrayBuffer = await fileRes.arrayBuffer();
    let outputBuffer = Buffer.from(arrayBuffer);

    // convert if provider doesn't have the requested format natively
    const requestedFormat = format || 'glb';
    if (converter.isConversionNeeded(provider, requestedFormat)) {
      outputBuffer = await converter.convertBuffer(outputBuffer, 'glb', requestedFormat);
    }

    const contentTypes = { glb: 'model/gltf-binary', fbx: 'application/octet-stream', obj: 'text/plain' };
    res.setHeader('Content-Type', contentTypes[requestedFormat] || 'application/octet-stream');
    res.setHeader('Content-Disposition', `attachment; filename="model.${requestedFormat}"`);
    res.send(outputBuffer);
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
    } else if (provider === 'replicate') {
      // replicate/trellis needs a url - use data url like meshy
      const base64 = file.buffer.toString('base64');
      const dataUrl = `data:${file.mimetype};base64,${base64}`;
      result = await replicate.createImageTask({ imageUrl: dataUrl });
    }

    // save source image as local thumbnail
    const ext = path.extname(file.originalname).toLowerCase() || '.jpg';
    const thumbFilename = `${result.taskId}${ext}`;
    const thumbPath = path.join(thumbnailsDir, thumbFilename);
    fs.writeFileSync(thumbPath, file.buffer);
    const thumbnailUrl = `/uploads/thumbnails/${thumbFilename}`;

    // save to mongodb
    const promptText = `image-to-3d: ${file.originalname}`;
    const asset = await Asset3D.create({
      name: file.originalname.slice(0, 60),
      prompt: promptText,
      enhanced_prompt: negative_prompt || null,
      provider,
      provider_task_id: result.taskId,
      status: 'generating',
      thumbnail_path: thumbnailUrl,
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

    // determine source format and convert to fbx if needed (roblox only accepts fbx/obj)
    const urlLower = model_url.toLowerCase();
    let uploadFormat = 'glb';
    if (urlLower.includes('.fbx')) uploadFormat = 'fbx';
    else if (urlLower.includes('.obj')) uploadFormat = 'obj';

    let uploadBuffer = modelBuffer;
    if (uploadFormat === 'glb') {
      uploadBuffer = await converter.convertBuffer(modelBuffer, 'glb', 'fbx');
      uploadFormat = 'fbx';
    }

    const uploadContentType = uploadFormat === 'obj' ? 'model/obj' : 'model/fbx';

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
      `--${boundary}${crlf}Content-Disposition: form-data; name="fileContent"; filename="model.${uploadFormat}"${crlf}Content-Type: ${uploadContentType}${crlf}${crlf}`
    );
    const endBoundary = Buffer.from(`${crlf}--${boundary}--${crlf}`);
    const body = Buffer.concat([metaPart, fileHeader, uploadBuffer, endBoundary]);

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

// POST /api/models/convert - upload a model file and convert to a different format
const modelUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 50 * 1024 * 1024 }, // 50mb for 3d models
  fileFilter: (_req, file, cb) => {
    const allowed = ['.glb', '.gltf', '.fbx', '.obj'];
    const ext = path.extname(file.originalname).toLowerCase();
    cb(null, allowed.includes(ext));
  },
});

router.post('/convert', modelUpload.single('model'), async (req, res, next) => {
  try {
    const file = req.file;
    const { target_format } = req.body;

    if (!file) {
      return res.status(400).json({ success: false, error: 'model file is required (glb, gltf, fbx, obj)' });
    }

    if (!target_format || !['fbx', 'obj'].includes(target_format)) {
      return res.status(400).json({ success: false, error: 'target_format must be fbx or obj' });
    }

    const ext = path.extname(file.originalname).toLowerCase().replace('.', '');
    if (ext === target_format) {
      return res.status(400).json({ success: false, error: `file is already in ${target_format} format` });
    }

    const outputBuffer = await converter.convertBuffer(file.buffer, ext, target_format);

    const baseName = path.basename(file.originalname, path.extname(file.originalname));
    const contentTypes = { fbx: 'application/octet-stream', obj: 'text/plain' };
    res.setHeader('Content-Type', contentTypes[target_format] || 'application/octet-stream');
    res.setHeader('Content-Disposition', `attachment; filename="${baseName}.${target_format}"`);
    res.send(outputBuffer);
  } catch (err) {
    next(err);
  }
});

// POST /api/models/convert-upload-roblox - convert file and upload directly to roblox
router.post('/convert-upload-roblox', modelUpload.single('model'), async (req, res, next) => {
  try {
    const file = req.file;
    const { name } = req.body;

    if (!file) {
      return res.status(400).json({ success: false, error: 'model file is required' });
    }

    const apiKey = config.robloxApiKey;
    if (!apiKey) {
      return res.status(503).json({ success: false, error: 'ROBLOX_API_KEY not configured' });
    }

    // convert to fbx if not already fbx/obj
    const ext = path.extname(file.originalname).toLowerCase().replace('.', '');
    let uploadBuffer = file.buffer;
    let uploadFormat = ext;
    if (!['fbx', 'obj'].includes(ext)) {
      uploadBuffer = await converter.convertBuffer(file.buffer, ext, 'fbx');
      uploadFormat = 'fbx';
    }

    const uploadContentType = uploadFormat === 'obj' ? 'model/obj' : 'model/fbx';
    const boundary = `----RobloxBoundary${Date.now()}`;
    const crlf = '\r\n';
    const metadata = JSON.stringify({
      assetType: 'Model',
      displayName: name || path.basename(file.originalname, path.extname(file.originalname)),
      description: 'Converted and uploaded via RobloxDashboard',
      creationContext: { creator: { userId: 'self' } },
    });

    const metaPart = Buffer.from(
      `--${boundary}${crlf}Content-Disposition: form-data; name="request"${crlf}Content-Type: application/json${crlf}${crlf}${metadata}${crlf}`
    );
    const fileHeader = Buffer.from(
      `--${boundary}${crlf}Content-Disposition: form-data; name="fileContent"; filename="model.${uploadFormat}"${crlf}Content-Type: ${uploadContentType}${crlf}${crlf}`
    );
    const endBoundary = Buffer.from(`${crlf}--${boundary}--${crlf}`);
    const body = Buffer.concat([metaPart, fileHeader, uploadBuffer, endBoundary]);

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

// POST /api/models/fix-thumbnails - clear expired external thumbnail urls
router.post('/fix-thumbnails', async (_req, res, next) => {
  try {
    const result = await Asset3D.updateMany(
      { thumbnail_path: { $regex: '^https?://' } },
      { $set: { thumbnail_path: '' } }
    );
    res.json({ success: true, data: { modified: result.modifiedCount } });
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
