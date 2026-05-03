import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:user_repository/user_repository.dart';

import '../../config/security_config.dart';

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

        if (!SecurityConfig.allowUnboundOrLegacyDevices) {
          final isDeviceValid = await _verifyDeviceBinding();
          if (!isDeviceValid) {
            await FirebaseAuth.instance.signOut();
            emit(SignInFailure(message: 'device_mismatch'));
            return;
          }
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

  Future<String> _getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return info.id;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        return info.identifierForVendor ?? 'unknown_ios_device';
      }
      return 'unknown_device';
    } catch (e) {
      print('[SignInBloc] Error getting device ID: $e');
      return 'error_device';
    }
  }

  Future<bool> _verifyDeviceBinding() async {
    try {
      final currentDeviceId = await _getDeviceId();
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) return false;

      final storedDeviceId = userDoc.data()?['deviceId'] as String?;
      if (storedDeviceId == null) return false;

      if (currentDeviceId != storedDeviceId) {
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

      return true;
    } catch (e) {
      print('[SignInBloc] Error during device verification: $e');
      return false;
    }
  }
}
