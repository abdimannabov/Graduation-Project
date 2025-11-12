import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:user_repository/user_repository.dart';
part 'sign_in_event.dart';
part 'sign_in_state.dart';

class SignInBloc extends Bloc<SignInEvent, SignInState> {
  final UserRepository _userRepository;

  SignInBloc({required UserRepository userRepository})
    : _userRepository = userRepository,
      super(SignInInitial()) {
    on<SignInRequired>((event, emit) async {
      emit(SignInProcess());
      try {
        await _userRepository.signIn(event.email, event.password);

        // ✅ NEW: Device binding verification BEFORE emitting success
        final isDeviceValid = await _verifyDeviceBinding();

        if (!isDeviceValid) {
          // Device mismatch - sign out immediately
          await FirebaseAuth.instance.signOut();
          emit(SignInFailure(message: 'device_mismatch'));
          return;
        }

        emit(SignInSuccess());
      } on FirebaseAuthException catch (e) {
        emit(SignInFailure(message: e.code));
      } catch (e) {
        emit(const SignInFailure());
      }
    });
    on<SignOutRequired>((event, emit) async {
      await _userRepository.logOut();
    });
  }

  // Get device ID
  Future<String> _getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        print('[SignInBloc] Android Device ID: ${info.id}');
        return info.id;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final vendorId = info.identifierForVendor ?? "unknown_ios_device";
        print('[SignInBloc] iOS Device ID: $vendorId');
        return vendorId;
      }
      return "unknown_device";
    } catch (e) {
      print('[SignInBloc] Error getting device ID: $e');
      return "error_device";
    }
  }

  // Verify device binding
  Future<bool> _verifyDeviceBinding() async {
    try {
      print('\n🔐 [SignInBloc] === DEVICE BINDING VERIFICATION ===');

      final currentDeviceId = await _getDeviceId();
      final currentUser = FirebaseAuth.instance.currentUser;

      print('[SignInBloc] Current Device ID: $currentDeviceId');
      print('[SignInBloc] Current User: ${currentUser?.email}');

      if (currentUser == null) {
        print('[SignInBloc] ERROR: No current user after signin!');
        return false;
      }

      // Get stored device ID from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        print('[SignInBloc] ERROR: User document not found in Firestore!');
        return false;
      }

      final storedDeviceId = userDoc.data()?['deviceId'] as String?;
      print('[SignInBloc] Stored Device ID: $storedDeviceId');

      if (storedDeviceId == null) {
        print('[SignInBloc] WARNING: No stored device ID');
        return false;
      }

      // Compare device IDs
      if (currentDeviceId != storedDeviceId) {
        print('[SignInBloc] ❌ DEVICE MISMATCH!');
        print('   Current: $currentDeviceId');
        print('   Stored:  $storedDeviceId');

        // Log suspicious activity
        await FirebaseFirestore.instance
            .collection('suspicious_activity_logs')
            .add({
              'type': 'device_mismatch_login_attempt',
              'userId': currentUser.uid,
              'email': currentUser.email,
              'storedDeviceId': storedDeviceId,
              'attemptedDeviceId': currentDeviceId,
              'timestamp': FieldValue.serverTimestamp(),
            });

        return false;
      }

      print('[SignInBloc] ✅ Device verified - LOGIN ALLOWED\n');
      return true;
    } catch (e) {
      print('[SignInBloc] ERROR during device verification: $e\n');
      return false;
    }
  }
}
