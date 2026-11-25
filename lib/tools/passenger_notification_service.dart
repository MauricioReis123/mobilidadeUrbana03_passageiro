import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/omni_integration_contracts.dart';
import '../models/campanha_model.dart';
import 'backends_service.dart';
import 'firebase_service.dart';

/// Evento emitido quando uma campanha chega em primeiro plano ou é tocada (`omni://cupons/{code}`)
class OmniDeepLinkCupomEvent {
  final String cupomCodigo;
  final String? campaignId;
  final String? titulo;
  final String? mensagem;

  const OmniDeepLinkCupomEvent({
    required this.cupomCodigo,
    this.campaignId,
    this.titulo,
    this.mensagem,
  });
}

/// Handler obrigatório de background (isolate separado no Android/iOS)
@pragma('vm:entry-point')
Future<void> omniFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
}

/// Motor de Notificações Push (FCM) & Heads-Up Banner para Passageiros OMNI
/// - Reutiliza a infraestrutura Firebase já existente no app (`Firebase.app()`)
/// - Canal Android `omni_passenger_campaigns_high` registrado nativamente via `OmniNotificationChannelProvider`
///   (sem dependência de `flutter_local_notifications` nem `coreLibraryDesugaring`)
/// - Gerencia inscrição automática nos tópicos `perfil_passageiro` e `passageiro_cidade_{slug}`
/// - Despacha eventos de primeiro plano (`onForegroundBanner`) e deep link `omni://cupons/{codigo}`
class OmniPassengerNotificationService {
  static const String _prefLastCityTopic = 'omni_last_city_topic_v1';
  static const String _topicPerfilPassageiro = 'perfil_passageiro';
  static const MethodChannel _headsUpChannel = MethodChannel('com.omni.passageiro/heads_up');

  static final StreamController<OmniDeepLinkCupomEvent> _deepLinkController =
      StreamController<OmniDeepLinkCupomEvent>.broadcast();
  static final StreamController<OmniDeepLinkCupomEvent> _foregroundBannerController =
      StreamController<OmniDeepLinkCupomEvent>.broadcast();

  static bool _inicializado = false;
  static bool _nativeTapHooked = false;
  static String? _ultimoToken;
  static String? _ultimoPassengerId;
  static String _ultimaCidade = '';
  static OmniDeepLinkCupomEvent? _deepLinkPendente;
  static final Set<String> _notifiedCampaignIds = <String>{};

  static Stream<OmniDeepLinkCupomEvent> get onDeepLinkCupom =>
      _deepLinkController.stream;

  static Stream<OmniDeepLinkCupomEvent> get onForegroundBanner =>
      _foregroundBannerController.stream;

  static OmniDeepLinkCupomEvent? consumirDeepLinkPendente() {
    final ev = _deepLinkPendente;
    _deepLinkPendente = null;
    return ev;
  }

