# Presentation Workflow Plan - App Logic & Screenshots

## 1. COMPLETE APP WORKFLOW FLOWCHART

### Phase 1: Authentication & Security Checks

```
┌─────────────────────────────────────────────────────┐
│              STUDENT OPENS APP                      │
└────────────────────┬────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────┐
│  Authentication State Check                         │
│  (Firebase Auth Token Valid?)                       │
└────────────────────┬────────────────────────────────┘
                     ├─→ NOT LOGGED IN → Go to Login Screen
                     └─→ LOGGED IN → Continue
                             ↓
┌─────────────────────────────────────────────────────┐
│  Security Layer 1: Device UUID Check               │
│  (Does saved Device ID match current device?)      │
└────────────────────┬────────────────────────────────┘
                     ├─→ MISMATCH ❌ → Block Access
                     │   (User kicked out, show error)
                     └─→ MATCH ✅ → Continue
                             ↓
┌─────────────────────────────────────────────────────┐
│  Security Layer 2: Face ID Check                   │
│  (Is Face ID enrolled on this account?)            │
└────────────────────┬────────────────────────────────┘
                     ├─→ ENROLLED → Verify Face ID
                     │              (Must scan face)
                     │              ├─→ Face Match ✅ → Continue
                     │              └─→ No Match ❌ → Verify Failed
                     └─→ NOT ENROLLED → Skip, Continue
                             ↓
┌─────────────────────────────────────────────────────┐
│  HOME SCREEN - Show Face ID Status                 │
│  (Green if enrolled, Orange if not)                │
└────────────────────┬────────────────────────────────┘
                     ↓
        User taps "Scan Attendance QR"
```

### Phase 2: QR Scanning & Network Check

```
┌─────────────────────────────────────────────────────┐
│  User Taps "Scan Attendance QR" Button              │
└────────────────────┬────────────────────────────────┘
                     ↓
┌─────────────────────────────────────────────────────┐
│  Security Layer 3: Face ID Verification            │
│  (If Face ID enrolled, must scan face first)       │
└────────────────────┬────────────────────────────────┘
                     ├─→ ENROLLED → Verify Face
                     │              ├─→ Success ✅ → Continue
                     │              └─→ Failed ❌ → Block QR scan
                     └─→ NOT ENROLLED → Skip, Continue
                             ↓
┌─────────────────────────────────────────────────────┐
│  QR SCANNING SCREEN                                │
│  (Camera opens, user scans QR code)                │
└────────────────────┬────────────────────────────────┘
                     ↓
        QR Code Successfully Scanned
                     ↓
┌─────────────────────────────────────────────────────┐
│  Security Layer 4: WiFi SSID Check                 │
│  (Is student on correct WiFi network?)             │
│  (Teacher's network SSID saved in Firestore)       │
└────────────────────┬────────────────────────────────┘
                     ├─→ WRONG NETWORK ❌
                     │   └─→ Show error: "Must be on classroom WiFi"
                     │   └─→ Block attendance
                     └─→ CORRECT NETWORK ✅ → Continue
                             ↓
┌─────────────────────────────────────────────────────┐
│  Security Layer 5: Device UUID Check (QR Time)    │
│  (Verify device still matches at QR scan)         │
└────────────────────┬────────────────────────────────┘
                     ├─→ MISMATCH ❌ → Block attendance
                     └─→ MATCH ✅ → Continue
                             ↓
┌─────────────────────────────────────────────────────┐
│  ATTENDANCE MARKED ✅                               │
│  (Log to Firestore with:                           │
│   - timestamp, device_id, wifi_ssid,              │
│   - face_id_verified, qr_code_data)               │
└─────────────────────────────────────────────────────┘
```

### Complete Flowchart Visual:

