const axios = require('axios');
const https = require('https');
const { baseUrl, token, allowInsecureTLS } = require('../config/moodle.config');

// Create an axios instance so we can attach an httpsAgent when needed (for self-signed certs)
const axiosOptions = { timeout: 10000 };
if (baseUrl.startsWith('https') && allowInsecureTLS) {
  axiosOptions.httpsAgent = new https.Agent({ rejectUnauthorized: false });
}
const client = axios.create(axiosOptions);
let cachedSiteInfoPromise = null;

async function callMoodle(wsfunction, params = {}) {
  try {
    const response = await client.post(baseUrl, null, {
      params: {
        wstoken: token,
        wsfunction,
        moodlewsrestformat: 'json',
        ...params,
      },
    });

    const data = response.data;

    // Moodle errors are often returned as an object with 'exception' / 'errorcode'
    if (data && (data.exception || data.error)) {
      const message = data.message || data.error || JSON.stringify(data);
      throw new Error(`Moodle API error: ${message}`);
    }

    return data;
  } catch (err) {
    // Wrap axios errors to provide clearer context
    if (err.response && err.response.data) {
      throw new Error(`Moodle request failed: ${JSON.stringify(err.response.data)}`);
    }
    throw new Error(`Moodle request failed: ${err.message}`);
  }
}

async function getUserByEmail(email) {
  const normalizedEmail = String(email).trim().toLowerCase();

  const res = await callMoodle('core_user_get_users_by_field', {
    field: 'email',
    'values[0]': normalizedEmail,
  });

  // Moodle returns an array
  if (!Array.isArray(res)) return [];

  return res; // ✅ return array always
}


async function getAttendanceSessions(attendanceid) {
  return callMoodle('mod_attendance_get_sessions', {
    attendanceid,
  });
}

async function getAttendanceSession(sessionid) {
  return callMoodle('mod_attendance_get_session', {
    sessionid,
  });
}

async function resolveTakenById(takenbyid) {
  const explicitTakenById = Number(takenbyid);
  if (Number.isInteger(explicitTakenById) && explicitTakenById > 0) {
    return explicitTakenById;
  }

  if (!cachedSiteInfoPromise) {
    cachedSiteInfoPromise = getSiteInfo().catch(err => {
      cachedSiteInfoPromise = null;
      throw err;
    });
  }

  const siteInfo = await cachedSiteInfoPromise;
  const inferredTakenById = Number(siteInfo && siteInfo.userid);
  if (Number.isInteger(inferredTakenById) && inferredTakenById > 0) {
    return inferredTakenById;
  }

  return undefined;
}

async function markAttendance({ sessionid, studentid, statusid, statusset, takenbyid }) {
  // Build params dynamically so optional ones are only sent when present
  const params = { sessionid, studentid, statusid };
  if (statusset) params.statusset = statusset;
  const resolvedTakenById = await resolveTakenById(takenbyid);
  if (resolvedTakenById) params.takenbyid = resolvedTakenById;

  return callMoodle('mod_attendance_update_user_status', params);
}

async function getSiteInfo() {
  // Useful for validating token and connectivity
  return callMoodle('core_webservice_get_site_info');
}

module.exports = {
  getUserByEmail,
  getAttendanceSessions,
  getAttendanceSession,
  markAttendance,
  getSiteInfo,
  resolveTakenById,
};
