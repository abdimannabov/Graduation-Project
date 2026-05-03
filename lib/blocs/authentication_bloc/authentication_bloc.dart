import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:user_repository/user_repository.dart';

import '../../config/security_config.dart';

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
      final user = event.user;
      if (user == null) {
        emit(const AuthenticationState.unauthenticated());
        return;
      }

      if (SecurityConfig.allowUnboundOrLegacyDevices) {
        emit(AuthenticationState.authenticated(user));
        return;
      }

      final isDeviceValid = await _verifyDeviceBinding(user);
      if (!isDeviceValid) {
        print('[AuthenticationBloc] Device verification failed - signing out');
        await FirebaseAuth.instance.signOut();
        emit(const AuthenticationState.unauthenticated());
        return;
      }

      emit(AuthenticationState.authenticated(user));
    });
  }

  Future<bool> _verifyDeviceBinding(User user) async {
    try {
      final currentDeviceId = await _getDeviceId();
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        final creationTime = user.metadata.creationTime;
        final isFreshSignup =
            creationTime != null &&
            DateTime.now().difference(creationTime).inMinutes < 2;
        return isFreshSignup;
      }

      final storedDeviceId = userDoc.data()?['deviceId'] as String?;
      if (storedDeviceId == null) return false;

      if (currentDeviceId != storedDeviceId) {
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

      return true;
    } catch (e) {
      print('[AuthenticationBloc] Error verifying device binding: $e');
      return false;
    }
  }

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
