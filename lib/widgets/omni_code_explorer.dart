import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/omni_constants.dart';
import '../theme/omni_theme.dart';

/// Explorador de Contrato & Arquitetura Flutter — Fidelidade 1:1 ao OmniCodeExplorer.tsx
/// Protegido contra overflow com scroll horizontal nos seletores e scroll bidirecional no bloco de código.
class OmniCodeExplorer extends StatefulWidget {
  const OmniCodeExplorer({super.key});

  @override
  State<OmniCodeExplorer> createState() => _OmniCodeExplorerState();
}

class _OmniCodeExplorerState extends State<OmniCodeExplorer> {
  String _selectedKey = 'contract';
  bool _copied = false;

  static const Map<String, Map<String, String>> _files = {
    'contract': {
      'title': 'omni_integration_contracts.dart',
      'path': 'lib/config/omni_integration_contracts.dart',
      'language': 'markdown',
      'content': '''# OMNI SHARED ECOSYSTEM CONTRACT (PASSAGEIRO <-> MOTORISTA)
Contrato Centralizado de Integração — Versão 2.0.0
Arquivos oficiais: mapeamento_sql_passageiro.md & mapeamento_realtime_firebase_passageiro.md

1. WORDPRESS DYNAMIC ROUTER (functions.php):
- Base URL: Dinâmica via cache (padrão http://192.168.12.10/servshop/wp-admin/admin-ajax.php + HTTPS)
- Nonce Action: GET ?action=omni_get_router_nonce
- Router Action: POST action=omni_global_router (nonce + payload JSON)
- backend_file: class-omni-passageiro-backend-pro.php
- class_name: class_omni_passageiro_backend_pro
- target_method (snake_case):
  * passenger_system_ping
  * passenger_trip_request / passenger_trip_cancel / passenger_trip_rate
  * passenger_trip_sos / passenger_get_driver_public_info
  * passenger_wallet_generate_pix / passenger_wallet_check_pix
  * passenger_private_offer_create / passenger_support_open_ticket

2. FIREBASE REALTIME DATABASE (PONTE MOTORISTA):
URL: https://catalogo-dropshipping-b9546-default-rtdb.firebaseio.com
- /drivers_online/{driver_id}         (lat, lng, bearing, is_online, updated_at)
- /dispatch_queue/{driver_id}/{trip_id}
- /trips/{trip_id}                    (status, driver_id, driver_location, chat, sos)
- /private_offers/{offer_id}
- /private_bids/{offer_id}/{driver_id}''',
    },
    'backend': {
      'title': 'backends_service.dart',
      'path': 'lib/tools/backends_service.dart',
      'language': 'dart',
      'content': '''import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/omni_integration_contracts.dart';
import 'local_http_overrides.dart';

class OmniBackendUniversal {
  static String get baseUrl => OmniRouterConfig.baseUrl;

  // Salva IP/domínio flexível em cache (SharedPreferences):
  // await OmniBackendUniversal.salvarDominioEmCache('192.168.12.10');
  // Fluxo real omni_global_dynamic_router:
  // 1) GET ?action=omni_get_router_nonce (com cache e renovação automática em 403)
  // 2) POST action=omni_global_router + nonce + payload JSON (backend_file, class_name, target_method, args)
  static Future<OmniBackendResponse> executar(
    String targetMethod, {
    Map<String, dynamic>? args,
    Map<String, dynamic>? payload,
    String? backendFile,
    String? className,
    bool testarTodosOsProtocolos = false,
  }) async {
    await carregarDominioDoCache();
    configurarHttpLocalOverrides();
    final effectiveArgs = args ?? payload ?? <String, dynamic>{};
    for (final url in OmniRouterConfig.candidateUrls) {
      final res = await _executarNaUrl(
        url,
        targetMethod,
        args: effectiveArgs,
        backendFile: backendFile ?? OmniRouterConfig.backendFile,
        className: className ?? OmniRouterConfig.className,
      );
      if (res.sucesso && !testarTodosOsProtocolos) return res;
    }
    return OmniBackendResponse.erro('Falha em HTTP e HTTPS', statusCode: 0);
  }
}''',
    },
    'firebase': {
      'title': 'firebase_service.dart',
      'path': 'lib/tools/firebase_service.dart',
      'language': 'dart',
      'content': '''import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../config/omni_integration_contracts.dart';

class OmniFirebaseService {
  static Stream<List<OmniMotoristaTelemetria>> escutarMotoristasProximos() {
    final ref = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: OmniRtdbConfig.databaseUrl,
    ).ref(OmniRtdbPaths.driversOnline);

    return ref.onValue.map((event) {
      // Mapeia /drivers_online/{driver_id} (lat, lng, bearing, is_online, updated_at)
      return <OmniMotoristaTelemetria>[];
    });
  }
}''',
    },
    'pubspec': {
      'title': 'pubspec.yaml',
      'path': '/pubspec.yaml',
      'language': 'yaml',
      'content': '''name: omni_passageiro
description: "Aplicativo OMNI Mobilidade Urbana — Passageiro."
version: 1.0.0+1

environment:
  sdk: ">=3.2.0 <4.0.0"
  flutter: ">=3.16.0"

dependencies:
  flutter:
    sdk: flutter
  google_maps_flutter: ^2.5.3
  geolocator: ^10.1.0
  firebase_core: ^2.27.0
  firebase_database: ^10.4.9
  http: ^1.2.0
  qr_flutter: ^4.1.0
  intl: ^0.19.0''',
    },
  };

  Future<void> _copyCode() async {
    final content = _files[_selectedKey]?['content'] ?? '';
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = _files[_selectedKey] ?? _files['contract']!;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: OmniTheme.cardDecoration(
        backgroundColor: OmniConstants.darkCard,
        borderColor: OmniConstants.darkBorder,
        borderRadius: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ARQUITETURA & CÓDIGO FONTE FLUTTER',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: OmniConstants.neonCyan,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Explorador de Arquivos Dart & Contratos',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: OmniConstants.neonCyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _copyCode,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check_circle_outline : Icons.copy_rounded,
                          size: 14,
                          color: OmniConstants.neonCyan,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _copied ? 'Copiado!' : 'Copiar Código',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: OmniConstants.neonCyan,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Seletor de Arquivos em Scroll Horizontal Fluido
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: _files.entries.map((entry) {
                final key = entry.key;
                final f = entry.value;
                final isSelected = _selectedKey == key;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _selectedKey = key),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 175,
                        padding: const EdgeInsets.all(11),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? OmniConstants.neonCyan.withValues(alpha: 0.1)
                              : OmniConstants.darkSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? OmniConstants.neonCyan : OmniConstants.darkBorderSubtle,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    f['title'] ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                      color: isSelected ? Colors.white : OmniConstants.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    f['language'] ?? '',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      color: OmniConstants.textDim,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: isSelected ? OmniConstants.neonCyan : OmniConstants.textDim,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 14),

          // Bloco de Código Monospace com Scroll Horizontal
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: OmniConstants.darkBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OmniConstants.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.only(bottom: 10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: OmniConstants.darkBorder)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          current['path'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: OmniConstants.neonCyan,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        (current['language'] ?? '').toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: OmniConstants.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: SelectableText(
                    current['content'] ?? '',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      height: 1.55,
                      color: OmniConstants.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
