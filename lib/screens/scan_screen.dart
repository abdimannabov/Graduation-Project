import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:developer';
import 'dart:io';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? controller;
  bool isScanned = false;

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
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
      final attendanceRef = FirebaseFirestore.instance
          .collection('attendance')
          .doc(user.uid)
          .collection('records');

      await attendanceRef.add({
        'qr_value': code,
        'timestamp': DateTime.now(),
        'email': user.email,
        'ip_verified': true,
        'ip_address': currentIp,
        'status': 'Present',
        'device_verified': true,
      });

      // Also log to attendance_logs for admin audit
      await FirebaseFirestore.instance.collection('attendance_logs').add({
        'userId': user.uid,
        'email': user.email,
        'qr_code': code,
        'timestamp': DateTime.now(),
        'ip_address': currentIp,
        'device_verified': true,
        'location_verified': true,
        'status': 'Present',
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
            child: QRView(key: qrKey, onQRViewCreated: _onQRViewCreated),
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
