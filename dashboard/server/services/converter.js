// converter service - glb to fbx/obj conversion using assimp cli

const { execFile } = require('child_process');
const { promisify } = require('util');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const execFileAsync = promisify(execFile);

// providers that only output glb
const GLB_ONLY_PROVIDERS = ['meshy', 'tripo', 'replicate'];

const VALID_OUTPUT_FORMATS = ['fbx', 'obj'];

const CONVERSION_TIMEOUT = 30000; // 30 seconds

let assimpAvailable = null;

// check if assimp cli is installed
async function checkAssimpInstalled() {
  if (assimpAvailable !== null) return assimpAvailable;
  try {
    await execFileAsync('assimp', ['version'], { timeout: 5000 });
    assimpAvailable = true;
  } catch {
    console.warn('assimp cli not found - model format conversion unavailable. install with: sudo apt-get install assimp-utils');
    assimpAvailable = false;
  }
  return assimpAvailable;
}

// check if conversion is needed for a given provider and format
function isConversionNeeded(provider, requestedFormat) {
  if (!requestedFormat || requestedFormat === 'glb') return false;
  return GLB_ONLY_PROVIDERS.includes(provider);
}

// convert a model buffer from one format to another using assimp
async function convertBuffer(inputBuffer, fromFormat, toFormat) {
  if (!VALID_OUTPUT_FORMATS.includes(toFormat)) {
    throw Object.assign(
      new Error(`unsupported output format: ${toFormat}. supported: ${VALID_OUTPUT_FORMATS.join(', ')}`),
      { status: 400 }
    );
  }

  const installed = await checkAssimpInstalled();
  if (!installed) {
    throw Object.assign(
      new Error('assimp is not installed - cannot convert model formats. install with: sudo apt-get install assimp-utils'),
      { status: 503 }
    );
  }

  const tmpId = crypto.randomUUID();
  const tmpDir = path.join(os.tmpdir(), `model-convert-${tmpId}`);
  const inputPath = path.join(tmpDir, `input.${fromFormat}`);
  const outputPath = path.join(tmpDir, `output.${toFormat}`);

  try {
    await fs.promises.mkdir(tmpDir, { recursive: true });
    await fs.promises.writeFile(inputPath, inputBuffer);

    await execFileAsync('assimp', ['export', inputPath, outputPath], {
      timeout: CONVERSION_TIMEOUT,
    });

    const outputBuffer = await fs.promises.readFile(outputPath);
    return outputBuffer;
  } catch (err) {
    // re-throw if already formatted
    if (err.status) throw err;

    const message = err.killed
      ? 'model conversion timed out'
      : `model conversion failed: ${err.stderr || err.message}`;

    throw Object.assign(new Error(message), { status: 500 });
  } finally {
    // clean up temp files
    await fs.promises.rm(tmpDir, { recursive: true, force: true }).catch(() => {});
  }
}

// run initial check on load
checkAssimpInstalled();

module.exports = { convertBuffer, isConversionNeeded, checkAssimpInstalled };
