// mongodb schema for projects

const mongoose = require('mongoose');

const projectSchema = new mongoose.Schema({
  name: { type: String, required: true },
  path: { type: String, required: true },
  roblox_place_id: { type: Number, default: null },
  created_at: { type: Date, default: Date.now },
  updated_at: { type: Date, default: Date.now },
});

projectSchema.pre('save', function () {
  this.updated_at = new Date();
});

module.exports = mongoose.model('Project', projectSchema);
