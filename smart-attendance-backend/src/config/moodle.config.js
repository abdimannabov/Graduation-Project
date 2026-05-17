const url = process.env.MOODLE_URL;
const token = process.env.MOODLE_TOKEN;

if (!url || !token) {
  // Fail fast with a clear message so developers notice missing env values early
  throw new Error('Missing MOODLE_URL or MOODLE_TOKEN environment variable. Add them to your .env file (see .env.example).');
}

// Ensure there's no duplicated slash
const baseUrl = url.endsWith('/') ? `${url}webservice/rest/server.php` : `${url}/webservice/rest/server.php`;

// Allow local development with self-signed certs when explicitly enabled
const allowInsecureTLS = process.env.MOODLE_ALLOW_INSECURE_TLS === 'true';

module.exports = { url, baseUrl, token, allowInsecureTLS };