  static void _configurarCanalNativoTap() {
    if (kIsWeb || _nativeTapHooked) return;
    _nativeTapHooked = true;
    _headsUpChannel.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationTap') {
        final args = call.arguments;
        if (args is Map) {
          _emitirDeepLink(
            OmniDeepLinkCupomEvent(
              cupomCodigo: (args['codigo_cupom'] ?? '').toString().trim().toUpperCase(),
              campaignId: args['campaign_id']?.toString(),
              titulo: args['titulo']?.toString(),
              mensagem: args['mensagem']?.toString(),
            ),
          );
        }
      }
    });
  }

  /// Inicializa FirebaseMessaging (iOS + Android) com permissões, apresentação em primeiro plano e deep links
  static Future<void> inicializar({
    required String passengerId,
    String cidadeAtual = '',
  }) async {
    _ultimoPassengerId = passengerId;
    if (cidadeAtual.trim().isNotEmpty) {
      _ultimaCidade = cidadeAtual.trim();
    }

    if (kIsWeb) {
      _inicializado = true;
      return;
    }

    _configurarCanalNativoTap();

    if (!_inicializado) {
      try {
        final initialTap = await _headsUpChannel.invokeMethod<dynamic>('getInitialNotificationTap');
        if (initialTap is Map) {
          _emitirDeepLink(
            OmniDeepLinkCupomEvent(
              cupomCodigo: (initialTap['codigo_cupom'] ?? '').toString().trim().toUpperCase(),
              campaignId: initialTap['campaign_id']?.toString(),
              titulo: initialTap['titulo']?.toString(),
              mensagem: initialTap['mensagem']?.toString(),
            ),
          );
        }
      } catch (_) {}

      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp();
        }
      } catch (_) {
        // Sem google-services.json nativo neste ambiente; opera em modo RTDB + Heads-up nativo
        _inicializado = true;
        return;
      }

      try {
        final messaging = FirebaseMessaging.instance;
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        FirebaseMessaging.onBackgroundMessage(omniFirebaseMessagingBackgroundHandler);

        FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
          await _despacharBannerPrimeiroPlano(message);
        });

        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          _processarRemoteMessageTap(message);
        });

        final initialMessage = await messaging.getInitialMessage();
        if (initialMessage != null) {
          _processarRemoteMessageTap(initialMessage);
        }

        messaging.onTokenRefresh.listen((newToken) {
          _ultimoToken = newToken;
          if (_ultimoPassengerId != null && _ultimoPassengerId!.isNotEmpty) {
            unawaited(
              sincronizarTopicosPassageiro(
                passengerId: _ultimoPassengerId!,
                cidadeAtual: _ultimaCidade,
                tokenOverride: newToken,
              ),
            );
          }
        });

        _inicializado = true;
      } catch (_) {
        return;
      }
    }

    await sincronizarTopicosPassageiro(
      passengerId: passengerId,
      cidadeAtual: _ultimaCidade,
    );
  }

  static OmniDeepLinkCupomEvent _extrairEvento(RemoteMessage message) {
    final data = message.data;
    final deepLink = (data['deep_link'] ?? '').toString();
    var code = (data['codigo_cupom'] ?? '').toString().trim().toUpperCase();
    if (code.isEmpty && deepLink.startsWith('omni://cupons/')) {
      code = deepLink.replaceFirst('omni://cupons/', '').trim().toUpperCase();
    }
    return OmniDeepLinkCupomEvent(
      cupomCodigo: code,
      campaignId: data['campaign_id']?.toString(),
      titulo: (message.notification?.title ?? data['titulo'])?.toString(),
      mensagem: (message.notification?.body ?? data['mensagem'])?.toString(),
    );
  }

  /// Exibe notificação Heads-Up no topo da tela (overlay global + barra nativa Android/iOS) com deduplicação
  static Future<void> exibirNotificacaoHeadsUp({
    required String titulo,
    required String mensagem,
    String cupomCodigo = '',
    String? campaignId,
    bool force = false,
  }) async {
    final cleanTitulo = titulo.trim();
    final cleanMensagem = mensagem.trim();
    if (cleanTitulo.isEmpty && cleanMensagem.isEmpty) return;

    final cid = (campaignId ?? '').trim();
    if (!force && cid.isNotEmpty && !_notifiedCampaignIds.add(cid)) {
      return;
    }

    final event = OmniDeepLinkCupomEvent(
      cupomCodigo: cupomCodigo.trim().toUpperCase(),
      campaignId: cid.isNotEmpty ? cid : null,
      titulo: cleanTitulo.isNotEmpty ? cleanTitulo : 'Promoção OMNI',
      mensagem: cleanMensagem,
    );

    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}

    if (!_foregroundBannerController.isClosed) {
      _foregroundBannerController.add(event);
    }

    if (!kIsWeb) {
      try {
        await _headsUpChannel.invokeMethod('showHeadsUp', {
          'titulo': event.titulo ?? 'OMNI Passageiro',
          'mensagem': event.mensagem ?? '',
          'codigo_cupom': event.cupomCodigo,
          'campaign_id': cid,
        });
      } catch (_) {}
    }
  }

  /// Emite evento de banner heads-up em primeiro plano com feedback tátil e barra nativa
  static Future<void> _despacharBannerPrimeiroPlano(RemoteMessage message) async {
    final event = _extrairEvento(message);
    if ((event.titulo ?? '').isEmpty && (event.mensagem ?? '').isEmpty) return;

    await exibirNotificacaoHeadsUp(
      titulo: event.titulo ?? 'Promoção OMNI',
      mensagem: event.mensagem ?? '',
      cupomCodigo: event.cupomCodigo,
      campaignId: event.campaignId,
    );
  }

  static void _processarRemoteMessageTap(RemoteMessage message) {
    _emitirDeepLink(_extrairEvento(message));
  }

  static void _emitirDeepLink(OmniDeepLinkCupomEvent event) {
    _deepLinkPendente = event;
    if (!_deepLinkController.isClosed) {
      _deepLinkController.add(event);
    }
  }

  /// Inscreve em `perfil_passageiro` + `passageiro_cidade_{slug}`, desinscreve cidade antiga e grava token no RTDB + PHP
  static Future<void> sincronizarTopicosPassageiro({
    required String passengerId,
    required String cidadeAtual,
    String? tokenOverride,
  }) async {
    _ultimoPassengerId = passengerId;
    if (cidadeAtual.trim().isNotEmpty) {
      _ultimaCidade = cidadeAtual.trim();
    }

    if (kIsWeb || Firebase.apps.isEmpty) return;

    try {
      final messaging = FirebaseMessaging.instance;
      final token = tokenOverride ?? _ultimoToken ?? await messaging.getToken();
      if (token == null || token.isEmpty) return;
      _ultimoToken = token;

      await messaging.subscribeToTopic(_topicPerfilPassageiro);

      final slug = OmniCampanhaPassageiro.normalizarSlugCidade(_ultimaCidade);
      final novoTopicoCidade = slug.isNotEmpty ? 'passageiro_cidade_$slug' : '';

      final prefs = await SharedPreferences.getInstance();
      final antigoTopicoCidade = prefs.getString(_prefLastCityTopic) ?? '';

      if (antigoTopicoCidade.isNotEmpty && antigoTopicoCidade != novoTopicoCidade) {
        try {
          await messaging.unsubscribeFromTopic(antigoTopicoCidade);
        } catch (_) {}
      }
      if (novoTopicoCidade.isNotEmpty) {
        await messaging.subscribeToTopic(novoTopicoCidade);
        await prefs.setString(_prefLastCityTopic, novoTopicoCidade);
      }

      final plataforma = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      final payload = {
        'passenger_id': passengerId,
        'fcm_token': token,
        'cidade_atual': _ultimaCidade,
        'topico_cidade': novoTopicoCidade,
        'topico_perfil': _topicPerfilPassageiro,
        'plataforma': plataforma,
      };

      await OmniFirebaseService.registrarTokenPushRtdb(passengerId, payload);
      await OmniBackendUniversal.executar(
        OmniBackendMethods.registerPushToken,
        args: {
          'passenger_id': passengerId,
          'fcm_token': token,
          'cidade_atual': _ultimaCidade,
          'plataforma': plataforma,
        },
      );
    } catch (_) {}
  }
}
