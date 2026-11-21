import 'package:flutter/material.dart';
import '../config/omni_integration_contracts.dart';

/// Constantes Globais, Paleta Neon Luxuoso e Configurações Centrais do OMNI Passageiro
class OmniConstants {
  // Informações do App
  static const String appName = 'OMNI Mobilidade Urbana';
  static const String appVersion = '1.0.0+1';
  static const String buildNumber = '100';

  // Cores da Identidade Visual: Neon Luxuoso (alinhada 1:1 ao Preview TSX)
  static const Color neonCyan = Color(0xFF00FFCC);
  static const Color neonCyanLight = Color(0xFF5CFFDD);
  static const Color neonCyanDark = Color(0xFF00BFA5);

  static const Color darkBackground = Color(0xFF07090C);
  static const Color darkSurface = Color(0xFF0E1318);
  static const Color darkCard = Color(0xFF141B22);
  static const Color mapCanvasBg = Color(0xFF0A0E13);

  static const Color darkBorder = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)
  static const Color darkBorderSubtle = Color(0x0DFFFFFF); // rgba(255,255,255,0.05)

  static const Color goldAccent = Color(0xFFFFB800);
  static const Color rubyRedAlert = Color(0xFFFF3366);
  static const Color emeraldSuccess = Color(0xFF10B981);
  static const Color amberWarning = Color(0xFFF59E0B);

  static const Color textPrimary = Color(0xFFF1F5F9); // slate-100
  static const Color textSecondary = Color(0xFFCBD5E1); // slate-300
  static const Color textMuted = Color(0xFF94A3B8); // slate-400
  static const Color textDim = Color(0xFF64748B); // slate-500

  // Backend Centralizado WordPress / PHP — Roteador Híbrido `omni_global_dynamic_router` (dinâmico via cache)
  static String get backendHost => OmniRouterConfig.backendHost;
  static String get backendBaseUrl => OmniRouterConfig.baseUrl;
  static String get backendBaseUrlHttps => OmniRouterConfig.baseUrlHttps;
  static List<String> get backendCandidateUrls => OmniRouterConfig.candidateUrls;
  static const bool allowSelfSignedLocalCert = OmniRouterConfig.allowSelfSignedLocalCert;
  static const String universalAjaxAction = OmniRouterConfig.actionGlobalRouter;
  static const String backendCoreFile =
      'wp-content/plugins/omni-multidropshipping-core/includes/integrations/${OmniRouterConfig.backendFile}';

  // Configuração Oficial Firebase RTDB (centralizada em OmniRtdbConfig)
  static const String firebaseApiKey = OmniRtdbConfig.apiKey;
  static const String firebaseDatabaseUrl = OmniRtdbConfig.databaseUrl;

  // Endpoints Firebase RTDB — 100% alinhados ao contrato oficial da outra ponta (App Motorista)
  static const String rtdbDriversOnline = OmniRtdbPaths.driversOnlineRoot;
  static const String rtdbDispatchQueue = OmniRtdbPaths.dispatchQueueRoot;
  static const String rtdbTrips = OmniRtdbPaths.tripsRoot;
  static const String rtdbPrivateOffers = OmniRtdbPaths.privateOffersRoot;
  static const String rtdbPrivateBids = OmniRtdbPaths.privateBidsRoot;

  // Tempos e Timeouts
  static const int httpTimeoutSeconds = 25;
  static const int otpCodeLength = 4;
  static const int driverLocationUpdateIntervalMs = 3500;

  // Payload Pix Padrão (BR Code EMV)
  static const String defaultPixCopiaECola =
      '00020126580014br.gov.bcb.pix0136omni-mobilidade-urbana-pix-gateway520400005303986540528.505802BR5925OMNI MOBILIDADE URBANA LT6009SAO PAULO62070503***6304C7A1';
}
