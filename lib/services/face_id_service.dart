import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:local_auth/local_auth.dart';

import '../config/security_config.dart';

class FaceIdService {
  static final FaceIdService _instance = FaceIdService._internal();

  factory FaceIdService() {
    return _instance;
  }

  FaceIdService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<bool> isBiometricAvailable() async {
    if (SecurityConfig.bypassBiometricVerification) return true;

    try {
      return await _localAuth.canCheckBiometrics;
    } catch (e) {
      print('[FaceIdService] Error checking biometric availability: $e');
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      print('[FaceIdService] Error getting available biometrics: $e');
      return [];
    }
  }

  Future<bool> isPreferredBiometricAvailable() async {
    if (SecurityConfig.bypassBiometricVerification) return true;

    try {
      final biometrics = await getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (e) {
      print('[FaceIdService] Error checking biometric availability: $e');
      return false;
    }
  }

  Future<bool> isFaceIdAvailable() async {
    return await isPreferredBiometricAvailable();
  }

  Future<String> _getPreferredBiometricType() async {
    if (SecurityConfig.bypassBiometricVerification) return 'debug_bypass';

    try {
      final biometrics = await getAvailableBiometrics();
      if (biometrics.contains(BiometricType.face)) return 'face';
      if (biometrics.contains(BiometricType.fingerprint)) return 'fingerprint';
      if (biometrics.isNotEmpty) return biometrics.first.toString();
      return '';
    } catch (e) {
      print('[FaceIdService] Error getting preferred biometric: $e');
      return '';
    }
  }

  Future<bool> hasFaceIdEnrolled() async {
    if (SecurityConfig.allowScanWithoutBiometricEnrollment) return true;

    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return false;

      final faceIdEnrolled =
          userDoc.data()?['faceIdEnrolled'] as bool? ?? false;
      print('[FaceIdService] Face ID enrolled status: $faceIdEnrolled');

      return faceIdEnrolled;
    } catch (e) {
      print('[FaceIdService] Error checking Face ID enrollment: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> setupFaceId() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'No user logged in'};
      }

      final alreadyEnrolled = await _readFaceIdEnrollmentFlag(user.uid);
      if (alreadyEnrolled) {
        return {
          'success': false,
          'error': 'Face ID already enrolled',
          'reason':
              'You can only enroll one biometric profile per account to prevent cheating',
        };
      }

      if (SecurityConfig.bypassBiometricVerification) {
        return await _saveDebugBiometricEnrollment(user);
      }

      final isBiometricAvailable = await isPreferredBiometricAvailable();
      if (!isBiometricAvailable) {
        return {
          'success': false,
          'error': 'Biometric not available',
          'reason': 'Your device does not support biometric authentication',
        };
      }

      final biometricType = await _getPreferredBiometricType();
      final authenticated = await _localAuth.authenticate(
        localizedReason:
            'Scan your face or fingerprint to enroll attendance authentication',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!authenticated) {
        return {
          'success': false,
          'error': 'Biometric authentication failed',
          'reason': 'Could not verify your biometric. Please try again.',
        };
      }

      final deviceId = await _getDeviceId();
      await _firestore.collection('users').doc(user.uid).set({
        'faceIdEnrolled': true,
        'faceIdEnrolledAt': FieldValue.serverTimestamp(),
        'faceIdDeviceId': deviceId,
        'biometricType': biometricType,
        'enrollmentAttempts': FieldValue.increment(1),
      }, SetOptions(merge: true));

      return {'success': true, 'message': 'Biometric enrolled successfully'};
    } on Exception catch (e) {
      print('[FaceIdService] Exception during biometric setup: $e');
      return {
        'success': false,
        'error': 'Setup failed',
        'reason': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> verifyFaceId() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'No user logged in'};
      }

      if (SecurityConfig.bypassBiometricVerification) {
        print(
          '[FaceIdService] Debug/testing mode: biometric verification bypassed',
        );
        return {'success': true, 'message': 'Biometric verification bypassed'};
      }

      final enrolled = await _readFaceIdEnrollmentFlag(user.uid);
      if (!enrolled) {
        return {
          'success': false,
          'error': 'Biometric not enrolled',
          'reason': 'Please enroll biometric authentication first in settings',
        };
      }

      final available = await isPreferredBiometricAvailable();
      if (!available) {
        return {
          'success': false,
          'error': 'Biometric unavailable',
          'reason': 'Biometric authentication is not available on this device',
        };
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Scan your face or fingerprint to verify attendance',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!authenticated) {
        await _logFaceIdAttempt(
          user.uid,
          'failed',
          'Biometric verification failed',
        );

        return {
          'success': false,
          'error': 'Biometric verification failed',
          'reason': 'Your biometric could not be verified. Please try again.',
        };
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final storedDeviceId =
            (userDoc.data()?['faceIdDeviceId'] ?? userDoc.data()?['deviceId'])
                as String?;
        final currentDeviceId = await _getDeviceId();
        if (storedDeviceId != null && storedDeviceId != currentDeviceId) {
          await _logFaceIdAttempt(
            user.uid,
            'failed',
            'Biometric verified on device that did not enroll it',
          );

          return {
            'success': false,
            'error': 'Device mismatch',
            'reason':
                'Biometric verified on a different device than the one used to enroll',
          };
        }
      }

      await _logFaceIdAttempt(
        user.uid,
        'success',
        'Biometric verification successful',
      );

      return {'success': true, 'message': 'Biometric verified successfully'};
    } on Exception catch (e) {
      print('[FaceIdService] Exception during biometric verification: $e');

      final user = _auth.currentUser;
      if (user != null) {
        await _logFaceIdAttempt(
          user.uid,
          'error',
          'Biometric verification error: $e',
        );
      }

      return {
        'success': false,
        'error': 'Verification failed',
        'reason': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> removeFaceId() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'No user logged in'};
      }

