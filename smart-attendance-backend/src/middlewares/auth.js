const { ApiError } = require('../utils/errors');
const logger = require('../utils/logger');
const { getFirebaseAuth } = require('../config/firebase.config');

function getAuthMode() {
  return String(process.env.AUTH_MODE || 'dev')
    .trim()
    .toLowerCase();
}

function isProduction() {
  return String(process.env.NODE_ENV || '')
    .trim()
    .toLowerCase() === 'production';
}

function extractBearerToken(req) {
  const rawHeader = req.headers.authorization || req.headers.Authorization;
  if (!rawHeader || typeof rawHeader !== 'string') return null;

  const match = rawHeader.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : null;
}

async function auth(req, res, next) {
  const mode = getAuthMode();

  if (isProduction() && mode !== 'firebase') {
    logger.error('Refusing insecure auth mode in production', { mode });
    return next(
      new ApiError(
        500,
        'INSECURE_AUTH_MODE',
        'Production requires AUTH_MODE=firebase with Firebase ID token verification.',
      ),
    );
  }

  if (mode === 'none') {
    return next();
  }

  if (mode === 'dev') {
    const email = req.headers['x-user-email'] || (req.body && req.body.email);
    if (!email) {
      return next(
        new ApiError(
          401,
          'NO_AUTH',
          'Missing x-user-email header or body.email (dev mode).',
        ),
      );
    }

    req.user = { email: String(email).trim().toLowerCase() };
    return next();
  }

  if (mode === 'firebase') {
    const idToken = extractBearerToken(req);
    if (!idToken) {
      return next(
        new ApiError(
          401,
          'NO_AUTH',
          'Missing Authorization bearer token.',
        ),
      );
    }

    try {
      const decodedToken = await getFirebaseAuth().verifyIdToken(idToken);
      const email = String(decodedToken.email || '')
        .trim()
        .toLowerCase();

      if (!email) {
        return next(
          new ApiError(
            401,
            'NO_AUTH_EMAIL',
            'Authenticated Firebase user does not have an email address.',
          ),
        );
      }

      req.user = {
        uid: decodedToken.uid,
        email,
        token: decodedToken,
      };
      return next();
    } catch (error) {
      logger.warn('Firebase token verification failed', {
        message: error && error.message,
      });
      return next(
        new ApiError(
          401,
          'INVALID_AUTH_TOKEN',
          'Invalid or expired authentication token.',
        ),
      );
    }
  }

  return next(
    new ApiError(500, 'AUTH_MODE_UNSUPPORTED', `Unsupported AUTH_MODE: ${mode}`),
  );
}

module.exports = auth;
