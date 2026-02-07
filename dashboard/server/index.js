// express entry point

const express = require('express');
const cors = require('cors');
const path = require('path');
const config = require('./config');
const connectDB = require('./db');
const { applySettings } = require('./settings');
const errorHandler = require('./middleware/errorHandler');

// route imports
const audioRoutes = require('./routes/audio');
const modelsRoutes = require('./routes/models');
const docsRoutes = require('./routes/docs');
const boardRoutes = require('./routes/board');
const settingsRoutes = require('./routes/settings');

const app = express();

// middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// static files
app.use(express.static(path.join(__dirname, '..', 'public')));

// api routes
app.use('/api/audio', audioRoutes);
app.use('/api/models', modelsRoutes);
app.use('/api/docs', docsRoutes);
app.use('/api/board', boardRoutes);
app.use('/api/settings', settingsRoutes);

// health check
app.get('/api/health', (_req, res) => {
  res.json({ success: true, data: { status: 'ok', timestamp: new Date().toISOString() } });
});

// error handler
app.use(errorHandler);

// start server
async function start() {
  applySettings();
  await connectDB();

  app.listen(config.port, '0.0.0.0', () => {
    console.log(`server running on http://localhost:${config.port}`);
  });
}

start();

module.exports = app;
