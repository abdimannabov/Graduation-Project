# Anti-Cheating Attendance System - Complete Architecture

## Executive Summary

This document describes a **multi-layer anti-cheating** system designed to prevent students from:

- Scanning QR codes from outside the classroom (location spoofing)
- Using someone else's phone (device swapping)
- Scanning multiple times with the same QR (duplicate submission)
- Modifying attendance records after submission
- Replaying old attendance data

---

## System Layers

### Layer 1: Device Binding & Enrollment

**Goal:** Ensure each student is tied to a single, specific device.

#### Sign-Up Flow

1. Student creates account with email, password, name
2. **App captures device ID:**
   - Android: `DeviceInfoPlugin.androidInfo.id` (unique per device)
   - iOS: `DeviceInfoPlugin.iosInfo.identifierForVendor` (unique per app + device combo)
3. **Check Firestore** for existing registrations with this device
   - If device already registered to another account → block signup with message
   - If device is new → proceed
4. **After signup**, persist device ID to Firestore:
   ```json
   users/{uid}: {
     "email": "student@uni.edu",
     "name": "John Doe",
     "deviceId": "abc123xyz789",
     "createdAt": Timestamp
   }
   ```

#### Why It Works

- Device ID is hardware-locked (cannot be spoofed without physical device access)
- One account per device prevents "device sharing" cheating
- Immutable binding prevents post-enrollment device swaps

---

### Layer 2: Sign-In Device Verification

**Goal:** Prevent unauthorized access from unregistered devices.

#### Sign-In Flow

1. Student enters email + password
2. **After successful Firebase Auth**:
   - App retrieves device ID of current device
   - Fetch user record from Firestore: `users/{uid}`
   - Compare: `currentDeviceId == storedDeviceId`
3. **If mismatch:**
   - Log suspicious activity to `suspicious_activity_logs`
   - Sign out the user immediately
   - Show: "You are not allowed to login from this device"
4. **If match:** Allow access

#### Why It Works

- Prevents account takeover via credentials (attacker would need the specific physical device)
- Catches stolen credentials early
- Auto-logs suspicious attempts for admin investigation

---

### Layer 3: QR Scan Validation - Multi-Check Strategy

**Goal:** Ensure attendance is only recorded when student is physically present at classroom.

#### Pre-Scan Checks (App Side)

**Check A: Device Binding Verification**

```
BEFORE attempting to scan QR:
  1. Get current device ID
  2. Fetch user's stored deviceId from Firestore (users/{uid})
  3. If NOT EQUAL:
     → Block scan
     → Log: suspicious_activity_logs { type: "device_mismatch_attendance_attempt" }
     → Sign out user
     → Message: "Unauthorized device ❌"
```

**Check B: Duplicate Scan Prevention**

```
AFTER scanning QR code:
  1. Query: attendance/{userId}/records
     WHERE qr_value == scanned_code
     AND timestamp >= (now - 1 hour)
  2. If ANY document found:
     → Block recording
     → Log: suspicious_activity_logs { type: "duplicate_scan_attempt" }
     → Message: "You already scanned this QR ❌"
```

**Check C: Location Verification (WiFi IP)**

```
AFTER scanning QR code:
  1. Get current WiFi IP: NetworkInfo.getWifiIP()
  2. Query: valid_qrs WHERE code == scanned_code
  3. Get ip_address from valid QR document
  4. If current_ip != valid_qr_ip:
     → Block recording
     → Log: suspicious_activity_logs { type: "wrong_location_attendance_attempt" }
     → Message: "You are not at the classroom ❌"
```

#### Post-Scan Actions (If All Checks Pass)

1. **Write to attendance collection:**

   ```json
   attendance/{userId}/records/{auto-id}: {
     "qr_value": "code-123",
     "timestamp": Timestamp.now(),
     "email": "student@uni.edu",
     "ip_verified": true,
     "ip_address": "192.168.1.42",
     "device_verified": true,
     "status": "Present"
   }
   ```

2. **Write to audit log:**
   ```json
   attendance_logs/{auto-id}: {
     "userId": "uid",
     "email": "student@uni.edu",
     "qr_code": "code-123",
     "timestamp": Timestamp.now(),
     "ip_address": "192.168.1.42",
     "device_verified": true,
     "location_verified": true,
     "status": "Present"
   }
   ```

---

### Layer 4: Server-Side Validation (Firestore Rules)

**Goal:** Prevent malicious clients from bypassing app-side checks.

#### Critical Rules

1. **Timestamp freshness:** Record must be within last 2 hours
2. **Mandatory fields:** `qr_value`, `ip_address`, `timestamp`, `device_verified` (all must exist)
3. **Device verified flag:** Must be `true` (attacker cannot just omit the check)
4. **Status must be:** Exactly `"Present"` (no null, empty, or other values)
5. **No updates/deletes:** Once written, records are immutable

