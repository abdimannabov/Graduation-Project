import 'package:flutter/foundation.dart';

class SecurityConfig {
  const SecurityConfig._();

  static const String _mode = String.fromEnvironment('SECURITY_MODE');

  static bool get isStrict {
    final mode = _mode.trim().toLowerCase();
    if (mode == 'strict' || mode == 'release' || mode == 'production') {
      return true;
    }
    if (mode == 'debug' || mode == 'test' || mode == 'relaxed') {
      return false;
    }

    return kReleaseMode;
  }

  static bool get isDebugTesting => !isStrict;

  static bool get bypassBiometricVerification => isDebugTesting;

  static bool get allowUnboundOrLegacyDevices => isDebugTesting;

  static bool get allowScanWithoutBiometricEnrollment => isDebugTesting;
}
