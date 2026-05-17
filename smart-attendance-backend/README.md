# Smart Attendance Backend

This backend communicates with Moodle using a WebService token and exposes APIs for QR-based attendance marking.

Prerequisites

- Node.js (16+ recommended)
- A Moodle instance with WebService enabled
- A Moodle token with access to user and attendance APIs

Quick start

1. Copy `.env.example` to `.env` and set `MOODLE_URL` and `MOODLE_TOKEN`.
2. Install dependencies:

```powershell
npm install
```

3. Run in development mode:

```powershell
npm run dev
```

Or run once:

```powershell
npm start
```

API endpoints

- `GET /api/moodle/ping`: validate Moodle connectivity/token.
- `POST /api/moodle/verify-user`: body `{ "email": "student@uni.edu" }`.
- `POST /api/attendance/qr` (auth required): generate a short-lived QR token.
- `POST /api/attendance/mark` (auth required): mark attendance using either your signed QR token or a Moodle attendance QR URL.
- `GET /api/attendance/sessions?attendanceId=XXX`: list raw Moodle attendance sessions.

Flutter integration contract

1. Professor generates a QR token:

```http
POST /api/attendance/qr
Headers:
  x-user-email: teacher@university.edu
  x-teacher-secret: <TEACHER_SECRET>
Body:
{
  "attendanceId": 12,
  "sessionId": 88,
  "wifiConstraint": {
    "bssid": "AA:BB:CC:DD:EE:FF"
  }
}
```

- `wifiConstraint` is optional.
- If provided, include `bssid` (AP MAC address).

2. Student scans QR and marks attendance:

```http
POST /api/attendance/mark
Headers:
  x-user-email: student@university.edu
Body:
{
  "qrToken": "<token-from-qr>",
  "wifiData": {
    "bssid": "AA:BB:CC:DD:EE:FF"
  }
}
```

- If QR contains `wifiConstraint`, backend compares it with `wifiData` and rejects mismatches.
- Backward compatible input is also accepted in root body fields: `bssid`, `mac`, `macAddress`.
- `qrToken` may also be a Moodle attendance URL like `http://moodle.local/mod/attendance/attendance.php?sessid=11&qrpass=abc123`.
- For Moodle QR URLs, the backend resolves the `sessid`, verifies the scanned session is open for student self-recording, maps the app user to Moodle by email, and marks the student through Moodle's attendance web service.

Notes and troubleshooting

- If you see missing `MOODLE_URL` or `MOODLE_TOKEN`, verify `.env` is present and loaded by `src/server.js`.
- In local development with `AUTH_MODE=dev`, send `x-user-email` for requests behind auth middleware.
- In release environments, use `AUTH_MODE=firebase` and send `Authorization: Bearer <Firebase ID token>`.
- `AUTH_MODE=dev` is intentionally rejected when `NODE_ENV=production`.
- For local/self-signed Moodle certs, set `MOODLE_ALLOW_INSECURE_TLS=true` (development only).
- Use `attendance-flow.http` with the VSCode REST Client extension to simulate the full QR flow.
- Wi-Fi validation logs are printed to server console, including:
  - `Wi-Fi bssid matched`
  - `Wi-Fi mismatch detected`
