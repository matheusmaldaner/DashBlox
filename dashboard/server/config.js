// environment variables and constants

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

module.exports = {
  port: process.env.PORT || 3000,
  mongoUri: process.env.MONGODB_URI || '',
  openrouterApiKey: process.env.OPENROUTER_API_KEY || '',
  elevenlabsApiKey: process.env.ELEVENLABS_API_KEY || '',
  meshyApiKey: process.env.MESHY_API_KEY || '',
  tripoApiKey: process.env.TRIPO_API_KEY || '',
  rodinApiKey: process.env.RODIN_API_KEY || '',
  robloxApiKey: process.env.ROBLOX_API_KEY || '',
  solanaRpcUrl: process.env.SOLANA_RPC_URL || 'https://api.devnet.solana.com',
  solanaPrivateKey: process.env.SOLANA_PRIVATE_KEY || '',
  projectPaths: process.env.PROJECT_PATHS ? process.env.PROJECT_PATHS.split(',') : [],
};
