// openrouter api client - llm prompt enhancement via gemini

const config = require('../config');

const BASE_URL = 'https://openrouter.ai/api/v1';

// system prompts by type
const SYSTEM_PROMPTS = {
  model: (provider) => `You are a senior 3D model prompt engineer. Transform a rough user idea into a polished, production-ready prompt for AI 3D generation.

Requirements:
- Be thorough, specific, and coherent.
- Include physical form, materials, texture detail, scale, and visual style.
- Include model-readiness details useful for game/real-time use (clean topology, UV-ready surfaces, consistent proportions).
- Keep it practical and directly usable by text-to-3D providers.
${provider ? `- Optimize wording for ${provider} as the target provider.` : ''}
- Return one complete prompt in 2-4 well-written sentences.
- End on a complete sentence.

Output ONLY the final enhanced prompt text. No bullets, labels, markdown, or explanation.`,

  audio: () => `You are a senior sound design prompt engineer for AI audio generation (ElevenLabs SFX). Transform a rough user idea into a polished, production-ready sound prompt.

Requirements:
- Be thorough, specific, and coherent.
- Include tone/timbre, envelope (attack/sustain/decay), intensity, environment, and perspective.
- Keep it practical and directly usable by an SFX generator.
- Return one complete prompt in 2-3 well-written sentences.
- End on a complete sentence.

Output ONLY the final enhanced prompt text. No bullets, labels, markdown, or explanation.`,
};

// enhance a prompt using gemini
async function enhancePrompt({ prompt, provider, type }) {
  const apiKey = config.openrouterApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('OPENROUTER_API_KEY not configured'), { status: 503 });
  }

  if (!prompt || prompt.trim().length === 0) {
    throw Object.assign(new Error('prompt is required'), { status: 400 });
  }

  const promptType = type || 'model';
  const systemMessage = SYSTEM_PROMPTS[promptType]
    ? SYSTEM_PROMPTS[promptType](provider)
    : SYSTEM_PROMPTS.model(provider);

  const response = await fetch(`${BASE_URL}/chat/completions`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'google/gemini-2.5-pro',
      messages: [
        { role: 'system', content: systemMessage },
        { role: 'user', content: `Original prompt: ${prompt.trim()}\n\nRewrite this into a polished final prompt that is ready to paste and use.` },
      ],
      temperature: 0.7,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw Object.assign(
      new Error(`openrouter api error: ${response.status}`),
      { status: response.status, details: errorText }
    );
  }

  const data = await response.json();
  const enhanced = data.choices?.[0]?.message?.content?.trim();

  if (!enhanced) {
    throw Object.assign(new Error('no response from openrouter'), { status: 502 });
  }

  return { enhanced, model: data.model, usage: data.usage };
}

module.exports = { enhancePrompt };
