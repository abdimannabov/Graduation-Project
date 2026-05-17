const { ApiError } = require('../utils/errors');

function asPositiveInt(value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) return null;
  return n;
}

function validateGenerateQr(req, res, next) {
  const body = req.body || {};
  const attendanceId = asPositiveInt(body.attendanceId);
  const sessionId = asPositiveInt(body.sessionId);

  if (!attendanceId || !sessionId) {
    return next(new ApiError(400, 'INVALID_INPUT', 'attendanceId and sessionId must be positive integers'));
  }

  if (body.wifiConstraint !== undefined && body.wifiConstraint !== null) {
    if (typeof body.wifiConstraint !== 'object' || Array.isArray(body.wifiConstraint)) {
      return next(new ApiError(400, 'INVALID_WIFI_CONSTRAINT', 'wifiConstraint must be an object'));
    }
  }

  req.validated = req.validated || {};
  req.validated.attendanceId = attendanceId;
  req.validated.sessionId = sessionId;
  req.validated.wifiConstraint = body.wifiConstraint || null;
  return next();
}

function validateMarkFromQr(req, res, next) {
  const body = req.body || {};
  const qrValue = body.qrToken || body.qrContent || body.scannedValue;

  if (!qrValue || typeof qrValue !== 'string') {
    return next(new ApiError(400, 'MISSING_QR', 'A scanned QR value is required'));
  }

  const hasWifiObject = body.wifiData !== undefined && body.wifiData !== null;
  if (hasWifiObject && (typeof body.wifiData !== 'object' || Array.isArray(body.wifiData))) {
    return next(new ApiError(400, 'INVALID_WIFI_DATA', 'wifiData must be an object'));
  }

  req.validated = req.validated || {};
  req.validated.qrToken = qrValue.trim();
  req.validated.wifiData = hasWifiObject
    ? body.wifiData
    : { bssid: body.bssid || body.mac || body.macAddress };

  return next();
}

module.exports = {
  validateGenerateQr,
  validateMarkFromQr,
};
