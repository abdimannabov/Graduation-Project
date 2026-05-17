# Anti-Cheating Attendance System - Quick Start Guide

## Summary of Changes

Your attendance system now has **5-layer security** to prevent cheating:

### What Was Implemented

#### 1. **Sign-Up Screen** (`sign_up_screen.dart`)

- ✅ Captures device ID on signup
- ✅ Checks if device is already registered to another account
- ✅ Blocks signup if device is already in use
- ✅ Stores `deviceId` to Firestore `users` collection after signup

#### 2. **Sign-In Screen** (`sign_in_screen.dart`)

- ✅ Verifies device ID matches stored device ID
- ✅ Blocks login from unregistered devices
- ✅ Logs suspicious device mismatch attempts
- ✅ Auto-logs out if device doesn't match

#### 3. **QR Scan Screen** (`scan_screen.dart`)

- ✅ Checks device binding BEFORE scanning
- ✅ Checks for duplicate scans (same QR in last hour)
- ✅ Checks IP address matches classroom WiFi
- ✅ Logs all suspicious attempts
- ✅ Writes to audit log for admin review
- ✅ Server-side validation catches sophisticated attacks

#### 4. **Security Rules** (`FIRESTORE_SECURITY_RULES.md`)

- ✅ Timestamp validation (2-hour window)
- ✅ Mandatory field enforcement
- ✅ Immutable records (no updates/deletes)
- ✅ Server-side device verification
- ✅ Admin-only access to logs

#### 5. **Audit & Monitoring** (Multiple Collections)

- ✅ `suspicious_activity_logs` — all failed attempts
- ✅ `attendance_logs` — successful scans with metadata
- ✅ Admin queries to detect patterns

---

## Firestore Collections Setup

Before deploying, ensure these collections exist in Firestore:

### 1. `users` Collection

**Document ID:** Firebase Auth UID

**Fields:**

```json
{
  "email": "student@university.edu",
  "name": "John Doe",
  "deviceId": "abc123def456",
  "createdAt": Timestamp,
  "role": "student"  // optional, for admin check
}
```

### 2. `valid_qrs` Collection

**Document ID:** Auto or custom (e.g., `ROOM101_2025-11-12`)

**Fields:**

```json
{
  "code": "SMARTATTEND-ROOM101-2025-11-11-ABC123",
  "ip_address": "192.168.1.42",
  "active": true,
  "created_at": Timestamp,
  "classroom": "Room 101",
  "expires_at": Timestamp  // optional
}
```

### 3. `attendance/{userId}/records` Sub-collection

**Document ID:** Auto-generated

**Fields:**

```json
{
  "qr_value": "SMARTATTEND-ROOM101-2025-11-11-ABC123",
  "timestamp": Timestamp,
  "email": "student@university.edu",
  "ip_verified": true,
  "ip_address": "192.168.1.42",
  "device_verified": true,
  "status": "Present"
}
```

### 4. `attendance_logs` Collection

**Document ID:** Auto-generated

**Fields:**

```json
{
  "userId": "firebase_uid",
  "email": "student@university.edu",
  "qr_code": "SMARTATTEND-ROOM101-2025-11-11-ABC123",
  "timestamp": Timestamp,
  "ip_address": "192.168.1.42",
  "device_verified": true,
  "location_verified": true,
  "status": "Present"
}
```

### 5. `suspicious_activity_logs` Collection

**Document ID:** Auto-generated

**Fields:**

```json
{
  "type": "device_mismatch_login_attempt",  // or other types
  "userId": "firebase_uid",
  "email": "student@university.edu",
  "timestamp": Timestamp,
  // Type-specific fields:
  "storedDeviceId": "expected_device_id",
  "attemptedDeviceId": "hacker_device_id",
  "qr_code": "code_if_applicable",
  "expected_ip": "192.168.1.42",
  "attempted_ip": "10.0.0.5"
}
```

---

## Deployment Steps

### Step 1: Update Firestore Rules

1. Open Firebase Console → Firestore Database → Rules
2. Replace existing rules with content from `FIRESTORE_SECURITY_RULES.md`
3. Test in Rules Playground before publishing
4. Publish

### Step 2: Build & Test App

```bash
cd d:\Mobile Dev\Graduation Project\smart_attendance
flutter clean
flutter pub get
flutter run
```

### Step 3: Test Signup with Device ID

1. Install app on **Device A**
2. Sign up as `student1@test.edu`
3. ✅ Confirm `deviceId` is saved in Firestore `users` collection

### Step 4: Test Sign-In Device Check

1. Try signing in on **Device A** as `student1@test.edu`
   - ✅ Should succeed
2. Try signing in on **Device B** as `student1@test.edu`
   - ❌ Should block with "You are not allowed to login from this device"

### Step 5: Test QR Scanning

1. Create a QR code with content: `SMARTATTEND-ROOM101-2025-11-11-ABC123`
2. Add to Firestore `valid_qrs`:
   ```json
   {
     "code": "SMARTATTEND-ROOM101-2025-11-11-ABC123",
     "ip_address": "192.168.1.42" // Your Device A's WiFi IP
   }
   ```
3. Connect Device A to classroom WiFi (192.168.1.x)
4. Open app and tap "Scan QR"
5. ✅ Scan should succeed → "Attendance recorded ✅"

