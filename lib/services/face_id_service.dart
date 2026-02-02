import 'dart:io';

import 'package:local_auth/local_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service for managing Face ID authentication
/// Ensures only ONE face ID per account to prevent cheating
class FaceIdService {
  static final FaceIdService _instance = FaceIdService._internal();

  factory FaceIdService() {
    return _instance;
  }

  FaceIdService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Check if device supports biometric authentication
  Future<bool> isBiometricAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } catch (e) {
      print('❌ [FaceIdService] Error checking biometric availability: $e');
      return false;
    }
  }

  /// Get available biometric types on device
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      print('❌ [FaceIdService] Error getting available biometrics: $e');
      return [];
    }
  }

  /// Check if a biometric (Face or Fingerprint) is available.
  /// Prefer face when available on device; otherwise fingerprint or other biometric.
  Future<bool> isPreferredBiometricAvailable() async {
    try {
      final biometrics = await getAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (e) {
      print('❌ [FaceIdService] Error checking biometric availability: $e');
      return false;
    }
  }

  /// Compatibility wrapper for older callers expecting `isFaceIdAvailable()`.
  /// Returns true if any biometric is available (face or fingerprint).
  Future<bool> isFaceIdAvailable() async {
    return await isPreferredBiometricAvailable();
  }

  /// Returns the preferred biometric type as a string: 'face' or 'fingerprint' or ''
  Future<String> _getPreferredBiometricType() async {
    try {
      final biometrics = await getAvailableBiometrics();
      if (biometrics.contains(BiometricType.face)) return 'face';
      if (biometrics.contains(BiometricType.fingerprint)) return 'fingerprint';
      if (biometrics.isNotEmpty) return biometrics.first.toString();
      return '';
    } catch (e) {
      print('❌ [FaceIdService] Error getting preferred biometric: $e');
      return '';
    }
  }

  /// Check if user already has Face ID enrolled in app
  Future<bool> hasFaceIdEnrolled() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) return false;

      final faceIdEnrolled = userDoc.get('faceIdEnrolled') as bool? ?? false;
      print('[FaceIdService] ✅ Face ID enrolled status: $faceIdEnrolled');

      return faceIdEnrolled;
    } catch (e) {
      print('❌ [FaceIdService] Error checking Face ID enrollment: $e');
      return false;
    }
  }

  /// Setup Face ID for current user (First time enrollment)
  /// ✅ STRICT: Only allows ONE face ID per account
  Future<Map<String, dynamic>> setupFaceId() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'No user logged in'};
      }

      print('\n🔐 === FACE ID SETUP STARTED ===');
      print('👤 User: ${user.email}');

      // ✅ CRITICAL: Check if Face ID already enrolled
      final alreadyEnrolled = await hasFaceIdEnrolled();
      if (alreadyEnrolled) {
        print('❌ Face ID already enrolled for this account');
        return {
          'success': false,
          'error': 'Face ID already enrolled',
          'reason':
              'You can only enroll one face per account to prevent cheating',
        };
      }

      print('✅ No existing Face ID found - proceeding with enrollment');

      // Check if any biometric is available (Face or Fingerprint)
      final isBiometricAvailable = await isPreferredBiometricAvailable();
      if (!isBiometricAvailable) {
        print('❌ No biometric available on this device');
        return {
          'success': false,
          'error': 'Biometric not available',
          'reason': 'Your device does not support biometric authentication',
        };
      }

      final biometricType = await _getPreferredBiometricType();
      print('✅ Biometric available on device: $biometricType');

      // Authenticate with Face ID to confirm it works
      print('🔄 Requesting Face ID authentication...');
      final authenticated = await _localAuth.authenticate(
        localizedReason:
            'Scan your face to enroll for attendance authentication',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!authenticated) {
        print('❌ Face ID authentication failed or cancelled');
        return {
          'success': false,
          'error': 'Face ID authentication failed',
          'reason': 'Could not verify your face. Please try again.',
        };
      }

      print('✅ Face ID authentication successful!');

      // Get current device id to bind enrollment to this device
      final deviceId = await _getDeviceId();

      final enrollmentData = {
        'faceIdEnrolled': true,
        'faceIdEnrolledAt': FieldValue.serverTimestamp(),
        'faceIdDeviceId': deviceId,
        'biometricType': biometricType,
        'enrollmentAttempts': FieldValue.increment(1),
      };

      // Save to Firestore (merge to avoid failing if doc missing)
      print('💾 Saving Face ID enrollment to Firestore...');
      await _firestore
          .collection('users')
          .doc(user.uid)
          .set(enrollmentData, SetOptions(merge: true));

      print('✅ Face ID enrollment successful!\n');

      return {'success': true, 'message': 'Face ID enrolled successfully'};
    } on Exception catch (e) {
      print('❌ [FaceIdService] Exception during Face ID setup: $e');
      return {
        'success': false,
        'error': 'Setup failed',
        'reason': e.toString(),
      };
    }
  }

  /// Verify Face ID for attendance QR scan
  /// ✅ STRICT: Must match enrolled face ID
  Future<Map<String, dynamic>> verifyFaceId() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'No user logged in'};
      }

      print('\n🔐 === FACE ID VERIFICATION ===');
      print('👤 User: ${user.email}');

      // Check if Face ID (or biometric) is enrolled
      final enrolled = await hasFaceIdEnrolled();
      if (!enrolled) {
        print('❌ Face ID not enrolled for this account');
        return {
          'success': false,
          'error': 'Face ID not enrolled',
          'reason': 'Please enroll Face ID first in account settings',
        };
      }

      print('✅ Face ID is enrolled');

      // Check if any preferred biometric is available
      final available = await isPreferredBiometricAvailable();
      if (!available) {
        print('❌ Biometric not available on device');
        return {
          'success': false,
          'error': 'Biometric unavailable',
          'reason': 'Biometric authentication is not available on this device',
        };
      }

      print('🔄 Requesting biometric scan...');

      // Authenticate with Face ID
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Scan your face to verify attendance',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!authenticated) {
        print('❌ Biometric verification failed');

        // Log failed attempt
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

      print('✅ Biometric verification successful!');

      // Verify this biometric verification comes from the enrolled device
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final storedDeviceId =
            (userDoc.data()?['faceIdDeviceId'] ?? userDoc.data()?['deviceId'])
                as String?;
        final currentDeviceId = await _getDeviceId();
        if (storedDeviceId != null && storedDeviceId != currentDeviceId) {
          print(
            '❌ Biometric verified but device mismatch: stored=$storedDeviceId, current=$currentDeviceId',
          );
          await _logFaceIdAttempt(
            user.uid,
            'failed',
            'Biometric verified on device that did not enroll Face ID',
          );

          return {
            'success': false,
            'error': 'Device mismatch',
            'reason':
                'Biometric verified on a different device than the one used to enroll',
          };
        }
      }

      // Log successful verification
      await _logFaceIdAttempt(
        user.uid,
        'success',
        'Biometric verification successful',
      );

      return {'success': true, 'message': 'Biometric verified successfully'};
    } on Exception catch (e) {
      print('❌ [FaceIdService] Exception during Face ID verification: $e');

      final user = _auth.currentUser;
      if (user != null) {
        await _logFaceIdAttempt(
          user.uid,
          'error',
          'Face ID verification error: $e',
        );
      }

      return {
        'success': false,
        'error': 'Verification failed',
        'reason': e.toString(),
      };
    }
  }

  /// Remove Face ID enrollment (for account settings)
  /// ✅ User can disable Face ID but must verify with Face ID first
  Future<Map<String, dynamic>> removeFaceId() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'No user logged in'};
      }

      print('\n🔐 === REMOVING FACE ID ENROLLMENT ===');
      print('👤 User: ${user.email}');

      // First verify with Face ID before removing
      final verified = await verifyFaceId();
      if (!verified['success']) {
        print('❌ Face ID verification failed - cannot remove enrollment');
        return verified;
      }

      // Remove Face ID enrollment
      print('🗑️ Removing Face ID enrollment...');
      await _firestore.collection('users').doc(user.uid).update({
        'faceIdEnrolled': false,
        'faceIdRemovedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Face ID enrollment removed successfully!\n');

      return {'success': true, 'message': 'Face ID enrollment removed'};
    } on Exception catch (e) {
      print('❌ [FaceIdService] Exception during Face ID removal: $e');
      return {
        'success': false,
        'error': 'Removal failed',
        'reason': e.toString(),
      };
    }
  }

  /// Get Face ID enrollment details for user
  Future<Map<String, dynamic>> getFaceIdDetails() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {};

      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) return {};

      return {
        'faceIdEnrolled': userDoc.get('faceIdEnrolled') ?? false,
        'enrolledAt': userDoc.get('faceIdEnrolledAt'),
        'removedAt': userDoc.get('faceIdRemovedAt'),
      };
    } catch (e) {
      print('❌ [FaceIdService] Error getting Face ID details: $e');
      return {};
    }
  }

  /// ✅ STRICT: Log all Face ID attempts for audit trail
  Future<void> _logFaceIdAttempt(
    String userId,
    String status,
    String details,
  ) async {
    try {
      await _firestore.collection('face_id_logs').add({
        'userId': userId,
        'email': _auth.currentUser?.email,
        'status': status, // 'success', 'failed', 'error'
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });

      print('✅ Face ID attempt logged');
    } catch (e) {
      print('⚠️ Error logging Face ID attempt: $e');
      // Don't fail the main operation if logging fails
    }
  }

  /// Generate unique token for Face ID enrollment
  /// This helps track if face ID was added from multiple devices

  /// Get current device ID (android id or ios identifierForVendor)
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
      print('⚠️ [FaceIdService] Error getting device ID: $e');
    }
    return 'unknown_device';
  }
}
