import 'dart:async';
import 'dart:io';
import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:user_repository/user_repository.dart';
part 'authentication_event.dart';
part 'authentication_state.dart';

class AuthenticationBloc
    extends Bloc<AuthenticationEvent, AuthenticationState> {
  final UserRepository userRepository;
  late final StreamSubscription<User?> _userSubscription;

  AuthenticationBloc({required this.userRepository})
    : super(const AuthenticationState.unknown()) {
    _userSubscription = userRepository.user.listen((user) {
      add(AuthenticationUserChanged(user));
    });
    on<AuthenticationUserChanged>((event, emit) async {
      if (event.user != null) {
        // ✅ VERIFY DEVICE BINDING BEFORE ALLOWING AUTHENTICATED STATE
        final isDeviceValid = await _verifyDeviceBinding(event.user!);

        if (!isDeviceValid) {
          print(
            '[AuthenticationBloc] Device verification failed - forcing sign out',
          );
          await FirebaseAuth.instance.signOut();
          emit(const AuthenticationState.unauthenticated());
          return;
        }

        emit(AuthenticationState.authenticated(event.user!));
      } else {
        emit(const AuthenticationState.unauthenticated());
      }
    });
  }

  /// Verify that the current device ID matches the stored device ID
  Future<bool> _verifyDeviceBinding(User user) async {
    try {
      print(
        '[AuthenticationBloc] Verifying device binding for user: ${user.email}',
      );

      // Get current device ID
      final currentDeviceId = await _getDeviceId();
      print('[AuthenticationBloc] Current device ID: $currentDeviceId');

      // Get stored device ID from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        print('[AuthenticationBloc] User document not found');
        return false;
      }

      final storedDeviceId = userDoc.get('deviceId') as String?;
      print('[AuthenticationBloc] Stored device ID: $storedDeviceId');

      if (storedDeviceId == null) {
        print('[AuthenticationBloc] No stored device ID found');
        return false;
      }

      // Compare device IDs
      if (currentDeviceId != storedDeviceId) {
        print(
          '[AuthenticationBloc] ❌ DEVICE MISMATCH: Current=$currentDeviceId, Stored=$storedDeviceId',
        );

        // Log suspicious activity
        await FirebaseFirestore.instance
            .collection('suspicious_activity_logs')
            .add({
              'userId': user.uid,
              'email': user.email,
              'activityType': 'device_mismatch_auth_state',
              'storedDeviceId': storedDeviceId,
              'attemptedDeviceId': currentDeviceId,
              'timestamp': FieldValue.serverTimestamp(),
            });

        return false;
      }

      print('[AuthenticationBloc] ✅ Device verification passed');
      return true;
    } catch (e) {
      print('[AuthenticationBloc] Error verifying device binding: $e');
      return false;
    }
  }

  /// Get current device ID
  Future<String> _getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'unknown';
      }

      return 'unknown';
    } catch (e) {
      print('[AuthenticationBloc] Error getting device ID: $e');
      return 'error_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  @override
  Future<void> close() {
    _userSubscription.cancel();
    return super.close();
  }
}
