class ApiError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

function handleError(err, res) {
  if (err instanceof ApiError) {
    return res.status(err.status).json({ ok: false, code: err.code, message: err.message });
  }

  console.error(err);
  return res.status(500).json({ ok: false, code: 'INTERNAL_ERROR', message: 'Internal server error' });
}

module.exports = { ApiError, handleError };
