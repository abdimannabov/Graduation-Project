const admin = require('firebase-admin');

let initializedApp = null;

function normalizePrivateKey(value) {
  return String(value || '').replace(/\\n/g, '\n').trim();
}

function loadServiceAccountFromEnv() {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    return JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
  }

  if (
    process.env.FIREBASE_PROJECT_ID &&
    process.env.FIREBASE_CLIENT_EMAIL &&
    process.env.FIREBASE_PRIVATE_KEY
  ) {
    return {
      project_id: process.env.FIREBASE_PROJECT_ID,
      client_email: process.env.FIREBASE_CLIENT_EMAIL,
      private_key: normalizePrivateKey(process.env.FIREBASE_PRIVATE_KEY),
    };
  }

  return null;
}

function buildFirebaseOptions() {
  const serviceAccount = loadServiceAccountFromEnv();
  if (serviceAccount) {
    return {
      credential: admin.credential.cert(serviceAccount),
      projectId: serviceAccount.project_id || process.env.FIREBASE_PROJECT_ID,
    };
  }

  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    return {
      credential: admin.credential.applicationDefault(),
      projectId: process.env.FIREBASE_PROJECT_ID,
    };
  }

  throw new Error(
    'Missing Firebase Admin credentials. Provide FIREBASE_SERVICE_ACCOUNT_JSON, ' +
      'or FIREBASE_PROJECT_ID/FIREBASE_CLIENT_EMAIL/FIREBASE_PRIVATE_KEY, ' +
      'or GOOGLE_APPLICATION_CREDENTIALS.',
  );
}

function getFirebaseAdminApp() {
  if (initializedApp) {
    return initializedApp;
  }

  initializedApp = admin.apps.length
    ? admin.app()
    : admin.initializeApp(buildFirebaseOptions());

  return initializedApp;
}

function getFirebaseAuth() {
  return getFirebaseAdminApp().auth();
}

module.exports = {
  getFirebaseAdminApp,
  getFirebaseAuth,
};
