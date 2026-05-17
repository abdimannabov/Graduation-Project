import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:user_repository/user_repository.dart';

part 'sign_up_event.dart';
part 'sign_up_state.dart';

class SignUpBloc extends Bloc<SignUpEvent, SignUpState> {
  final UserRepository _userRepository;

  SignUpBloc({required UserRepository userRepository})
    : _userRepository = userRepository,
      super(SignUpInitial()) {
    on<SignUpRequired>((event, emit) async {
      emit(SignUpProcess());
      try {
        print('\n=== SIGNUP PROCESS STARTED ===');

        final deviceId = await _getDeviceId();
        final user = await _userRepository.signUp(event.user, event.password);
        await _createUserProfileWithDeviceBinding(user, deviceId);

        emit(SignUpSuccess());
      } on FirebaseAuthException catch (e) {
        print('Firebase Auth Error: ${e.code}');
        emit(SignUpFailure(message: e.code));
      } on FirebaseException catch (e) {
        print('Firebase Firestore Error: ${e.code} ${e.message}');
        await _deleteCurrentAuthUserAfterFailedSignup();
        if (e.code == 'permission-denied' || e.code == 'already-exists') {
          emit(SignUpFailure(message: 'device_already_bound'));
        } else {
          emit(SignUpFailure(message: e.code));
        }
      } catch (e) {
        print('SignUp Error: $e');
        await _deleteCurrentAuthUserAfterFailedSignup();
        emit(SignUpFailure());
      }
    });
  }

  Future<String> _getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        print('[SignUpBloc] Android Device ID: ${info.id}');
        return info.id;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final vendorId = info.identifierForVendor ?? 'unknown_ios_device';
        print('[SignUpBloc] iOS Device ID: $vendorId');
        return vendorId;
      }
      return 'unknown_device_${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      print('[SignUpBloc] Error retrieving device info: $e');
      return 'error_device_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  String _deviceBindingDocId(String deviceId) {
    return deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  Future<void> _createUserProfileWithDeviceBinding(
    MyUser user,
    String deviceId,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No authenticated user after signup.',
      );
    }

    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection('users').doc(user.userID);
    final deviceRef = firestore
        .collection('device_bindings')
        .doc(_deviceBindingDocId(deviceId));

    final batch = firestore.batch();
    batch.set(deviceRef, {
      'userId': user.userID,
      'email': user.email,
      'deviceId': deviceId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(userRef, {
      'userID': user.userID,
      'name': user.name,
      'email': user.email,
      'deviceId': deviceId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'faceIdEnrolled': false,
    });

    await batch.commit();
    print('[SignUpBloc] User profile and device binding saved.');
  }

  Future<void> _deleteCurrentAuthUserAfterFailedSignup() async {
    try {
      await FirebaseAuth.instance.currentUser?.delete();
    } catch (e) {
      print('[SignUpBloc] Could not delete auth user after failed signup: $e');
    }
  }
}