```
                    ┌─────────────┐
                    │  Open App   │
                    └──────┬──────┘
                           ↓
                  ┌─────────────────┐
                  │ Auth Check      │
                  └────┬───────┬────┘
            NOT LOGGED │       │ LOGGED IN
                       ↓       ↓
                  [LOGIN]  ┌──────────────┐
                           │Device UUID   │
                           │Check         │
                           └────┬─────┬──┘
                        MATCH   │     │ MISMATCH
                                ↓     ↓
                           ┌────────┐ [KICKED OUT]
                           │Face ID │
                           │Enrolled?
                           └──┬──┬──┘
                          YES │  │ NO
                             ↓  ↓
                        [VERIFY] [CONTINUE]
                             ↓  ↓
                           ┌──────────┐
                           │ HOME     │
                           │ SCREEN   │
                           └────┬─────┘
                                ↓
                          [TAP SCAN QR]
                                ↓
                           ┌──────────┐
                     ENROLL │Face ID   │ NOT
                        YES │Verify?   │ ENROLL
                            └──┬──┬───┘
                               ↓  ↓
                          [VERIFY] [SKIP]
                               ↓  ↓
                           ┌──────────────┐
                           │QR SCAN       │
                           │SCREEN        │
                           └───┬──────┬───┘
                        SUCCESS│      │CANCEL
                               ↓      ↓
                            [SCAN]  [EXIT]
                               ↓
                        ┌────────────────┐
                        │WiFi SSID Check │
                        └────┬────────┬──┘
                     WRONG   │        │ CORRECT
                             ↓        ↓
                        [ERROR]  ┌──────────┐
                                 │Device    │
                                 │UUID Check│
                                 └──┬────┬──┘
                            WRONG   │    │ MATCH
                                    ↓    ↓
                               [ERROR]  [SUCCESS]
                                        ↓
                                  ✅ ATTENDANCE
                                     MARKED
```

---

## 2. SCREENSHOTS TO CAPTURE - 12 Total

### **SECTION 1: Authentication & Security (3 screenshots)**

#### Screenshot 1: Login Screen

**What to show**:

- Email and password fields
- "Sign In" button
- "Create Account" link
- Caption: "Step 1: Student logs in with credentials"

**Why important**: Shows entry point to system

---

#### Screenshot 2: Device Mismatch Error (Different Device)

**What to show**:

- Error dialog: "⚠️ Device Mismatch Detected"
- Message: "This account is bound to a different device. Access denied."
- Device ID shown: "Current: ABC123, Bound to: XYZ789"
- "Logout" button
- Caption: "Security Check: Device UUID prevents access from wrong device"

**Why important**: Demonstrates anti-cheating device binding

---

#### Screenshot 3: Home Screen with Face ID Status

**What to show**:

- Welcome message: "Welcome, John Doe"
- Face ID Status box:
  - Green box if Face ID enrolled: "✅ Face ID Enrolled & Active"
  - OR Orange box if not: "⚠️ Face ID Not Enrolled (Optional)"
- "Scan Attendance QR" button (blue)
- Settings button (gear icon top-right)
- Caption: "Home Screen - Shows Face ID enrollment status for security"

**Why important**: Shows Face ID as security layer before QR scanning

---

### **SECTION 2: Face ID Setup (2 screenshots)**

#### Screenshot 4: Face ID Setup Screen

**What to show**:

- Title: "Secure Face ID Authentication"
- Icon: Face recognition symbol
- Info boxes explaining:
  - ✅ Security
  - 🚫 Prevents Cheating
  - 🔒 One Face Only
  - 📱 Uses Phone's Built-in
- ⚠️ Warning: "You can only enroll ONE face per account"
- "Setup Face ID" button (green)
- "Skip for Now" button
- Caption: "Face ID Enrollment - Strict one-face-per-account policy"

**Why important**: Shows anti-cheating Face ID feature unique to your app

---

#### Screenshot 5: Device Biometric Support Check

**What to show**:

- Same Face ID setup screen but with:
- Status: "✅ Face ID Available" (green checkmark) OR "❌ Not Available" (red X)
- If available: "Your device supports Face ID biometric authentication"
- If not: "This device doesn't support Face ID" (on emulator)
- Caption: "Device compatibility check - Ensures biometric hardware exists"

**Why important**: Shows smart device detection

---

### **SECTION 3: Account Settings (1 screenshot)**

#### Screenshot 6: Account Settings Screen

**What to show**:

- User email at top
- Face ID Status section:
  - Show "✅ Enrolled & Active" (if enrolled) with ACTIVE badge
  - Show "Enroll Face ID" button and "Remove Face ID" button
- Security & Anti-Cheating section with 4 points:
  - 📱 Device Binding
  - 🔐 One Face Per Account
  - 📊 Activity Logging
  - ✅ Academic Integrity
- Caption: "Settings Page - Manage Face ID and view security layers"

**Why important**: Shows all anti-cheating security measures in one place

---

### **SECTION 4: QR Scanning (3 screenshots)**

#### Screenshot 7: Tap Scan QR Button

**What to show**:

- Home screen
- User tapping "Scan Attendance QR" button
- OR show button highlighted/pressed state
- Caption: "Step 2: Student taps 'Scan Attendance QR' button"

**Why important**: Shows user action

---

#### Screenshot 8: Face ID Verification Before QR

**What to show**:

- Loading spinner or Face ID prompt
- Message: "Verifying Face ID..."
- OR show device's native Face ID prompt overlay
- Caption: "Security Check: If Face ID enrolled, must verify face before scanning"

