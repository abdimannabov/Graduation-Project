/// Local testing network settings.
///
/// If your laptop IP changes, update only [laptopIp].
class LocalDevNetworkConfig {
  const LocalDevNetworkConfig._();

  static const String scheme = 'http';
  static const String laptopIp = '192.168.1.6';
  static const int backendPort = 5000;

  static String get backendBaseUrl => '$scheme://$laptopIp:$backendPort';
}