#### Why Double Validation?

- **App validation** catches 99% of cheating (catches students using the app normally)
- **Server validation** stops sophisticated attackers who:
  - Intercept Firebase SDK calls
  - Craft custom API requests
  - Use modified APK/IPA

---

### Layer 5: Audit Logging & Admin Monitoring

**Goal:** Detect and investigate suspicious patterns.

#### Suspicious Activity Logs

Every failed scan attempt creates an entry:

```json
suspicious_activity_logs/{auto-id}: {
  "type": "device_mismatch_attendance_attempt",
  "userId": "uid",
  "email": "student@uni.edu",
  "storedDeviceId": "correct_device_id",
  "attemptedDeviceId": "hacker_device_id",
  "timestamp": Timestamp.now()
}
```

**Types of Suspicious Activity Logged:**

1. `device_mismatch_login_attempt` — failed login from unregistered device
2. `device_mismatch_attendance_attempt` — tried to scan from wrong device
3. `duplicate_scan_attempt` — scanned same QR twice in 1 hour
4. `wrong_location_attendance_attempt` — tried to scan from outside classroom IP
5. `invalid_qr_scan_attempt` — scanned fake/expired QR code

#### Admin Queries for Detection

```javascript
// Red flag: Multiple failed attempts for one student
db.collection("suspicious_activity_logs")
  .where("userId", "==", "uid")
  .orderBy("timestamp", "desc")
  .limit(10)
  .get();
// If > 3 attempts in 1 day → manual review

// Red flag: Device swap patterns
db.collection("suspicious_activity_logs")
  .where("type", "==", "device_mismatch_attendance_attempt")
  .where("timestamp", ">=", Date.now() - 24 * 60 * 60 * 1000)
  .get();
// Investigate each incident

// Red flag: Attendance from impossible location
db.collection("suspicious_activity_logs")
  .where("type", "==", "wrong_location_attendance_attempt")
  .where("timestamp", ">=", Date.now() - 24 * 60 * 60 * 1000)
  .get();
// Campus only, no VPN/proxy

// Red flag: Same device, multiple users
db.collection("suspicious_activity_logs")
  .where("type", "==", "device_mismatch_login_attempt")
  .where("attemptedDeviceId", "==", "suspicious_device_id")
  .get();
// Indicates shared device usage
```

---

## Cheating Scenario Walkthrough

### Scenario 1: Student Tries to Cheat by Scanning from Home

**Student Action:** Scan classroom QR code from home WiFi (different IP)

**System Response:**