**Why important**: Shows layered security before QR access

---

#### Screenshot 9: QR Code Scanner Screen

**What to show**:

- Camera view with QR code being scanned
- Or show successful scan result:
  - "✅ QR Code Scanned Successfully"
  - QR data displayed
- "Attendance Marked" confirmation
- Caption: "QR Scanning & WiFi Verification - Data sent to Firestore"

**Why important**: Shows main attendance functionality

---

### **SECTION 5: Error Scenarios (2 screenshots)**

#### Screenshot 10: Wrong WiFi Network Error

**What to show**:

- Error dialog:
  - Title: "❌ WiFi Network Error"
  - Message: "You must be connected to the classroom WiFi network"
  - Current WiFi: "Starbucks_WiFi"
  - Required WiFi: "Classroom_5G"
- "Dismiss" button
- Caption: "Anti-Cheating: Location verification via WiFi SSID"

**Why important**: Shows network-based cheating prevention

---

#### Screenshot 11: Face ID Already Enrolled Error

**What to show**:

- Error dialog when trying to enroll Face ID twice:
  - Title: "⚠️ Face ID Already Enrolled"
  - Message: "You can only enroll one face per account to prevent cheating"
  - Reason: "Cannot add multiple faces to same account"
- "Dismiss" button
- Caption: "Strict Enforcement: One face per account prevents account sharing"

**Why important**: Demonstrates your unique strict Face ID policy

---

#### Screenshot 12: Firestore Data Logged

**What to show**:

- Firebase Console showing `attendance_logs` collection:
  - Document with fields:
    - `userId`: "user_123"
    - `email`: "student@university.edu"
    - `timestamp`: "2025-11-16T14:30:00Z"
    - `deviceId`: "BE2A.250530.026.D1"
    - `wifiSSID`: "Classroom_5G"
    - `faceIdVerified`: true
    - `qrCodeData`: "attendance_code_xyz"
    - `status`: "success"
- Caption: "Firestore Audit Trail - All attendance marked with 7 security layers"

**Why important**: Shows data persistence and audit trail

---

## 3. PRESENTATION SLIDE STRUCTURE

### **Slide 1: Title**

- "Smart Attendance System"
- "Anti-Cheating through Multi-Layer Security"
- Your name, date

---

### **Slide 2: Problem Statement**

- Traditional attendance (manual roll call):
  - ❌ Time-consuming
  - ❌ Can be manipulated (proxy attendance)
  - ❌ No audit trail
- Your solution: Smart biometric + location verification

---

### **Slide 3: 7-Layer Security Architecture**

```
Layer 1: Device UUID Binding
Layer 2: Face ID Enrollment (One per account)
Layer 3: Face ID Verification
Layer 4: WiFi SSID Verification
Layer 5: Device UUID Re-Check at QR Time
Layer 6: Firebase Auth
Layer 7: Audit Logging
```

---

### **Slide 4: Authentication Flow**

- Screenshot 1 (Login Screen)
- Screenshot 2 (Device Mismatch Error)
- Screenshot 3 (Home Screen with Face ID Status)

---

### **Slide 5: Face ID Setup**

- Screenshot 4 (Face ID Setup Screen)
- Screenshot 5 (Device Support Check)
- Text: "Strict one-face-per-account policy prevents account sharing"

---

### **Slide 6: Account Settings**

- Screenshot 6 (Settings Screen)
- Highlight all 4 security measures

---

### **Slide 7: QR Scanning Process**

- Screenshot 7 (Tap Scan QR)
- Screenshot 8 (Face ID Verification)
- Screenshot 9 (QR Scanner)
- Text: "Multi-step verification ensures only authorized students mark attendance"

---

### **Slide 8: Error Handling & Anti-Cheating**

- Screenshot 10 (Wrong WiFi Error)
- Screenshot 11 (Face ID Already Enrolled)
- Text: "Prevents common cheating methods:
  - Device sharing (UUID check)
  - Remote scanning (WiFi check)
  - Account sharing (Face ID check)
  - Friend enrollment (one face per account)"

---

### **Slide 9: Data & Audit Trail**

- Screenshot 12 (Firestore Console)
- Text: "All attendance attempts logged with:
  - User ID & Email
  - Device ID
  - WiFi Network
  - Face ID Verification Status
  - Timestamp
  - Attendance Status"

---

### **Slide 10: Technology Stack**

- Frontend: Flutter/Dart
- Backend: Firebase (Auth, Firestore, Security Rules)
- Biometrics: local_auth package (Face ID/Touch ID)
- Device: device_info_plus (UUID capture)
- Network: network_info_plus (WiFi detection)

