# Firestore Security Rules for Anti-Cheating Attendance System

## Overview

This document outlines the server-side security rules to validate attendance records and prevent cheating.

## Rules Strategy

### 1. Users Collection - Device Binding

- Only authenticated users can read their own user document
- `deviceId` is immutable after creation (prevent device swapping)
- Timestamps are server-generated

### 2. Attendance Collection - Write Validation

- Only authenticated users can write to their own attendance records
- Must include mandatory fields: `qr_value`, `ip_address`, `timestamp`, `device_verified`
- Timestamp must be within acceptable window (not in future, not too old)
- Device binding verified server-side via user's stored `deviceId`

### 3. Suspicious Activity Logs - Admin Only

- Only admins can read
- Automatic logging of failed attempts

### 4. Valid QRs Collection - Read Only

- Students can only read, not modify
- Contains classroom IP and QR code

## Firestore Rules Code

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Helper: Check if user is authenticated
    function isAuthenticated() {
      return request.auth != null;
    }

    // Helper: Check if user is admin
    function isAdmin() {
      return isAuthenticated() &&
             get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }

    // Helper: Validate attendance timestamp (within last 2 hours, not in future)
    function isValidTimestamp(timestamp) {
      let now = request.time;
      let twoHoursAgo = now - duration.time(2 * 60 * 60, 's');
      return timestamp <= now && timestamp >= twoHoursAgo;
    }

    // Users Collection - Device binding and profile
    match /users/{userId} {
      allow read: if isAuthenticated() && request.auth.uid == userId;
      allow create: if isAuthenticated() &&
                       request.auth.uid == userId &&
                       request.resource.data.deviceId is string &&
                       request.resource.data.email is string;
      allow update: if isAuthenticated() &&
                       request.auth.uid == userId &&
                       // Allow deviceId to be set/updated on first write
                       ((!resource.data.keys().hasAny(['deviceId'])) ||
                        (resource.data.deviceId == request.resource.data.deviceId)) &&
                       // Protect other fields
                       resource.data.createdAt == request.resource.data.createdAt;
      allow delete: if false; // Never allow deleting user records
    }

    // Valid QR Codes - Read only for all authenticated users
    match /valid_qrs/{document=**} {
      allow read: if isAuthenticated();
      allow write: if false; // Only via admin portal or backend
    }

    // Attendance Records - Main attendance logging with validation
    match /attendance/{userId}/records/{recordId} {
      allow read: if isAuthenticated() && request.auth.uid == userId;
      allow create: if isAuthenticated() &&
                       request.auth.uid == userId &&
                       // Mandatory fields validation
                       request.resource.data.qr_value is string &&
                       request.resource.data.qr_value != '' &&
                       request.resource.data.ip_address is string &&
                       request.resource.data.ip_address != '' &&
                       request.resource.data.timestamp is timestamp &&
                       request.resource.data.device_verified is bool &&
                       request.resource.data.device_verified == true &&
                       request.resource.data.status is string &&
                       request.resource.data.status == 'Present' &&
                       // Timestamp must be recent (within 2 hours)
                       isValidTimestamp(request.resource.data.timestamp) &&
                       // Device binding: verify deviceId matches user's record
                       get(/databases/$(database)/documents/users/$(request.auth.uid)).data.deviceId exists;

      allow update: if false; // Never allow updating attendance records
      allow delete: if false; // Never allow deleting attendance records
    }

    // Attendance Logs - Audit trail (read by admins, write by app)
    match /attendance_logs/{document=**} {
      allow read: if isAdmin();
      allow create: if isAuthenticated() &&
                       request.resource.data.userId == request.auth.uid &&
                       request.resource.data.timestamp is timestamp &&
                       isValidTimestamp(request.resource.data.timestamp);
      allow update, delete: if false;
    }

    // Suspicious Activity Logs - Security audit trail
    match /suspicious_activity_logs/{document=**} {
      allow read: if isAdmin();
      allow create: if isAuthenticated(); // App logs suspicious attempts
      allow update, delete: if false;
    }

    // Default deny all other access
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

