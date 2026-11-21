import 'dart:io';
import '../constants/omni_constants.dart';

/// Permite certificados HTTPS autoassinados para o host configurado dinamicamente
/// ou hosts da rede local LAN (ex: 192.168.x.x, 10.x.x.x, localhost) em desenvolvimento.
class _OmniLocalHttpOverrides extends HttpOverrides {
  static const Set<String> _hostsLocaisBase = {
    'localhost',
    '10.0.2.2',
    '127.0.0.1',
  };

  bool _isHostLocalOuConfigurado(String host) {
    final h = host.trim().toLowerCase();
    if (h == OmniConstants.backendHost.toLowerCase()) return true;
    if (_hostsLocaisBase.contains(h) || h.endsWith('.local')) return true;
    if (h.startsWith('192.168.') || h.startsWith('10.')) return true;
    if (RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(h)) return true;
    return false;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    if (OmniConstants.allowSelfSignedLocalCert) {
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        return _isHostLocalOuConfigurado(host);
      };
    }
    return client;
  }
}

void configurarHttpLocalOverrides() {
  HttpOverrides.global = _OmniLocalHttpOverrides();
}