      if (!SecurityConfig.bypassBiometricVerification) {
        final verified = await verifyFaceId();
        if (!verified['success']) {
          return verified;
        }
      }

      await _firestore.collection('users').doc(user.uid).update({
        'faceIdEnrolled': false,
        'faceIdRemovedAt': FieldValue.serverTimestamp(),
      });

      return {'success': true, 'message': 'Biometric enrollment removed'};
    } on Exception catch (e) {
      print('[FaceIdService] Exception during biometric removal: $e');
      return {
        'success': false,
        'error': 'Removal failed',
        'reason': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> getFaceIdDetails() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {};

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return {};

      return {
        'faceIdEnrolled': userDoc.data()?['faceIdEnrolled'] ?? false,
        'enrolledAt': userDoc.data()?['faceIdEnrolledAt'],
        'removedAt': userDoc.data()?['faceIdRemovedAt'],
      };
    } catch (e) {
      print('[FaceIdService] Error getting biometric details: $e');
      return {};
    }
  }

  Future<bool> _readFaceIdEnrollmentFlag(String userId) async {
    final userDoc = await _firestore.collection('users').doc(userId).get();
    if (!userDoc.exists) return false;
    return userDoc.data()?['faceIdEnrolled'] as bool? ?? false;
  }

  Future<Map<String, dynamic>> _saveDebugBiometricEnrollment(User user) async {
    final deviceId = await _getDeviceId();
    await _firestore.collection('users').doc(user.uid).set({
      'faceIdEnrolled': true,
      'faceIdEnrolledAt': FieldValue.serverTimestamp(),
      'faceIdDeviceId': deviceId,
      'biometricType': 'debug_bypass',
      'enrollmentAttempts': FieldValue.increment(1),
    }, SetOptions(merge: true));

    return {
      'success': true,
      'message': 'Biometric enrollment enabled for debug/testing mode',
    };
  }

  Future<void> _logFaceIdAttempt(
    String userId,
    String status,
    String details,
  ) async {
    try {
      await _firestore.collection('face_id_logs').add({
        'userId': userId,
        'email': _auth.currentUser?.email,
        'status': status,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('[FaceIdService] Error logging biometric attempt: $e');
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
        return info.identifierForVendor ?? 'ios_unknown';
      }
    } catch (e) {
      print('[FaceIdService] Error getting device ID: $e');
    }
    return 'unknown_device';
  }
}
