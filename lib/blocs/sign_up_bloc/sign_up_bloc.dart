import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:user_repository/user_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

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
        print('\n🚀 === SIGNUP PROCESS STARTED ===');

        // ✅ NEW: Check if device is already bound to another account
        final deviceCheckResult = await _checkDeviceUniqueness();

        if (!deviceCheckResult['isUnique']) {
          print(
            '❌ Device already bound to account: ${deviceCheckResult['existingEmail']}',
          );
          emit(SignUpFailure(message: 'device_already_bound'));
          return;
        }

        print('✅ Device is unique - proceeding with signup');

        MyUser user = await _userRepository.signUp(event.user, event.password);
        await _userRepository.setUserData(user);

        // Save device ID to Firestore after successful signup
        await _saveDeviceBinding();

        emit(SignUpSuccess());
      } on FirebaseAuthException catch (e) {
        print('❌ Firebase Auth Error: ${e.code}');
        emit(SignUpFailure(message: e.code));
      } catch (e) {
        print('❌ SignUp Error: $e');
        emit(SignUpFailure());
      }
    });
  }

  // Helper method to get device ID
  Future<String> _getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        print('🔍 [Bloc] Android Device ID: ${info.id}');
        return info.id;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final vendorId = info.identifierForVendor ?? "unknown_ios_device";
        print('🔍 [Bloc] iOS Device ID: $vendorId');
        return vendorId;
      }
      return "unknown_device_${DateTime.now().millisecondsSinceEpoch}";
    } catch (e) {
      print('❌ [Bloc] Error retrieving device info: $e');
      return "error_device_${DateTime.now().millisecondsSinceEpoch}";
    }
  }

  // Save device binding to Firestore
  Future<void> _saveDeviceBinding() async {
    try {
      print('\n🚀 === [Bloc] SAVING DEVICE BINDING ===');

      final deviceId = await _getDeviceId();
      final currentUser = FirebaseAuth.instance.currentUser;

      print('📱 [Bloc] Device ID: "$deviceId"');
      print('👤 [Bloc] Current User UID: ${currentUser?.uid}');

      if (currentUser != null && deviceId.isNotEmpty) {
        final usersRef = FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid);

        print('💾 [Bloc] Saving deviceId to Firestore...');

        await usersRef.set({
          'deviceId': deviceId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        print('✅ [Bloc] Device ID saved successfully!\n');
      } else {
        print(
          '❌ [Bloc] Cannot save device binding: user=null or deviceId empty\n',
        );
      }
    } catch (e) {
      print('❌ [Bloc] Error saving device binding: $e\n');
      // Don't rethrow - we still want signup to succeed even if device binding fails
    }
  }

  /// ✅ NEW: Check if device is already bound to another account
  Future<Map<String, dynamic>> _checkDeviceUniqueness() async {
    try {
      print('\n🔍 === CHECKING DEVICE UNIQUENESS ===');

      final currentDeviceId = await _getDeviceId();
      print('📱 Device ID to check: $currentDeviceId');

      // Query Firestore to find if any user already has this deviceId
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('deviceId', isEqualTo: currentDeviceId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        print('✅ Device is unique - no existing binding found');
        return {'isUnique': true};
      }

      // Device is already bound to another account
      final existingUserDoc = querySnapshot.docs.first;
      final existingEmail = existingUserDoc.get('email') as String?;
      final existingUid = existingUserDoc.id;

      print('❌ Device already bound to account:');
      print('   UID: $existingUid');
      print('   Email: $existingEmail');

      return {
        'isUnique': false,
        'existingEmail': existingEmail,
        'existingUid': existingUid,
      };
    } catch (e) {
      print('⚠️ Error checking device uniqueness: $e');
      // On error, allow signup to proceed (fail-safe)
      return {'isUnique': true};
    }
  }
}
