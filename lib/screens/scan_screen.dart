import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:developer';
import 'dart:io';
import '../services/face_id_service.dart';
import 'package:smart_attendance/screens/auth/face_id_setup_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool isScanned = false;
  final FaceIdService _faceIdService = FaceIdService();
  bool _biometricEnrolled = false;
  bool _biometricAvailable = false;

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkBiometricSetup();
  }

  Future<void> _checkBiometricSetup() async {
    try {
      final enrolled = await _faceIdService.hasFaceIdEnrolled();
      final available = await _faceIdService.isFaceIdAvailable();
      setState(() {
        _biometricEnrolled = enrolled;
        _biometricAvailable = available;
      });
    } catch (e) {
      log('Error checking biometric setup: $e');
      setState(() {
        _biometricEnrolled = false;
        _biometricAvailable = false;
      });
    }
  }

  /// Get current device ID for anti-cheating verification
  Future<String> _getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return info.id;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return info.identifierForVendor ?? 'unknown';
      }
    } catch (e) {
      log('Error getting device ID: $e');
    }
    return 'unknown';
  }

  /// Verify attendance record doesn't already exist for this user and QR code
  Future<bool> _checkDuplicateAttendance(String userId, String qrCode) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('attendance')
          .doc(userId)
          .collection('records')
          .where('qr_value', isEqualTo: qrCode)
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: DateTime.now().subtract(Duration(hours: 1)),
          )
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        log('⚠️ Duplicate scan attempt detected for code: $qrCode');
        return true;
      }
      return false;
    } catch (e) {
      log('Error checking duplicate: $e');
      return false;
    }
  }

  /// Verify device binding to user
  Future<bool> _verifyDeviceBinding(String userId) async {
    try {
      final deviceId = await _getDeviceId();
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!userDoc.exists) return false;

      final storedDeviceId = userDoc.data()?['deviceId'] as String?;

      // If device IDs don't match, it's a cheating attempt
      if (storedDeviceId != null && storedDeviceId != deviceId) {
        log(
          '🚨 SECURITY: Device mismatch! User: $userId, Stored: $storedDeviceId, Current: $deviceId',
        );

        // Log suspicious activity
        await FirebaseFirestore.instance
            .collection('suspicious_activity_logs')
            .add({
              'type': 'device_mismatch_attendance_attempt',
              'userId': userId,
              'storedDeviceId': storedDeviceId,
              'attemptedDeviceId': deviceId,
              'timestamp': FieldValue.serverTimestamp(),
            });

        return false;
      }
      return true;
    } catch (e) {
      log('Error verifying device binding: $e');
      return false;
    }
  }

  void _onQRViewCreated(QRViewController ctrl) {
    controller = ctrl;
    ctrl.scannedDataStream.listen((scanData) async {
      if (!isScanned) {
        setState(() => isScanned = true);
        await _handleScan(scanData.code);
      }
    });
  }

  Future<void> _handleScan(String? rawCode) async {
    if (rawCode == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('User not logged in ❌');
      return;
    }

    try {
      // Clean scanned text (remove invisible chars, trim spaces)
      final code = rawCode.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
      log('🔹 Raw scanned: <$rawCode> | Cleaned: <$code>');

      // SECURITY CHECK 1: Verify device binding
      final deviceVerified = await _verifyDeviceBinding(user.uid);
      if (!deviceVerified) {
        _showMessage('Unauthorized device ❌');
        log('🚨 Device verification failed for user ${user.uid}');

        // Force logout for security
        await FirebaseAuth.instance.signOut();
        Navigator.pop(context);
        return;
      }

      // SECURITY CHECK 2: Check for duplicate attendance (prevent same QR re-scan)
      final isDuplicate = await _checkDuplicateAttendance(user.uid, code);
      if (isDuplicate) {
        _showMessage('You already scanned this QR ❌');
        log('⚠️ Duplicate scan attempt for QR: $code');

        // Log potential cheating attempt
        await FirebaseFirestore.instance
            .collection('suspicious_activity_logs')
            .add({
              'type': 'duplicate_scan_attempt',
              'userId': user.uid,
              'email': user.email,
              'qr_code': code,
              'timestamp': FieldValue.serverTimestamp(),
            });

        Navigator.pop(context);
        return;
      }

      // Get current Wi-Fi IP
      final info = NetworkInfo();
      final currentIp = (await info.getWifiIP())?.trim();
      log('📡 Device IP: $currentIp');

      // Fetch valid QR data
      final snapshot = await FirebaseFirestore.instance
          .collection('valid_qrs')
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        _showMessage('Invalid QR Code ❌');
        log('⚠️ No valid QR found for code: $code');

        // Log invalid scan attempt
        await FirebaseFirestore.instance
            .collection('suspicious_activity_logs')
            .add({
              'type': 'invalid_qr_scan_attempt',
              'userId': user.uid,
              'email': user.email,
              'attempted_code': code,
              'ip_address': currentIp,
              'timestamp': FieldValue.serverTimestamp(),
            });

        Navigator.pop(context);
        return;
      }

      final data = snapshot.docs.first.data();
      final validIp = (data['ip_address'] ?? '').toString().trim();
      log('✅ Valid IP from Firestore: $validIp');

      // SECURITY CHECK 3: IP verification (location-based authentication)
      if (currentIp != validIp) {
        _showMessage('Wrong location: not at classroom Wi-Fi ❌');
        log('❌ IP mismatch — current: $currentIp, expected: $validIp');

        // Log suspicious location attempt
        await FirebaseFirestore.instance
            .collection('suspicious_activity_logs')
            .add({
              'type': 'wrong_location_attendance_attempt',
              'userId': user.uid,
              'email': user.email,
              'qr_code': code,
              'expected_ip': validIp,
              'attempted_ip': currentIp,
              'timestamp': FieldValue.serverTimestamp(),
            });

        Navigator.pop(context);
        return;
      }

      // All security checks passed — record attendance
      final deviceId = await _getDeviceId();
      log('📱 Final device ID used for attendance: $deviceId');
      final attendanceRef = FirebaseFirestore.instance
          .collection('attendance')
          .doc(user.uid)
          .collection('records');

      await attendanceRef.add({
        'qr_value': code,
        'timestamp': FieldValue.serverTimestamp(),
        'email': user.email,
        'ip_verified': true,
        'ip_address': currentIp,
        'status': 'Present',
        'device_verified': true,
        'deviceId': deviceId,
      });

      // Also log to attendance_logs for admin audit
      await FirebaseFirestore.instance.collection('attendance_logs').add({
        'userId': user.uid,
        'email': user.email,
        'qr_code': code,
        'timestamp': FieldValue.serverTimestamp(),
        'ip_address': currentIp,
        'device_verified': true,
        'location_verified': true,
        'status': 'Present',
        'deviceId': deviceId,
      });

      _showMessage('Attendance recorded ✅');
      log('🎉 Attendance saved successfully!');
      Navigator.pop(context);
    } catch (e, st) {
      log('🔥 Error in _handleScan: $e\n$st');
      _showMessage('Error: ${e.toString()}');
      Navigator.pop(context);
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR')),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: _biometricAvailable && _biometricEnrolled
                ? QRView(key: qrKey, onQRViewCreated: _onQRViewCreated)
                : Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            children: const [
                              Icon(Icons.lock, size: 48, color: Colors.red),
                              SizedBox(height: 12),
                              Text(
                                'M A N D A T O R Y — Face ID / Fingerprint required',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'You cannot use the camera or scan QR codes until you enroll Face ID or Fingerprint on this device. This is enforced to prevent attendance fraud and is not optional.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () async {
                            // Navigate the user to enrollment screen
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FaceIdSetupScreen(),
                              ),
                            );
                            // Also try refreshing biometric state in case user enrolled elsewhere
                            await _checkBiometricSetup();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Enroll Face ID / Fingerprint'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
