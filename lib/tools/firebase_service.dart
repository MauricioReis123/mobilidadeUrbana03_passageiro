import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../config/omni_integration_contracts.dart';

/// Modelo de Telemetria de Motorista no RTDB — Alinhado 100% ao nó `/drivers_online/{driver_id}`
class OmniMotoristaTelemetria {
  final String driverId;
  final bool isOnline;
  final String nome;
  final double lat;
  final double lng;
  final double heading;
  final String status;
  final String modeloVeiculo;
  final String placa;
  final double avaliacao;
  final int atualizadoEm;

  OmniMotoristaTelemetria({
    required this.driverId,
    required this.isOnline,
    required this.nome,
    required this.lat,
    required this.lng,
    required this.heading,
    required this.status,
    required this.modeloVeiculo,
    required this.placa,
    required this.avaliacao,
    required this.atualizadoEm,
  });

  factory OmniMotoristaTelemetria.fromMap(String id, Map<dynamic, dynamic> map) {
    final bool online = map[OmniRtdbFields.isOnline] == true;
    final veiculo = map['veiculo'] is Map ? map['veiculo'] as Map : const {};
    return OmniMotoristaTelemetria(
      driverId: (map[OmniRtdbFields.driverId] ?? id).toString(),
      isOnline: online,
      nome: (map['nome'] ?? map['full_name'] ?? 'Motorista OMNI').toString(),
      lat: (map[OmniRtdbFields.lat] as num?)?.toDouble() ?? 0.0,
      lng: (map[OmniRtdbFields.lng] as num?)?.toDouble() ?? 0.0,
      heading: (map[OmniRtdbFields.bearing] as num?)?.toDouble() ??
          (map['heading'] as num?)?.toDouble() ??
          0.0,
      status: online ? 'online' : 'offline',
      modeloVeiculo: (veiculo['modelo'] ?? map['vehicle_model'] ?? 'Veículo OMNI').toString(),
      placa: (veiculo['placa'] ?? map['plate'] ?? '---').toString(),
      avaliacao: (map['avaliacao'] as num?)?.toDouble() ?? 5.0,
      atualizadoEm: (map[OmniRtdbFields.updatedAt] as num?)?.toInt() ?? 0,
    );
  }
}

/// Serviço Firebase Realtime Database para OMNI Passageiro
/// 100% alinhado aos paths e payloads do App Motorista (OmniRtdbPaths / OmniRtdbFields)
class OmniFirebaseService {
  static FirebaseDatabase? _database;
  static bool _inicializado = false;

  static final Map<String, StreamSubscription> _activeSubscriptions = {};

