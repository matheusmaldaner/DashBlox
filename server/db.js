// mongodb connection using mongoose

const mongoose = require('mongoose');
const config = require('./config');

async function connectDB() {
  if (!config.mongoUri) {
    console.log('MONGODB_URI not set, skipping database connection');
    return null;
  }

  try {
    const conn = await mongoose.connect(config.mongoUri);
    console.log(`mongodb connected: ${conn.connection.host}`);
    return conn;
  } catch (err) {
    console.error(`mongodb connection error: ${err.message}`);
    process.exit(1);
  }
}

module.exports = connectDB;