1. ✓ Device check passes (student's own phone)
2. ✓ Duplicate check passes (first scan of the day)
3. ✗ **Location check FAILS** (home IP ≠ classroom IP)
4. App blocks: "You are not at the classroom ❌"
5. Logged to `suspicious_activity_logs` as `wrong_location_attendance_attempt`
6. Admin sees attempt, investigates IP/time

---

### Scenario 2: Student Lends Phone to Friend

**Setup:** Student A (phone X, device ID = aaa111) lends phone to Student B

**Student B Action:** Signs into Student B's account on borrowed Phone X

**System Response:**

1. Phone X tries to authenticate as Student B
2. App gets device ID from Phone X = aaa111
3. Firestore lookup: Student B's stored device ID = bbb222
4. ✗ **Device mismatch detected**
5. Firebase Auth signs out Student B
6. Message: "You are not allowed to login from this device"
7. Logged as `device_mismatch_login_attempt`
8. Admin sees incident, flags account for investigation

---

### Scenario 3: Student Tries to Scan QR Twice

**Student A Action:** Scans QR at 9:00 AM, then scans same QR again at 9:05 AM

**System Response (2nd Scan):**

1. ✓ Device check passes
2. ✗ **Duplicate check FAILS** (same code scanned 5 min ago)
3. App queries: `attendance/{uid}/records WHERE qr_value == code AND timestamp >= (now - 1 hour)`
4. Finds 1st record from 5 min ago
5. Blocks: "You already scanned this QR ❌"
6. Logged as `duplicate_scan_attempt`
7. Server-side rule also prevents write (if somehow app-check bypassed)

---

### Scenario 4: Attacker Intercepts & Replays Old Attendance

**Attack:** Hacker intercepts valid attendance record from 2 days ago, replays it today

**System Response:**

1. Server receives: `timestamp: 2 days ago`
2. Firestore rule checks: `isValidTimestamp(timestamp)`
3. Rule validates: `timestamp <= now && timestamp >= (now - 2 hours)`
4. ✗ **Timestamp is outside 2-hour window**
5. **Write rejected** by Firestore rules

---

### Scenario 5: Sophisticated Attacker Modifies APK

**Attack:** Hacker modifies app to set `device_verified: false` and `status: "Absent"`

**System Response:**

1. Modified app sends:
   ```json
   {
     "qr_value": "code",
     "device_verified": false, // ← Attacker set this
     "status": "Absent" // ← Attacker set this
   }
   ```
2. Firestore rule checks:
   ```javascript
   request.resource.data.device_verified is bool &&
   request.resource.data.device_verified == true &&
   request.resource.data.status is string &&
   request.resource.data.status == 'Present'
   ```
3. ✗ **Both checks fail**
4. **Write rejected**
5. No record created

---

## Deployment Checklist

- [ ] **Sign-Up Screen**

  - [ ] Add `getDeviceId()` helper
  - [ ] Add device uniqueness check before signup
  - [ ] Persist `deviceId` to Firestore on signup success
  - [ ] Test: sign up on Device A, ensure device ID saved

- [ ] **Sign-In Screen**

  - [ ] Add device verification after successful Auth
  - [ ] Compare current device ID to stored device ID
  - [ ] Block + logout if mismatch
  - [ ] Log suspicious attempt
  - [ ] Test: sign in on Device A (✓ pass), sign in on Device B (✗ fail)

- [ ] **QR Scan Screen**

  - [ ] Add `_getDeviceId()` helper
  - [ ] Add `_checkDuplicateAttendance()` check
  - [ ] Add `_verifyDeviceBinding()` check
  - [ ] Check IP before recording
  - [ ] Write to both `attendance` and `attendance_logs`
  - [ ] Log suspicious activities
  - [ ] Test all 5 blocking scenarios above

- [ ] **Firestore Collections**

  - [ ] Ensure `users` collection exists with `deviceId` field
  - [ ] Ensure `valid_qrs` collection exists with `ip_address` field
  - [ ] Create `attendance` subcollections under `users/{uid}`
  - [ ] Create `attendance_logs` collection
  - [ ] Create `suspicious_activity_logs` collection

- [ ] **Firestore Rules**

  - [ ] Deploy rules from `FIRESTORE_SECURITY_RULES.md`
  - [ ] Test each rule in Rules Playground
  - [ ] Publish to production

- [ ] **Admin Dashboard** (future)
  - [ ] Display `suspicious_activity_logs`
  - [ ] Filter by type, date, user
  - [ ] Manual review workflow
  - [ ] Action: flag account, force re-enrollment, investigate

---

## Security Best Practices

### ✅ Do's

- ✅ Always verify device binding before any sensitive operation
- ✅ Log all failed attempts comprehensively
- ✅ Use server-side validation as the source of truth
- ✅ Make timestamps immutable (server-generated only)
- ✅ Make attendance records immutable after creation
- ✅ Review suspicious activity logs weekly
- ✅ Require device re-verification on app updates/reinstall

### ❌ Don'ts

- ❌ Trust client timestamps (always use server time)
- ❌ Allow clients to set `device_verified` or `status` (admin only)
- ❌ Permit attendance record updates (creates audit trail gaps)
- ❌ Skip IP verification because "everyone's on campus network"
- ❌ Ignore suspicious activity logs
- ❌ Store device IDs in plain text (encrypt in storage if possible)

---

## Monitoring & Incident Response

### Weekly Admin Tasks

1. Check `suspicious_activity_logs` for new entries
2. Investigate any `device_mismatch_*` patterns
3. Review students with 3+ failed attempts
4. Check for impossible locations (VPN detected?)

### Alert Thresholds

- 🟢 Green: 0 suspicious activities per student per day
- 🟡 Yellow: 1-2 incidents (could be honest mistakes)
- 🔴 Red: 3+ incidents (investigate + potential disciplinary action)

### Incident Response Workflow

1. **Detect** → Admin sees suspicious activity in logs
2. **Investigate** → Cross-check timestamp, device, IP with classroom records
3. **Verify** → Contact student to confirm (might be device reset, WiFi issues)
4. **Action** → Warn, flag, or escalate to administration
5. **Document** → Add notes to student record

---

## Future Enhancements

- [ ] GPS location validation (not just WiFi IP)
- [ ] Biometric verification (fingerprint/face) for critical scans
- [ ] Machine learning to detect suspicious patterns automatically
- [ ] Admin dashboard with analytics and heatmaps
- [ ] Integration with institution's student database
- [ ] Encrypted device ID storage
- [ ] Rate limiting per device (max 1 scan per 5 min)
- [ ] Geofencing alerts if student tries to register from outside campus

---

## Conclusion

This **5-layer security model** makes cheating extremely difficult:

1. **Device binding** prevents device sharing
2. **Sign-in verification** prevents unauthorized access
3. **Pre-scan checks** catch location spoofing and duplicates
4. **Server validation** blocks sophisticated attacks
5. **Audit logging** enables investigation and deterrence

The system is **not 100% hack-proof** (no system is), but it raises the bar so high that:

- Casual cheating is blocked immediately
- Coordinated cheating is detectable
- Sophisticated attacks require modifying the app or hacking Firestore rules
- All attempts are logged for administrative review
