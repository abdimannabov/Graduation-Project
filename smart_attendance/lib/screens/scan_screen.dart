import 'dart:developer';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';

import '../config/security_config.dart';
import '../services/backend_api.dart';
import '../services/face_id_service.dart';
import 'auth/face_id_setup_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  final FaceIdService _faceIdService = FaceIdService();
  final BackendApi _backendApi = BackendApi();

  QRViewController? controller;
  bool isScanned = false;
  bool _biometricEnrolled = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricSetup();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> _checkBiometricSetup() async {
    try {
      final enrolled = await _faceIdService.hasFaceIdEnrolled();
      final available = await _faceIdService.isFaceIdAvailable();
      if (!mounted) return;
      setState(() {
        _biometricEnrolled = enrolled;
        _biometricAvailable = available;
      });
    } catch (e) {
      log('Error checking biometric setup: $e');
      if (!mounted) return;
      setState(() {
        _biometricEnrolled = false;
        _biometricAvailable = false;
      });
    }
  }

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

  Future<bool> _verifyDeviceBinding(String userId) async {
    try {
      final deviceId = await _getDeviceId();
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!userDoc.exists) return SecurityConfig.allowUnboundOrLegacyDevices;

      final storedDeviceId = userDoc.data()?['deviceId'] as String?;
      if (storedDeviceId != null && storedDeviceId != deviceId) {
        log(
          'SECURITY: Device mismatch. User: $userId, stored: $storedDeviceId, current: $deviceId',
        );

        await _logSuspiciousActivity({
          'type': 'device_mismatch_attendance_attempt',
          'userId': userId,
          'storedDeviceId': storedDeviceId,
          'attemptedDeviceId': deviceId,
        });

        return false;
      }
      if (storedDeviceId == null &&
          SecurityConfig.allowUnboundOrLegacyDevices) {
        return true;
      }
      return true;
    } catch (e) {
      log('Error verifying device binding: $e');
      return SecurityConfig.allowUnboundOrLegacyDevices;
    }
  }

  Future<void> _logSuspiciousActivity(Map<String, dynamic> data) async {
    try {
      await FirebaseFirestore.instance
          .collection('suspicious_activity_logs')
          .add({...data, 'timestamp': FieldValue.serverTimestamp()});
    } catch (e) {
      log('Error writing suspicious activity log: $e');
    }
  }

  Future<void> _logSuccessfulAttendance({
    required User user,
    required String qrCode,
    required String deviceId,
    String? backendHost,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('attendance_logs').add({
        'userId': user.uid,
        'email': user.email,
        'qr_code': qrCode,
        'timestamp': FieldValue.serverTimestamp(),
        'device_verified': true,
        'location_verified': true,
        'status': 'Present',
        'deviceId': deviceId,
        if (backendHost != null && backendHost.isNotEmpty)
          'backend_host': backendHost,
      });
    } catch (e) {
      log('Attendance audit log failed after backend success: $e');
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
      _showMessage('User not logged in');
      return;
    }

    try {
      final code = rawCode.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
      log('Raw scanned: <$rawCode> | Cleaned: <$code>');

      final deviceVerified = await _verifyDeviceBinding(user.uid);
      if (!deviceVerified) {
        _showMessage('Unauthorized device');
        await FirebaseAuth.instance.signOut();
        if (mounted) Navigator.pop(context);
        return;
      }

      // Location gate: for URL QRs, only the QR host/IP is compared with the
      // configured backend host. Device IP is not used for auth or account checks.
      if (!_backendApi.qrHostMatchesBackend(code)) {
        final expectedHost = _backendApi.backendHost ?? 'unknown';
        _showMessage('Wrong classroom network for this QR code');
        log(
          'QR host mismatch. Expected backend host: $expectedHost, QR: $code',
        );
        await _logSuspiciousActivity({
          'type': 'qr_backend_host_mismatch',
          'userId': user.uid,
          'email': user.email,
          'qr_code': code,
          'expected_backend_host': expectedHost,
        });
        if (mounted) Navigator.pop(context);
        return;
      }

      final result = await _backendApi.markAttendance(
        scannedValue: code,
        userEmail: user.email ?? '',
      );

      if (!result.ok) {
        final message = result.message ?? 'Attendance rejected';
        _showMessage(message);
        log('Attendance rejected: ${result.code} $message');
        await _logSuspiciousActivity({
          'type': 'attendance_rejected_by_backend',
          'userId': user.uid,
          'email': user.email,
          'qr_code': code,
          'backend_code': result.code,
          'backend_message': message,
          'backend_status': result.statusCode,
        });
        if (mounted) Navigator.pop(context);
        return;
      }

      final deviceId = await _getDeviceId();
      await _logSuccessfulAttendance(
        user: user,
        qrCode: code,
        deviceId: deviceId,
        backendHost: _backendApi.backendHost,
      );

      _showMessage(result.message ?? 'Attendance recorded');
      log('Attendance saved through backend successfully.');
      if (mounted) Navigator.pop(context);
    } catch (e, st) {
      log('Error in _handleScan: $e\n$st');
      _showMessage('Error: ${e.toString()}');
      if (mounted) Navigator.pop(context);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
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
            child:
                (_biometricAvailable && _biometricEnrolled) ||
                    SecurityConfig.allowScanWithoutBiometricEnrollment
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
                          child: const Column(
                            children: [
                              Icon(Icons.lock, size: 48, color: Colors.red),
                              SizedBox(height: 12),
                              Text(
                                'Mandatory Face ID / Fingerprint required',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'You cannot scan attendance QR codes until biometric verification is enrolled on this device.',
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
                            final didEnroll = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const FaceIdSetupScreen(),
                              ),
                            );
                            if (didEnroll == true) {
                              await _checkBiometricSetup();
                            }
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