### Step 6: Test Anti-Cheating Blocks

#### Test 2.1: Duplicate Scan

- Scan same QR again within 1 hour
- ❌ Should block: "You already scanned this QR ❌"

#### Test 2.2: Wrong Location

- Connect Device A to a different WiFi (not 192.168.1.x)
- Try scanning same QR
- ❌ Should block: "You are not at the classroom ❌"

#### Test 2.3: Device Mismatch Attendance

- _(Requires 2 devices)_
- Device A: Student 1's account
- Device B: Try to access Student 1's account, then scan
- ❌ Should block at login: device mismatch error

---

## Admin Monitoring Dashboard (Future)

### Recommended Queries

**Check suspicious activity for a student:**

```javascript
db.collection("suspicious_activity_logs")
  .where("userId", "==", "target_uid")
  .orderBy("timestamp", "desc")
  .get();
```

**Find all device swap attempts in last 24 hours:**

```javascript
db.collection("suspicious_activity_logs")
  .where("type", "==", "device_mismatch_attendance_attempt")
  .where("timestamp", ">=", new Date(Date.now() - 24 * 60 * 60 * 1000))
  .get();
```

**Find all remote attendance attempts:**

```javascript
db.collection("suspicious_activity_logs")
  .where("type", "==", "wrong_location_attendance_attempt")
  .orderBy("timestamp", "desc")
  .get();
```

**Check legitimate attendance:**

```javascript
db.collection("attendance_logs")
  .where("status", "==", "Present")
  .orderBy("timestamp", "desc")
  .get();
```

---

## Troubleshooting

### Issue: "This device is already registered with another account"

**Solution:** Device was previously used by a different student. Options:

1. Factory reset the device (clears device ID)
2. Uninstall and reinstall app (new device ID on some Android versions)
3. Contact admin to unregister device

### Issue: "You are not allowed to login from this device"

**Solution:** Login attempted from a different device than enrollment. Options:

1. Sign in on the original device
2. Device was reset (new device ID) — contact admin to re-enroll
3. Account compromised — change password

### Issue: "You are not at the classroom"

**Solution:** IP address doesn't match classroom WiFi. Options:

1. Confirm connected to correct WiFi network
2. Confirm device WiFi IP is in correct subnet
   - Go to Settings → WiFi → Tap network → View IP
   - Should start with same first 3 octets as classroom IP (e.g., 192.168.1.x)

### Issue: "You already scanned this QR"

**Solution:** Same QR code scanned recently. Options:

1. Wait 1 hour and try again
2. Teacher may have generated a new QR code for same class
3. Contact admin if this is incorrect

---

## Code Files Modified

### New/Updated Files

1. **`lib/screens/auth/sign_up_screen.dart`**

   - Added: Device ID capture & verification
   - Added: Duplicate device check before signup
   - Added: Device ID persistence to Firestore

2. **`lib/screens/auth/sign_in_screen.dart`**

   - Added: Device binding verification after login
   - Added: Device mismatch detection & logging
   - Added: Auto-logout if device doesn't match

3. **`lib/screens/scan_screen.dart`**

   - Added: Device ID verification before scan
   - Added: Duplicate scan detection
   - Added: IP location verification
   - Added: Comprehensive suspicious activity logging
   - Added: Audit log writes to `attendance_logs`

4. **`FIRESTORE_SECURITY_RULES.md`** (New)

   - Server-side validation rules
   - Timestamp freshness checks
   - Immutable record enforcement
   - Admin access controls

5. **`ANTI_CHEATING_ARCHITECTURE.md`** (New)
   - Complete anti-cheating strategy
   - Cheating scenario walkthroughs
   - Monitoring guidelines
   - Future enhancements

---

## Key Security Properties

| Attack                                 | Defense                                  |
| -------------------------------------- | ---------------------------------------- |
| Device sharing (friend uses my phone)  | ✅ Device binding in sign-in             |
| Remote attendance (scanning from home) | ✅ IP/WiFi verification                  |
| Duplicate scanning (scanning QR twice) | ✅ Duplicate detection + Firestore rules |
| Lending phone to friend                | ✅ Device verification + sign-in check   |
| Fake QR codes                          | ✅ Valid QRs collection lookup           |
| Modifying attendance records           | ✅ Immutable records in Firestore        |
| Replaying old attendance               | ✅ Timestamp validation (2-hour window)  |
| Bypassing app validation               | ✅ Server-side Firestore rules           |

---

## Next Steps

1. ✅ Deploy code (sign-up, sign-in, scan screens updated)
2. ✅ Deploy Firestore rules
3. ✅ Create Firestore collections & documents
4. ✅ Test on multiple devices
5. ⏭️ Train teachers on QR generation (use `valid_qrs` collection)
6. ⏭️ Set up admin dashboard to monitor `suspicious_activity_logs`
7. ⏭️ (Optional) Add biometric verification for extra security
8. ⏭️ (Optional) Add GPS geofencing for additional location check

---

## Support

If students encounter issues:

- Check `suspicious_activity_logs` to understand what failed
- Verify device is properly registered (`users` collection)
- Confirm WiFi IP matches expected classroom IP
- Check timestamp is recent (not replaying old attempts)
- Review `ANTI_CHEATING_ARCHITECTURE.md` for detailed scenarios
