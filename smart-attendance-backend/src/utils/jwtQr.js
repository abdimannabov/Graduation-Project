let jwt;
try {
  jwt = require('jsonwebtoken');
} catch (e) {
  jwt = null;
}

const secret = process.env.QR_JWT_SECRET;
const ttl = parseInt(process.env.QR_TTL_SECONDS || '30', 10);

function signQrToken(payload = {}) {
  if (!secret) throw new Error('Missing QR_JWT_SECRET in environment');
  if (!jwt) throw new Error('jsonwebtoken module not installed; run npm install');
  // payload should include attendanceId and sessionId (numbers)
  return jwt.sign(payload, secret, { expiresIn: ttl });
}

function verifyQrToken(token) {
  if (!secret) {
    const e = new Error('Missing QR_JWT_SECRET in environment');
    e.code = 'QR_INVALID';
    throw e;
  }
  try {
    if (!jwt) {
      const e = new Error('jsonwebtoken module not installed; run npm install');
      e.code = 'QR_INVALID';
      throw e;
    }
    return jwt.verify(token, secret);
  } catch (err) {
    const e = new Error('Invalid or expired QR token');
    e.code = 'QR_INVALID';
    throw e;
  }
}

module.exports = { signQrToken, verifyQrToken };