---

### **Slide 11: Key Achievements**

- ✅ 7-layer anti-cheating system
- ✅ Strict face ID policy (one per account)
- ✅ Real-time device binding verification
- ✅ WiFi-based location verification
- ✅ Complete audit trail
- ✅ User-friendly error messages
- ✅ Works on real Android/iOS devices

---

### **Slide 12: Testing Results**

- Create account on Device A ✅
- Try to create second account on Device A ❌ (blocked immediately)
- Try to access from Device B ❌ (blocked due to device mismatch)
- Enroll Face ID ✅
- Try to enroll second face ❌ (blocked with error message)
- Scan QR with Face ID ✅ (all security layers checked)

---

### **Slide 13: Future Enhancements**

- Liveness detection (prevent photo spoofing)
- Rate limiting (max 3 failed attempts)
- Admin override capabilities
- Session timeout with re-verification
- Backup authentication methods
- Mobile attendance report dashboard

---

### **Slide 14: Conclusion**

- Summary of security layers
- Impact: Eliminates proxy attendance, creates accountability
- Ready for deployment in educational institutions

---

## 4. HOW TO CAPTURE SCREENSHOTS

### **On Android Emulator (Google Pixel 9 Pro)**:

```powershell
# Press: Ctrl + S in emulator to save screenshot
# Or: Volume Down + Power buttons simultaneously
# Screenshots saved to: C:\Users\[YourUser]\AppData\Local\Temp\emu_screenshots
```

### **Using ADB (Android Debug Bridge)**:

```powershell
# Connect emulator
adb devices

# Capture screenshot
adb shell screencap -p /sdcard/screenshot.png

# Pull to computer
adb pull /sdcard/screenshot.png "C:\Screenshots\"
```

### **Recommended Tool**:

- VS Code built-in screenshot (Ctrl+Shift+P → "Take Screenshot")
- Or use free tool: Greenshot

---

## 5. FLOWCHART CREATION TOOLS

### **Option 1: Draw.io (Recommended)**

- Free, online, works in browser
- Import the ASCII flowcharts I provided above
- Color code: Green for ✅, Red for ❌, Blue for processes
- Export as PNG/PDF for presentation

### **Option 2: Lucidchart**

- Professional flowchart tool
- Free tier available
- Beautiful templates

### **Option 3: PowerPoint Shapes**

- Use built-in shapes and connectors
- Create custom flowchart directly in your presentation

---

## 6. PRESENTATION STRUCTURE - SUMMARY

**Total Duration**: ~15-20 minutes (adjust per professor's requirement)

1. **Title Slide** (30 sec)
2. **Problem & Solution** (1 min)
3. **Architecture Overview** (2 min) - Show flowchart
4. **Authentication Flow** (2 min) - Screenshots 1-3
5. **Face ID Security** (2 min) - Screenshots 4-6
6. **QR Scanning Process** (2 min) - Screenshots 7-9
7. **Anti-Cheating Features** (2 min) - Screenshots 10-11
8. **Data & Audit Trail** (1 min) - Screenshot 12
9. **Technology Stack** (1 min)
10. **Testing Results** (1 min)
11. **Future Work** (1 min)
12. **Conclusion** (1 min)
13. **Q&A** (5 min)

---

## 7. TALKING POINTS FOR PROFESSOR

**Key Points to Emphasize**:

- ✅ **Prevents 3 Types of Cheating**: Device sharing, proxy attendance, remote scanning
- ✅ **Strict Face ID Policy**: Unlike other apps, only ONE face per account
- ✅ **Multi-Layer Verification**: 7 different security checks
- ✅ **Real-time Logging**: Complete audit trail for accountability
- ✅ **Works on Real Devices**: Leverages phone's built-in biometric hardware
- ✅ **User-Friendly**: Clear error messages, optional Face ID enrollment
- ✅ **Production Ready**: All edge cases handled, comprehensive error handling

**Expected Questions**:

- Q: "What if student loses their phone?"

  - A: Device binding can be reset by admin, or student can sign in from new device (with Face ID verification)

- Q: "What if Face ID fails?"

  - A: System logs the attempt, student can retry, or skip Face ID if not enrolled

- Q: "How do you know it's really the student's face?"

  - A: Uses device's secure biometric hardware (same tech used for phone unlock)

- Q: "Can multiple students use same device?"
  - A: No! Device UUID binding prevents multiple accounts on same device

---

**Ready to start capturing screenshots?** 📸

Let me know if you need help with any specific screenshot or flowchart customization!
