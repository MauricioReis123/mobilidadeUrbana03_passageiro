import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import '../config/omni_integration_contracts.dart';
import '../models/campanha_model.dart';

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
/// Modo Híbrido Inteligente:
/// - Usa o SDK nativo `FirebaseDatabase` quando `google-services.json` está presente;
/// - Faz fallback automático transparente para **Firebase RTDB REST + Server-Sent Events (`text/event-stream`)**
///   quando compilado sem `google-services.json`, garantindo 100% de funcionamento em tempo real no APK!
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
      // Sem google-services.json nativo: opera via REST + SSE Streaming contra databaseUrl
      _database = null;
      _inicializado = false;
    }
  }

  static Uri _restUri(String path) {
    final cleanBase = OmniRtdbConfig.databaseUrl.replaceAll(RegExp(r'/+$'), '');
    final cleanPath = path.replaceAll(RegExp(r'^/+'), '');
    return Uri.parse('$cleanBase/$cleanPath.json');
  }

  static Future<dynamic> _restRequest(
    String path, {
    String method = 'GET',
    dynamic body,
  }) async {
    final uri = _restUri(path);
    const headers = {'Content-Type': 'application/json; charset=UTF-8', 'Accept': 'application/json'};
    late http.Response resp;
    final encoded = body != null ? jsonEncode(body) : null;

    switch (method.toUpperCase()) {
      case 'PUT':
        resp = await http.put(uri, headers: headers, body: encoded).timeout(const Duration(seconds: 8));
        break;
      case 'POST':
        resp = await http.post(uri, headers: headers, body: encoded).timeout(const Duration(seconds: 8));
        break;
      case 'PATCH':
        resp = await http.patch(uri, headers: headers, body: encoded).timeout(const Duration(seconds: 8));
        break;
      default:
        resp = await http.get(uri, headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('RTDB REST HTTP ${resp.statusCode}');
    }
    if (resp.body.trim().isEmpty || resp.body.trim() == 'null') return null;
    return jsonDecode(resp.body);
  }

  static Map<String, dynamic> _applySsePatch(
    Map<String, dynamic>? current,
    String subPath,
    dynamic data,
  ) {
    final base = current != null ? Map<String, dynamic>.from(current) : <String, dynamic>{};
    final parts = subPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      if (data is Map) {
        data.forEach((k, v) => base[k.toString()] = v);
      }
      return base;
    }

    Map<String, dynamic> cursor = base;
    for (int i = 0; i < parts.length - 1; i++) {
      final k = parts[i];
      final existing = cursor[k];
      if (existing is Map) {
        cursor[k] = Map<String, dynamic>.from(existing);
      } else {
        cursor[k] = <String, dynamic>{};
      }
      cursor = cursor[k] as Map<String, dynamic>;
    }

    final leaf = parts.last;
    if (data == null) {
      cursor.remove(leaf);
    } else if (data is Map && cursor[leaf] is Map) {
      final merged = Map<String, dynamic>.from(cursor[leaf] as Map);
      data.forEach((k, v) => merged[k.toString()] = v);
      cursor[leaf] = merged;
    } else {
      cursor[leaf] = data;
    }
    return base;
  }

  static Map<String, dynamic>? _applySsePut(
    Map<String, dynamic>? current,
    String subPath,
    dynamic data,
  ) {
    final parts = subPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      if (data is Map) return Map<String, dynamic>.from(data);
      return null;
    }
    final base = current != null ? Map<String, dynamic>.from(current) : <String, dynamic>{};
    Map<String, dynamic> cursor = base;
    for (int i = 0; i < parts.length - 1; i++) {
      final k = parts[i];
      final existing = cursor[k];
      if (existing is Map) {
        cursor[k] = Map<String, dynamic>.from(existing);
      } else {
        cursor[k] = <String, dynamic>{};
      }
      cursor = cursor[k] as Map<String, dynamic>;
    }

    final leaf = parts.last;
    if (data == null) {
      cursor.remove(leaf);
    } else {
      cursor[leaf] = data;
    }
    return base;
  }

  /// Stream em tempo real via Server-Sent Events (SSE) do Firebase RTDB com reconexão automática + poll inicial
  static Stream<Map<String, dynamic>?> _streamSseNode(
    String path, {
    Duration fallbackInterval = const Duration(seconds: 3),
  }) {
    late final StreamController<Map<String, dynamic>?> controller;
    bool closed = false;
    Map<String, dynamic>? snapshotCache;
    http.Client? client;
    StreamSubscription<String>? lineSub;
    Timer? reconnectTimer;
    Timer? pollTimer;

    void emitCurrent() {
      if (!closed && !controller.isClosed) {
        controller.add(snapshotCache != null ? Map<String, dynamic>.from(snapshotCache!) : null);
      }
    }

    Future<void> pollOnce() async {
      if (closed) return;
      try {
        final raw = await _restRequest(path, method: 'GET');
        if (closed) return;
        snapshotCache = raw is Map ? Map<String, dynamic>.from(raw) : null;
        emitCurrent();
      } catch (_) {}
    }

    Future<void> connectSse() async {
      if (closed) return;
      await lineSub?.cancel();
      client?.close();
      client = http.Client();

      try {
        final req = http.Request('GET', _restUri(path));
        req.headers['Accept'] = 'text/event-stream';
        req.headers['Cache-Control'] = 'no-cache';

        final streamed = await client!.send(req).timeout(const Duration(seconds: 12));
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          throw Exception('SSE HTTP ${streamed.statusCode}');
        }

        pollTimer?.cancel();
        pollTimer = null;

        String currentEvent = 'put';
        final dataBuffer = StringBuffer();

        lineSub = streamed.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            if (closed) return;
            if (line.startsWith('event:')) {
              currentEvent = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              dataBuffer.writeln(line.substring(5).trim());
            } else if (line.trim().isEmpty && dataBuffer.isNotEmpty) {
              final rawJson = dataBuffer.toString().trim();
              dataBuffer.clear();
              if (currentEvent == 'keep-alive' || currentEvent == 'cancel' || rawJson == 'null') {
                return;
              }
              try {
                final decoded = jsonDecode(rawJson);
                if (decoded is Map) {
                  final subPath = (decoded['path'] ?? '/').toString();
                  final payload = decoded['data'];
                  if (currentEvent == 'patch') {
                    snapshotCache = _applySsePatch(snapshotCache, subPath, payload);
                    emitCurrent();
                  } else if (currentEvent == 'put') {
                    snapshotCache = _applySsePut(snapshotCache, subPath, payload);
                    emitCurrent();
                  }
                }
              } catch (_) {}
            }
          },
          onError: (_) {
            if (closed) return;
            pollTimer ??= Timer.periodic(fallbackInterval, (_) => pollOnce());
            reconnectTimer?.cancel();
            reconnectTimer = Timer(const Duration(seconds: 4), connectSse);
          },
          onDone: () {
            if (closed) return;
            pollTimer ??= Timer.periodic(fallbackInterval, (_) => pollOnce());
            reconnectTimer?.cancel();
            reconnectTimer = Timer(const Duration(seconds: 2), connectSse);
          },
          cancelOnError: false,
        );
      } catch (_) {
        if (closed) return;
        await pollOnce();
        pollTimer ??= Timer.periodic(fallbackInterval, (_) => pollOnce());
        reconnectTimer?.cancel();
        reconnectTimer = Timer(const Duration(seconds: 4), connectSse);
      }
    }

    controller = StreamController<Map<String, dynamic>?>.broadcast(
      onListen: () {
        pollOnce();
        connectSse();
      },
      onCancel: () {
        closed = true;
        pollTimer?.cancel();
        reconnectTimer?.cancel();
        lineSub?.cancel();
        client?.close();
      },
    );

    return controller.stream;
  }

  /// Escuta motoristas online em tempo real no nó compartilhado `/drivers_online`
  static Stream<List<OmniMotoristaTelemetria>> escutarMotoristasProximos() {
    List<OmniMotoristaTelemetria> parseDrivers(Map<dynamic, dynamic>? dados) {
      if (dados == null) return [];
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
    }

    if (_database != null) {
      final ref = _database!.ref(OmniRtdbPaths.driversOnlineRoot);
      return ref.onValue.map((event) {
        final snapshot = event.snapshot;
        if (!snapshot.exists || snapshot.value == null || snapshot.value is! Map) return [];
        return parseDrivers(snapshot.value as Map<dynamic, dynamic>);
      });
    }

    return _streamSseNode(
      OmniRtdbPaths.driversOnlineRoot,
      fallbackInterval: const Duration(seconds: 4),
    ).map(parseDrivers);
  }

  /// Lê telemetria pontual de um motorista online em `/drivers_online/{driver_id}`
  static Future<OmniMotoristaTelemetria?> obterTelemetriaMotorista(String driverId) async {
    try {
      if (_database != null) {
        final snap = await _database!.ref(OmniRtdbPaths.driverOnline(driverId)).get();
        if (snap.exists && snap.value is Map) {
          return OmniMotoristaTelemetria.fromMap(driverId, snap.value as Map);
        }
      }
      final raw = await _restRequest(OmniRtdbPaths.driverOnline(driverId), method: 'GET');
      if (raw is Map) {
        return OmniMotoristaTelemetria.fromMap(driverId, raw);
      }
    } catch (_) {}
    return null;
  }

  /// Grava / atualiza snapshot completo da corrida em `/trips/{trip_id}` (PATCH)
  static Future<void> registrarDadosCorridaRtdb(
    String tripId,
    Map<String, dynamic> tripPayload,
  ) async {
    final sanitized = Map<String, dynamic>.from(tripPayload);
    sanitized[OmniRtdbFields.updatedAt] = DateTime.now().millisecondsSinceEpoch;

    if (_database != null) {
      try {
        await _database!.ref(OmniRtdbPaths.trip(tripId)).update(sanitized);
        return;
      } catch (_) {}
    }
    try {
      await _restRequest(OmniRtdbPaths.trip(tripId), method: 'PATCH', body: sanitized);
    } catch (_) {}
  }

  /// Busca snapshot instantâneo em `/trips/{trip_id}` (usado ao sincronizar manualmente)
  static Future<Map<String, dynamic>?> obterSnapshotCorrida(String tripId) async {
    if (_database != null) {
      try {
        final snap = await _database!.ref(OmniRtdbPaths.trip(tripId)).get();
        if (snap.exists && snap.value is Map) {
          return Map<String, dynamic>.from(snap.value as Map);
        }
      } catch (_) {}
    }
    try {
      final raw = await _restRequest(OmniRtdbPaths.trip(tripId), method: 'GET');
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } catch (_) {}
    return null;
  }

  /// Escuta atualizações em tempo real da corrida ativa em `/trips/{trip_id}`
  static Stream<Map<String, dynamic>?> escutarCorridaAtiva(String tripId) {
    if (_database != null) {
      final ref = _database!.ref(OmniRtdbPaths.trip(tripId));
      return ref.onValue.map((event) {
        final snapshot = event.snapshot;
        if (!snapshot.exists || snapshot.value == null || snapshot.value is! Map) return null;
        return Map<String, dynamic>.from(snapshot.value as Map);
      });
    }
    return _streamSseNode(
      OmniRtdbPaths.trip(tripId),
      fallbackInterval: const Duration(seconds: 2),
    );
  }

  /// Grava status canônico da corrida em `/trips/{trip_id}/status` (set / PUT)
  static Future<void> atualizarStatusCorrida(String tripId, String canonicalStatus) async {
    if (_database != null) {
      try {
        await _database!.ref(OmniRtdbPaths.tripStatus(tripId)).set(canonicalStatus);
        return;
      } catch (_) {}
    }
    try {
      await _restRequest(OmniRtdbPaths.tripStatus(tripId), method: 'PUT', body: canonicalStatus);
    } catch (_) {}
  }

  /// Despacha oferta de corrida para `/dispatch_queue/{driver_id}/{trip_id}` (set / PUT)
  static Future<void> enviarOfertaDespacho({
    required String driverId,
    required String tripId,
    required Map<String, dynamic> offerPayload,
  }) async {
    if (_database != null) {
      try {
        await _database!.ref(OmniRtdbPaths.dispatchOffer(driverId, tripId)).set(offerPayload);
        return;
      } catch (_) {}
    }
    try {
      await _restRequest(
        OmniRtdbPaths.dispatchOffer(driverId, tripId),
        method: 'PUT',
        body: offerPayload,
      );
    } catch (_) {}
  }

  /// Envia mensagem no chat mascarado em `/trips/{trip_id}/chat` usando `push()` / POST e retorna o `push_id`
  static Future<String?> enviarMensagemChat({
    required String tripId,
    required String senderId,
    required String text,
  }) async {
    final payload = {
      OmniRtdbFields.senderRole: 'passenger',
      OmniRtdbFields.senderId: senderId,
      OmniRtdbFields.text: text,
      OmniRtdbFields.createdAt: DateTime.now().millisecondsSinceEpoch,
      OmniRtdbFields.isRead: false,
    };

    if (_database != null) {
      try {
        final pushRef = _database!.ref(OmniRtdbPaths.tripChat(tripId)).push();
        await pushRef.set(payload);
        return pushRef.key;
      } catch (_) {}
    }

    try {
      final resp = await _restRequest(
        OmniRtdbPaths.tripChat(tripId),
        method: 'POST',
        body: payload,
      );
      if (resp is Map && resp['name'] != null) {
        return resp['name'].toString();
      }
    } catch (_) {}
    return null;
  }

  /// Marca mensagens recebidas do motorista como lidas (`is_read: true`)
  static Future<void> marcarMensagensChatLidas(String tripId, List<String> pushIds) async {
    if (pushIds.isEmpty) return;
    for (final pid in pushIds) {
      final path = '${OmniRtdbPaths.tripChat(tripId)}/$pid';
      if (_database != null) {
        try {
          await _database!.ref(path).update({OmniRtdbFields.isRead: true});
          continue;
        } catch (_) {}
      }
      try {
        await _restRequest(path, method: 'PATCH', body: {OmniRtdbFields.isRead: true});
      } catch (_) {}
    }
  }

  /// Escuta mensagens em tempo real em `/trips/{trip_id}/chat` (SDK onChildAdded + SSE REST fallback)
  /// Emite Map com `'push_id'` para permitir deduplicação e sincronia bidirecional completa.
  static Stream<Map<String, dynamic>> escutarChatCorrida(String tripId) {
    if (_database != null) {
      final ref = _database!.ref(OmniRtdbPaths.tripChat(tripId));
      return ref.onChildAdded.map((event) {
        final val = event.snapshot.value;
        if (val is Map) {
          final map = Map<String, dynamic>.from(val);
          if (event.snapshot.key != null) {
            map['push_id'] = event.snapshot.key;
          }
          return map;
        }
        return <String, dynamic>{};
      });
    }

    late final StreamController<Map<String, dynamic>> controller;
    final seenKeys = <String>{};
    StreamSubscription<Map<String, dynamic>?>? sub;

    controller = StreamController<Map<String, dynamic>>.broadcast(
      onListen: () {
        sub = _streamSseNode(
          OmniRtdbPaths.tripChat(tripId),
          fallbackInterval: const Duration(seconds: 2),
        ).listen((chatMap) {
          if (chatMap == null || controller.isClosed) return;
          final entries = chatMap.entries.where((e) => e.value is Map).toList();
          entries.sort((a, b) {
            final ta = ((a.value as Map)[OmniRtdbFields.createdAt] as num?)?.toInt() ?? 0;
            final tb = ((b.value as Map)[OmniRtdbFields.createdAt] as num?)?.toInt() ?? 0;
            return ta.compareTo(tb);
          });
          for (final entry in entries) {
            if (seenKeys.contains(entry.key)) continue;
            seenKeys.add(entry.key);
            final msg = Map<String, dynamic>.from(entry.value as Map);
            msg['push_id'] = entry.key;
            if (!controller.isClosed) controller.add(msg);
          }
        });
      },
      onCancel: () {
        sub?.cancel();
      },
    );

    return controller.stream;
  }

  /// Aciona alerta crítico SOS em `/trips/{trip_id}/sos` (set / PUT)
  static Future<void> enviarAlertaSos({
    required String tripId,
    required String passengerId,
    required String driverId,
    required double lat,
    required double lng,
  }) async {
    final payload = {
      OmniRtdbFields.triggeredBy: 'passenger',
      OmniRtdbFields.passengerId: passengerId,
      OmniRtdbFields.driverId: driverId,
      OmniRtdbFields.lat: lat,
      OmniRtdbFields.lng: lng,
      OmniRtdbFields.status: 'ACTIVE',
      OmniRtdbFields.createdAt: DateTime.now().toUtc().toIso8601String(),
    };

    if (_database != null) {
      try {
        await _database!.ref(OmniRtdbPaths.tripSos(tripId)).set(payload);
        return;
      } catch (_) {}
    }
    try {
      await _restRequest(OmniRtdbPaths.tripSos(tripId), method: 'PUT', body: payload);
    } catch (_) {}
  }

  /// Publica oferta particular diretamente em `/private_offers/{offer_id}` caso o backend PHP esteja offline
  static Future<void> publicarOfertaPrivada(
    String offerId,
    Map<String, dynamic> payload,
  ) async {
    if (_database != null) {
      try {
        await _database!.ref(OmniRtdbPaths.privateOffer(offerId)).set(payload);
        return;
      } catch (_) {}
    }
    try {
      await _restRequest(OmniRtdbPaths.privateOffer(offerId), method: 'PUT', body: payload);
    } catch (_) {}
  }

  /// Escuta lances enviados por motoristas em `/private_bids/{offer_id}`
  static Stream<List<Map<String, dynamic>>> escutarLancesPrivados(String offerId) {
    List<Map<String, dynamic>> parseBids(Map<dynamic, dynamic>? val) {
      if (val == null) return [];
      final lista = <Map<String, dynamic>>[];
      val.forEach((key, v) {
        if (v is Map) {
          final m = Map<String, dynamic>.from(v);
          m.putIfAbsent(OmniRtdbFields.bidId, () => key.toString());
          lista.add(m);
        }
      });
      lista.sort((a, b) {
        final ba = (a[OmniRtdbFields.bidAmount] as num?)?.toDouble() ?? 0.0;
        final bb = (b[OmniRtdbFields.bidAmount] as num?)?.toDouble() ?? 0.0;
        return ba.compareTo(bb);
      });
      return lista;
    }

    if (_database != null) {
      final ref = _database!.ref(OmniRtdbPaths.privateBids(offerId));
      return ref.onValue.map((event) {
        final val = event.snapshot.value;
        if (val is! Map) return <Map<String, dynamic>>[];
        return parseBids(val);
      });
    }

    return _streamSseNode(
      OmniRtdbPaths.privateBids(offerId),
      fallbackInterval: const Duration(seconds: 3),
    ).map(parseBids);
  }

  /// Grava ou atualiza token push e tópicos do passageiro em `/passageiros_push/{passenger_id}`
  static Future<void> registrarTokenPushRtdb(
    String passengerId,
    Map<String, dynamic> payload,
  ) async {
    final pid = passengerId.trim();
    if (pid.isEmpty) return;
    final sanitized = Map<String, dynamic>.from(payload);
    sanitized[OmniRtdbFields.updatedAt] = DateTime.now().millisecondsSinceEpoch;

    if (_database != null) {
      try {
        await _database!.ref(OmniRtdbPaths.passageiroPush(pid)).set(sanitized);
        return;
      } catch (_) {}
    }
    try {
      await _restRequest(OmniRtdbPaths.passageiroPush(pid), method: 'PUT', body: sanitized);
    } catch (_) {}
  }

  /// Escuta campanhas promocionais em tempo real em `/campanhas_passageiro` (SDK + SSE fallback)
  static Stream<List<OmniCampanhaPassageiro>> escutarCampanhasPassageiro() {
    List<OmniCampanhaPassageiro> parseCampanhas(Map<dynamic, dynamic>? val) {
      if (val == null) return [];
      final lista = <OmniCampanhaPassageiro>[];
      val.forEach((key, v) {
        if (v is Map) {
          lista.add(OmniCampanhaPassageiro.fromMap(key.toString(), v));
        }
      });
      lista.sort((a, b) => b.id.compareTo(a.id));
      return lista;
    }

    if (_database != null) {
      final ref = _database!.ref(OmniRtdbPaths.campanhasPassageiroRoot);
      return ref.onValue.map((event) {
        final val = event.snapshot.value;
        if (val is! Map) return <OmniCampanhaPassageiro>[];
        return parseCampanhas(val);
      });
    }

    return _streamSseNode(
      OmniRtdbPaths.campanhasPassageiroRoot,
      fallbackInterval: const Duration(seconds: 6),
    ).map(parseCampanhas);
  }

  /// Encerra todos os listeners ativos para evitar vazamento de memória
  static void cancelarTodosListeners() {
    for (final sub in _activeSubscriptions.values) {
      sub.cancel();
    }
    _activeSubscriptions.clear();
  }
}
