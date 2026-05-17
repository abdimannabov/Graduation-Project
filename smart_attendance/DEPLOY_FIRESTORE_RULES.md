# 🚨 URGENT: Deploy Firestore Security Rules

**Your current Firestore rules expire on November 27, 2025 (15 days from now).**

After that date, **ALL** requests to your database will be **DENIED** unless you update the rules.

---

## Step-by-Step Deployment

### 1. Open Firebase Console

- Go to: https://console.firebase.google.com/
- Select your project: **attendance-system-3a571**

### 2. Navigate to Firestore Rules

- Click on **Firestore Database** in the left sidebar
- Click on the **Rules** tab at the top

### 3. Replace the Default Rules

You will see the temporary rule that looks like this:

```javascript
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.time < timestamp.date(2025, 11, 27);
    }
  }
}
```

**DELETE ALL OF THIS** and replace it with the complete rules from `FIRESTORE_SECURITY_RULES.md` (the entire code block under "## Firestore Rules Code").

### 4. Copy the New Rules

Go to `FIRESTORE_SECURITY_RULES.md` in your project and copy the entire rules code starting from:

```javascript
rules_version = '2';
service cloud.firestore {
  // ... all the helper functions and match statements ...
}
```

### 5. Paste and Publish

- Paste the new rules into the Firebase Console rules editor
- Click **Publish** button
- Wait for the rules to be published (takes ~1 minute)

---

## What These Rules Do

✅ **Protect your data** from unauthorized access  
✅ **Enforce device binding** - students can't cheat from different devices  
✅ **Validate attendance** - only valid scans are recorded  
✅ **Prevent tampering** - attendance records are immutable  
✅ **Log suspicious activity** - admins can monitor cheating attempts

---

## Key Security Features

| Feature              | Protects Against                             |
| -------------------- | -------------------------------------------- |
| Device Binding       | Students signing into each other's accounts  |
| IP Verification      | Students scanning from home/outside campus   |
| Duplicate Detection  | Students scanning the same QR multiple times |
| Timestamp Validation | Replaying old attendance records             |
| Immutable Records    | Changing "Present" to "Absent"               |
| Audit Logging        | Undetected cheating attempts                 |

---

## ⚠️ Important Notes

1. **These rules require device binding to work** - ensure `sign_up_screen.dart` correctly saves `deviceId` to Firestore (see debug logs)

2. **Test before going live**:

   - Create a test account
   - Verify `deviceId` appears in Firestore `users` collection
   - Try to sign in from a different device (should be blocked)
   - Try to scan a QR code (should work from original device, fail from new device)

3. **If deployment fails**:

   - Check that all collection names match exactly: `users`, `valid_qrs`, `attendance`, `attendance_logs`, `suspicious_activity_logs`
   - Verify the syntax is correct (no typos)
   - Use the **Rules Playground** to debug

4. **Admin access**:
   - Add your admin user's UID to the rules if needed
   - The current rules assume `role: 'admin'` field in `users` collection

---

## Rules Playground Testing

Before publishing, you can test the rules:

1. Click **Rules Playground** button in the editor
2. Select a test case (e.g., "Create Attendance")
3. Modify the request/document data as needed
4. Click **Run** to see if the rule allows/denies the operation

---

## Deployment Checklist

- [ ] Device ID being saved to Firestore (check sign_up_screen.dart debug logs)
- [ ] Copy the complete rules from FIRESTORE_SECURITY_RULES.md
- [ ] Replace the temporary rules in Firebase Console
- [ ] Click **Publish** and wait for confirmation
- [ ] Create a test account and verify deviceId is stored
- [ ] Test sign-in from different device (should fail)
- [ ] Test QR scanning from original device (should work)
- [ ] Add suspicious_activity_logs to Firestore (auto-created on first write)

---

## Need Help?

If rules fail to publish:

1. Check the error message in Firebase Console
2. Verify all JavaScript syntax is correct
3. Ensure all field names match exactly (case-sensitive)
4. Use the Rules Playground to test individual match statements

Once deployed, your attendance system is **production-ready and cheating-proof! 🔒**