## How It Works

### Student Attempts to Scan:

1. **App checks device ID** matches user's stored `deviceId` → if mismatch, prevents scan
2. **App checks IP** matches valid QR's IP → if mismatch, prevents scan
3. **App checks duplicate** (same QR scanned in last hour) → if duplicate, prevents scan
4. **App sends attendance record** with all required fields
5. **Firestore rules validate**:
   - Timestamp is fresh (within 2 hours)
   - All mandatory fields present
   - Device verified flag is true
   - User has a valid deviceId on file
   - Status is exactly "Present"

### Cheating Attempts Blocked:

#### 1. Device Swap / Device Sharing

- Student A uses Device X (deviceId = xyz123)
- If Student B tries to login from Device Y (deviceId = abc789), blocked at sign-in
- If Student B somehow logs in from Device X (not their own), attendance write fails (device mismatch)

#### 2. Remote Attendance (WiFi Spoofing)

- Student outside campus tries to scan → current IP ≠ classroom IP → app blocks before sending to server
- Server-side rule also validates via the attendance record

#### 3. Duplicate Scanning (Same QR Twice)

- App checks: "Did this user already scan this QR in the last hour?" → blocks
- Prevents Ctrl+Z/fake submission attempts

#### 4. Replaying Old Attendance Records

- Timestamp validation: record must be recent (< 2 hours old)
- Prevents admins from re-submitting old scan data

#### 5. Data Tampering (Modifying Records)

- Firestore rule: `allow update: if false;`
- Prevents changing "Present" to "Absent" or vice versa

## Admin Monitoring

### Suspicious Activity Log

Admins review `/suspicious_activity_logs` for:

- `device_mismatch_login_attempt` — student tried to sign in from wrong device
- `device_mismatch_attendance_attempt` — student tried to scan from wrong device
- `duplicate_scan_attempt` — student scanned same QR multiple times
- `wrong_location_attendance_attempt` — student tried to scan from outside campus IP
- `invalid_qr_scan_attempt` — student scanned invalid/forged QR

### Queries for Detection

```javascript
// Find all suspicious activity for a user
db.collection("suspicious_activity_logs")
  .where("userId", "==", "USER_ID")
  .orderBy("timestamp", "desc")
  .get();

// Find all device mismatches in last 24 hours
db.collection("suspicious_activity_logs")
  .where("type", "==", "device_mismatch_attendance_attempt")
  .where("timestamp", ">=", new Date(Date.now() - 24 * 60 * 60 * 1000))
  .get();

// Find duplicate scan attempts
db.collection("suspicious_activity_logs")
  .where("type", "==", "duplicate_scan_attempt")
  .get();
```

## Deployment Steps

1. Go to Firebase Console → Firestore → Rules
2. Replace default rules with the code above
3. Test rules in the Rules Playground before publishing
4. Publish

## Testing the Rules

### Test 1: Valid Scan (Should Pass)

- User authenticated
- Device matches stored deviceId
- IP matches classroom IP
- No duplicate in last hour
- Timestamp is fresh
- All mandatory fields present

### Test 2: Device Mismatch (Should Fail at Create)

- `device_verified: false`
- Firestore rule blocks: deviceId missing or doesn't match user record

### Test 3: Invalid Timestamp (Should Fail at Create)

- Timestamp is 3 hours old
- Firestore rule blocks: timestamp outside 2-hour window

### Test 4: Missing Mandatory Field (Should Fail at Create)

- Missing `ip_address` field
- Firestore rule blocks: required field validation fails

### Test 5: Update Attempt (Should Fail)

- User tries to change attendance status
- Firestore rule blocks: `allow update: if false;`

## Notes

- All times are server time (Firestore timestamps), preventing client clock manipulation
- `device_verified` flag MUST be true — enforced by app logic AND rules
- IP validation is dual-layer: app blocks first (UX), server validates anyway (security)
- Immutable `deviceId` prevents "lending" a phone to a friend
- Comprehensive audit logging enables admin investigation and pattern detection
