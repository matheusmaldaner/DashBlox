// mongodb schema for model conversion history

const mongoose = require('mongoose');

const conversionHistorySchema = new mongoose.Schema({
  name: { type: String, required: true },
  from_format: { type: String, required: true },
  to_format: { type: String, required: true },
  file_size: { type: Number, default: 0 },
  created_at: { type: Date, default: Date.now },
});

module.exports = mongoose.model('ConversionHistory', conversionHistorySchema);
