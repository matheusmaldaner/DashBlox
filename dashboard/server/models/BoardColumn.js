// mongodb schema for board columns

const mongoose = require('mongoose');

const boardColumnSchema = new mongoose.Schema({
  project_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Project' },
  title: { type: String, required: true },
  position: { type: Number, default: 0 },
  created_at: { type: Date, default: Date.now },
});

module.exports = mongoose.model('BoardColumn', boardColumnSchema);
