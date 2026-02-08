// mongodb schema for board cards

const mongoose = require('mongoose');

const boardCardSchema = new mongoose.Schema({
  column_id: { type: mongoose.Schema.Types.ObjectId, ref: 'BoardColumn', required: true },
  project_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Project' },
  title: { type: String, required: true },
  description: { type: String, default: '' },
  priority: {
    type: String,
    enum: ['low', 'medium', 'high', 'critical'],
    default: 'medium',
  },
  labels: [String],
  assignee: { type: String, default: null },
  due_date: { type: Date, default: null },
  linked_asset_id: { type: mongoose.Schema.Types.ObjectId, default: null },
  position: { type: Number, default: 0 },
  created_at: { type: Date, default: Date.now },
  updated_at: { type: Date, default: Date.now },
});

boardCardSchema.pre('save', function () {
  this.updated_at = new Date();
});

module.exports = mongoose.model('BoardCard', boardCardSchema);
