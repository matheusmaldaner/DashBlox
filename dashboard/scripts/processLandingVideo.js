#!/usr/bin/env node

const { spawnSync } = require('node:child_process');
const path = require('node:path');
const ffmpegPath = require('ffmpeg-static');

const rootDir = path.resolve(__dirname, '..');
const inputPath = path.join(rootDir, 'video-bright-redbackground.mp4');
const alphaOutPath = path.join(rootDir, 'public/assets/updated-video-alpha.webm');
const fallbackOutPath = path.join(rootDir, 'public/assets/updated-video-fallback.mp4');
const keyColor = '0xFF0000';
// Broader tolerance around #FF0000 to handle H.264 color drift and edge bleed.
const keySimilarity = '0.2';
// Hard-cut only deep reds to avoid clipping yellow/orange character details.
const redCutoff =
  "geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(gt(r(X,Y),150)*lt(g(X,Y),90)*lt(b(X,Y),90),0,alpha(X,Y))'";

function runFfmpeg(args) {
  const result = spawnSync(ffmpegPath, args, {
    cwd: rootDir,
    stdio: 'inherit',
  });

  if (result.status !== 0) {
    process.exit(result.status || 1);
  }
}

runFfmpeg([
  '-y',
  '-ss',
  '0.5',
  '-i',
  inputPath,
  '-vf',
  `colorkey=${keyColor}:${keySimilarity}:0.0,format=rgba,${redCutoff},format=rgba`,
  '-c:v',
  'libvpx-vp9',
  '-pix_fmt',
  'yuva420p',
  '-auto-alt-ref',
  '0',
  '-b:v',
  '0',
  '-crf',
  '30',
  '-an',
  '-metadata:s:v:0',
  'alpha_mode=1',
  alphaOutPath,
]);

runFfmpeg([
  '-y',
  '-ss',
  '0.5',
  '-i',
  inputPath,
  '-c:v',
  'libx264',
  '-preset',
  'medium',
  '-crf',
  '20',
  '-pix_fmt',
  'yuv420p',
  '-an',
  fallbackOutPath,
]);

console.log('Generated:');
console.log(alphaOutPath);
console.log(fallbackOutPath);
