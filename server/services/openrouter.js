// openrouter api client - llm prompt enhancement via gemini

const config = require('../config');

const BASE_URL = 'https://openrouter.ai/api/v1';

// enhance a 3d model prompt using gemini
async function enhancePrompt({ prompt, provider }) {
  const apiKey = config.openrouterApiKey;
  if (!apiKey) {
    throw Object.assign(new Error('OPENROUTER_API_KEY not configured'), { status: 503 });
  }

  if (!prompt || prompt.trim().length === 0) {
    throw Object.assign(new Error('prompt is required'), { status: 400 });
  }

  const systemMessage = `You are a 3D model generation prompt engineer. Given a simple description, enhance it into a detailed, optimized prompt for AI 3D model generation. Focus on:
- Physical details (shape, material, texture, color, size)
- Art style (realistic, stylized, low-poly, game-ready)
- Technical requirements (clean topology, suitable for games, ~30k triangles)
${provider ? `- Optimized for ${provider} 3D generation API` : ''}

Output ONLY the enhanced prompt text, no explanation or formatting.`;

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
        { role: 'user', content: prompt.trim() },
      ],
      temperature: 0.7,
      max_tokens: 300,
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
