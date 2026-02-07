// docs routes - read/write markdown files from project directories

const express = require('express');
const router = express.Router();
const fs = require('fs').promises;
const path = require('path');
const config = require('../config');

const ALLOWED_FILES = ['CLAUDE.md', 'PLAN.md', 'PROGRESS.md'];

// get resolved project paths, fallback to current project root
function getProjectPaths() {
  const paths = config.projectPaths.filter(Boolean);
  if (paths.length > 0) return paths;
  // default to the dashboard project itself
  return [path.join(__dirname, '..', '..')];
}

// validate project index and file name, return resolved file path
function resolveFilePath(projectIndex, fileName) {
  const projects = getProjectPaths();
  const idx = parseInt(projectIndex, 10);

  if (isNaN(idx) || idx < 0 || idx >= projects.length) {
    throw Object.assign(new Error('invalid project index'), { status: 400 });
  }

  if (!ALLOWED_FILES.includes(fileName)) {
    throw Object.assign(
      new Error('file not allowed, must be one of: ' + ALLOWED_FILES.join(', ')),
      { status: 400 }
    );
  }

  const projectDir = path.resolve(projects[idx]);
  const filePath = path.resolve(path.join(projectDir, fileName));

  // prevent directory traversal
  if (!filePath.startsWith(projectDir)) {
    throw Object.assign(new Error('invalid file path'), { status: 400 });
  }

  return { filePath, projectDir };
}

// GET /api/docs/projects - list available projects
router.get('/projects', async (_req, res, next) => {
  try {
    const projectPaths = getProjectPaths();
    const projects = [];

    for (let i = 0; i < projectPaths.length; i++) {
      const dir = path.resolve(projectPaths[i]);
      const name = path.basename(dir);

      // check which allowed files exist in this directory
      const files = [];
      for (const f of ALLOWED_FILES) {
        try {
          await fs.access(path.join(dir, f));
          files.push(f);
        } catch {
          // file doesn't exist, skip
        }
      }

      projects.push({ index: i, name, path: dir, files });
    }

    res.json({ success: true, data: projects });
  } catch (err) {
    next(err);
  }
});

// GET /api/docs/read - read a markdown file
router.get('/read', async (req, res, next) => {
  try {
    const { project, file } = req.query;

    if (project === undefined || !file) {
      throw Object.assign(new Error('project and file query parameters required'), { status: 400 });
    }

    const { filePath } = resolveFilePath(project, file);
    const content = await fs.readFile(filePath, 'utf-8');

    res.json({ success: true, data: { file, content } });
  } catch (err) {
    if (err.code === 'ENOENT') {
      err.status = 404;
      err.message = 'file not found';
    }
    next(err);
  }
});

// PUT /api/docs/write - write/update a markdown file
router.put('/write', async (req, res, next) => {
  try {
    const { project, file, content } = req.body;

    if (project === undefined || !file || content === undefined) {
      throw Object.assign(new Error('project, file, and content are required'), { status: 400 });
    }

    const { filePath } = resolveFilePath(project, file);
    await fs.writeFile(filePath, content, 'utf-8');

    res.json({ success: true, data: { file, saved: true } });
  } catch (err) {
    next(err);
  }
});

module.exports = router;
