// model routes - 3d generation, prompt enhancement, upload

const express = require('express');
const router = express.Router();
const { enhancePrompt } = require('../services/openrouter');
const meshy = require('../services/meshy');
const tripo = require('../services/tripo');
const rodin = require('../services/rodin');
const Asset3D = require('../models/Asset3D');

// provider dispatch map
const providers = { meshy, tripo, rodin };

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
    const { prompt, provider, enhanced_prompt, topology, target_polycount, tier, format, quality } = req.body;

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
      result = await meshy.createTask({ prompt: textPrompt, topology, targetPolycount: target_polycount });
    } else if (provider === 'tripo') {
      result = await tripo.createTask({ prompt: textPrompt });
    } else if (provider === 'rodin') {
      result = await rodin.createTask({ prompt: textPrompt, tier, format, quality });
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

// POST /api/models/upload-roblox - upload to roblox open cloud (phase 4)
router.post('/upload-roblox', (_req, res) => {
  res.json({ success: false, error: 'not implemented' });
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