  /// Inicializa o Firebase RTDB com a URL oficial compartilhada
  static Future<void> inicializar() async {
    if (_inicializado) return;
    try {
      _database = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: OmniRtdbConfig.databaseUrl,
      );
      _inicializado = true;
    } catch (_) {
      _inicializado = false;
    }
  }

  /// Escuta motoristas online em tempo real no nó compartilhado `/drivers_online`
  static Stream<List<OmniMotoristaTelemetria>> escutarMotoristasProximos() {
    if (_database == null) {
      return Stream.value([]);
    }
    final ref = _database!.ref(OmniRtdbPaths.driversOnlineRoot);
    return ref.onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null || snapshot.value is! Map) return [];
      final dados = snapshot.value as Map<dynamic, dynamic>;
      final lista = <OmniMotoristaTelemetria>[];
      dados.forEach((key, val) {
        if (val is Map) {
          final item = OmniMotoristaTelemetria.fromMap(key.toString(), val);
          if (item.isOnline) {
            lista.add(item);
          }
        }
      });
      return lista;
    });
  }

  /// Escuta atualizações em tempo real da corrida ativa em `/trips/{trip_id}`
  /// (status canônico, driver_id, driver_location)
  static Stream<Map<String, dynamic>?> escutarCorridaAtiva(String tripId) {
    if (_database == null) {
      return Stream.value(null);
    }
    final ref = _database!.ref(OmniRtdbPaths.trip(tripId));
    return ref.onValue.map((event) {
      final snapshot = event.snapshot;
      if (!snapshot.exists || snapshot.value == null || snapshot.value is! Map) return null;
      return Map<String, dynamic>.from(snapshot.value as Map);
    });
  }

  /// Grava status canônico da corrida em `/trips/{trip_id}/status` (set / PUT)
  static Future<void> atualizarStatusCorrida(String tripId, String canonicalStatus) async {
    if (_database == null) return;
    try {
      await _database!.ref(OmniRtdbPaths.tripStatus(tripId)).set(canonicalStatus);
    } catch (_) {}
  }

  /// Despacha oferta de corrida (janela 15s) para `/dispatch_queue/{driver_id}/{trip_id}` (set / PUT)
  static Future<void> enviarOfertaDespacho({
    required String driverId,
    required String tripId,
    required Map<String, dynamic> offerPayload,
  }) async {
    if (_database == null) return;
    try {
      await _database!.ref(OmniRtdbPaths.dispatchOffer(driverId, tripId)).set(offerPayload);
    } catch (_) {}
  }

  /// Envia mensagem no chat mascarado em `/trips/{trip_id}/chat` usando `push()` (NUNCA set)
  static Future<void> enviarMensagemChat({
    required String tripId,
    required String senderId,
    required String text,
  }) async {
    if (_database == null) return;
    try {
      await _database!.ref(OmniRtdbPaths.tripChat(tripId)).push().set({
        OmniRtdbFields.senderRole: 'passenger',
        OmniRtdbFields.senderId: senderId,
        OmniRtdbFields.text: text,
        OmniRtdbFields.createdAt: DateTime.now().millisecondsSinceEpoch,
        OmniRtdbFields.isRead: false,
      });
    } catch (_) {}
  }

  /// Escuta mensagens em tempo real via `onChildAdded` em `/trips/{trip_id}/chat`
  static Stream<Map<String, dynamic>> escutarChatCorrida(String tripId) {
    if (_database == null) {
      return const Stream.empty();
    }
    final ref = _database!.ref(OmniRtdbPaths.tripChat(tripId));
    return ref.onChildAdded.map((event) {
      final val = event.snapshot.value;
      if (val is Map) {
        return Map<String, dynamic>.from(val);
      }
      return <String, dynamic>{};
    });
  }

  /// Aciona alerta crítico SOS em `/trips/{trip_id}/sos` (set / PUT)
  static Future<void> enviarAlertaSos({
    required String tripId,
    required String passengerId,
    required String driverId,
    required double lat,
    required double lng,
  }) async {
    if (_database == null) return;
    try {
      await _database!.ref(OmniRtdbPaths.tripSos(tripId)).set({
        OmniRtdbFields.triggeredBy: 'passenger',
        OmniRtdbFields.passengerId: passengerId,
        OmniRtdbFields.driverId: driverId,
        OmniRtdbFields.lat: lat,
        OmniRtdbFields.lng: lng,
        OmniRtdbFields.status: 'ACTIVE',
        OmniRtdbFields.createdAt: DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Escuta lances enviados por motoristas em `/private_bids/{offer_id}`
  static Stream<List<Map<String, dynamic>>> escutarLancesPrivados(String offerId) {
    if (_database == null) {
      return Stream.value([]);
    }
    final ref = _database!.ref(OmniRtdbPaths.privateBids(offerId));
    return ref.onValue.map((event) {
      final val = event.snapshot.value;
      if (val is! Map) return <Map<String, dynamic>>[];
      return val.values
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    });
  }

  /// Encerra todos os listeners ativos para evitar vazamento de memória
  static void cancelarTodosListeners() {
    for (final sub in _activeSubscriptions.values) {
      sub.cancel();
    }
    _activeSubscriptions.clear();
  }
}
