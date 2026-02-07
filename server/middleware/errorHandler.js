// centralized error handling middleware

function errorHandler(err, _req, res, _next) {
  console.error(err.stack);

  const status = err.status || 500;
  const message = err.message || 'internal server error';

  res.status(status).json({
    success: false,
    error: message,
  });
}

module.exports = errorHandler;
