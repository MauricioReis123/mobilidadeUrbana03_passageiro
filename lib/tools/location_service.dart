import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'mapas_service.dart';

/// Resultado estruturado de geocodificação reversa 100% gratuita
class OmniEnderecoDetalhado {
  final String enderecoCompleto;
  final String rua;
  final String numero;
  final String bairro;
  final String cidade;
  final String uf;
  final String cep;
  final String fonte;

  const OmniEnderecoDetalhado({
    required this.enderecoCompleto,
    this.rua = '',
    this.numero = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
    this.cep = '',
    this.fonte = 'nominatim',
  });
}

/// Posição de alta precisão com filtro de sinal, alerta de precisão reduzida e endereço resolvido
class OmniPosicaoPrecisa {
  final double lat;
  final double lng;
  final double accuracyMeters;
  final double heading;
  final double speedMps;
  final bool reducedAccuracyAlert;
  final OmniEnderecoDetalhado? enderecoDetalhado;

  const OmniPosicaoPrecisa({
    required this.lat,
    required this.lng,
    required this.accuracyMeters,
    this.heading = 0.0,
    this.speedMps = 0.0,
    this.reducedAccuracyAlert = false,
    this.enderecoDetalhado,
  });

  String? get enderecoCompleto => enderecoDetalhado?.enderecoCompleto;
  String get cidade => enderecoDetalhado?.cidade ?? '';
}

class _ReverseGeoCacheEntry {
  final OmniEnderecoDetalhado data;
  final DateTime expiresAt;
  const _ReverseGeoCacheEntry(this.data, this.expiresAt);
}

class _OsrmRoadCandidate {
  final String name;
  final double distanceMeters;
  final double snappedLat;
  final double snappedLng;
  const _OsrmRoadCandidate({
    required this.name,
    required this.distanceMeters,
    required this.snappedLat,
    required this.snappedLng,
  });
}

class _GeoStreetRecord {
  final String rua;
  final String numero;
  final String bairro;
  final String cidade;
  final String uf;
  final String cep;
  final double? distanceMeters;
  final String fonte;

  const _GeoStreetRecord({
    this.rua = '',
    this.numero = '',
    this.bairro = '',
    this.cidade = '',
    this.uf = '',
    this.cep = '',
    this.distanceMeters,
    required this.fonte,
  });
}

/// Motor Central de Localização Nativa de Alta Precisão e Geocodificação 100% Gratuita
/// - Nunca utiliza `getLastKnownPosition()`
/// - Usa `LocationAccuracy.bestForNavigation` com `AndroidSettings` (Fused Location) / `AppleSettings`
/// - Descarta leituras antigas (> 15s) ou imprecisas (> 15m), aplica rejeição de outliers por mediana
///   e fusão ponderada por variância (Kalman 1D/2D)
/// - Arbitragem de logradouro 100% gratuita: Nominatim (`zoom=18`) + OSRM Nearest (`number=3`) +
///   `geocoding` nativo + Photon Reverse, evitando desvio para rua transversal em esquinas
/// - Snap-to-Road gratuito com `bearings` via OSRM Nearest (`/nearest/v1/driving`)
class OmniLocationService {
  static const double _maxAccuracyMeters = 15.0;
  static const double _debounceDisplacementMeters = 6.0;
  static const Duration _debounceDuration = Duration(milliseconds: 700);
  static const int _maxStaleFixSeconds = 15;
  static const Map<String, String> _osmHeaders = {
    'Accept': 'application/json',
    'Accept-Language': 'pt-BR,pt;q=0.9',
    'User-Agent': 'OMNI-Passageiro-Mobile/1.0 (https://omni.mobilidade.app)',
  };

  static final Map<String, _ReverseGeoCacheEntry> _reverseCache = {};
  static Timer? _debounceTimer;
  static double? _lastDebouncedLat;
  static double? _lastDebouncedLng;

  /// Configurações nativas específicas de plataforma para máxima precisão
  static LocationSettings obterSettingsPlataforma({int distanceFilter = 3}) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distanceFilter,
        forceLocationManager: false,
        intervalDuration: const Duration(milliseconds: 1200),
      );
    }
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: distanceFilter,
    );
  }

  /// Verifica se o usuário concedeu apenas localização aproximada (Precisão Reduzida)
  static Future<bool> verificarPrecisaoReduzida() async {
    if (kIsWeb) return false;
    try {
      final status = await Geolocator.getLocationAccuracy();
      return status == LocationAccuracyStatus.reduced;
    } catch (_) {
      return false;
    }
  }

  /// Solicita precisão total temporária no iOS (`OmniPrecisePickup` em Info.plist) quando reduzida
  static Future<bool> solicitarPrecisaoCompletaSeNecessario() async {
    if (kIsWeb) return false;
    try {
      var status = await Geolocator.getLocationAccuracy();
      if (status == LocationAccuracyStatus.reduced &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS)) {
        status = await Geolocator.requestTemporaryFullAccuracy(
          purposeKey: 'OmniPrecisePickup',
        );
      }
      return status == LocationAccuracyStatus.reduced;
    } catch (_) {
      return await verificarPrecisaoReduzida();
    }
  }

  /// Reseta o último ponto de debounce ao recentrar GPS manualmente
  static void resetarDebounce() {
    _debounceTimer?.cancel();
    _lastDebouncedLat = null;
    _lastDebouncedLng = null;
  }

  /// Rejeita outliers espaciais (> 35m da mediana quando há 3+ amostras) antes da fusão Kalman
  static List<Position> _filtrarOutliersEspaciais(List<Position> amostras) {
    if (amostras.length < 3) return amostras;
    final lats = amostras.map((p) => p.latitude).toList()..sort();
    final lngs = amostras.map((p) => p.longitude).toList()..sort();
    final medLat = lats[lats.length ~/ 2];
    final medLng = lngs[lngs.length ~/ 2];
    final centroMediano = OmniCoordenada(lat: medLat, lng: medLng);

    final filtradas = amostras.where((p) {
      final distM = OmniMapasService.calcularDistanciaHaversine(
            centroMediano,
            OmniCoordenada(lat: p.latitude, lng: p.longitude),
          ) *
          1000.0;
      return distM <= 35.0;
    }).toList();

    return filtradas.isNotEmpty ? filtradas : amostras;
  }

  /// Captura posição de alta precisão descartando leituras antigas ou com erro > 15m e aplicando filtro ponderado
  static Future<OmniPosicaoPrecisa> capturarPosicaoFina({
    bool resolverEndereco = true,
    bool forceRefreshAddress = true,
  }) async {
    resetarDebounce();
    final reducedAlert = await solicitarPrecisaoCompletaSeNecessario();
    final settings = obterSettingsPlataforma(distanceFilter: 0);

    final List<Position> todasAmostrasFrescas = [];
    final List<Position> amostrasFinas = [];
    final List<Position> backupQualquerIdade = [];
    final completer = Completer<void>();
    StreamSubscription<Position>? sub;
    Timer? hardTimeout;
    final inicioCaptura = DateTime.now();

    try {
      sub = Geolocator.getPositionStream(locationSettings: settings).listen(
        (pos) {
          backupQualquerIdade.add(pos);
          final idadeSegundos = inicioCaptura.difference(pos.timestamp).inSeconds;
          // Ignora cache antigo inicial emitido pelo FusedLocation se ainda houver janela para fix real
          if (idadeSegundos > _maxStaleFixSeconds && !pos.isMocked) {
            return;
          }
          todasAmostrasFrescas.add(pos);
          if (pos.accuracy > 0 && pos.accuracy <= _maxAccuracyMeters) {
            amostrasFinas.add(pos);
          }
          // Encerra rápido com 3 leituras <= 10m ou 4 leituras <= 15m
          final tightCount = amostrasFinas.where((p) => p.accuracy <= 10.0).length;
          if ((tightCount >= 3 || amostrasFinas.length >= 4) && !completer.isCompleted) {
            completer.complete();
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
      );

      hardTimeout = Timer(const Duration(seconds: 7), () {
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future;
    } catch (_) {
      // Fallback abaixo se o stream não puder ser iniciado
    } finally {
      hardTimeout?.cancel();
      await sub?.cancel();
    }

    Position? baseFallback;
    if (amostrasFinas.isEmpty) {
      try {
        final single = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 10),
        );
        backupQualquerIdade.add(single);
        todasAmostrasFrescas.add(single);
        if (single.accuracy > 0 && single.accuracy <= _maxAccuracyMeters) {
          amostrasFinas.add(single);
        }
        baseFallback = single;
      } catch (_) {}
    }

    final candidatas = amostrasFinas.isNotEmpty
        ? amostrasFinas
        : (todasAmostrasFrescas.isNotEmpty ? todasAmostrasFrescas : backupQualquerIdade);

    if (candidatas.isEmpty && baseFallback == null) {
      throw Exception('Não foi possível obter uma leitura de GPS precisa.');
    }

    final listaBruta = candidatas.isNotEmpty ? candidatas : [baseFallback!];
    final listaFinal = _filtrarOutliersEspaciais(listaBruta);

    // Filtro de Kalman 1D ponderado pela inversa da variância da acurácia (1 / accuracy^2)
    double sumWeights = 0.0;
    double weightedLat = 0.0;
    double weightedLng = 0.0;
    double bestAccuracy = double.infinity;

    for (final p in listaFinal) {
      final acc = p.accuracy > 1.0 ? p.accuracy : 3.0;
      final weight = 1.0 / (acc * acc);
      weightedLat += p.latitude * weight;
      weightedLng += p.longitude * weight;
      sumWeights += weight;
      if (p.accuracy > 0 && p.accuracy < bestAccuracy) {
        bestAccuracy = p.accuracy;
      }
    }

    final finalLat = sumWeights > 0 ? weightedLat / sumWeights : listaFinal.last.latitude;
    final finalLng = sumWeights > 0 ? weightedLng / sumWeights : listaFinal.last.longitude;
    final ultima = listaFinal.last;
    final finalAccuracy = bestAccuracy.isFinite
        ? double.parse(bestAccuracy.toStringAsFixed(1))
        : (ultima.accuracy > 0 ? double.parse(ultima.accuracy.toStringAsFixed(1)) : 12.0);

    OmniEnderecoDetalhado? endereco;
    if (resolverEndereco) {
      endereco = await reverterEnderecoPreciso(
        finalLat,
        finalLng,
        forceRefresh: forceRefreshAddress,
      );
    }

    return OmniPosicaoPrecisa(
      lat: finalLat,
      lng: finalLng,
      accuracyMeters: finalAccuracy,
      heading: ultima.heading.isFinite && ultima.heading >= 0 ? ultima.heading : 0.0,
      speedMps: ultima.speed.isFinite && ultima.speed >= 0 ? ultima.speed : 0.0,
      reducedAccuracyAlert: reducedAlert || finalAccuracy > _maxAccuracyMeters,
      enderecoDetalhado: endereco,
    );
  }

  /// Stream contínuo com filtro de ruído Kalman 2D para acompanhamento em tempo real (Motorista/Passageiro)
  static Stream<OmniPosicaoPrecisa> obterStreamPosicaoRefinada({
    int distanceFilter = 3,
    double maxAcceptableAccuracy = 25.0,
  }) {
    final settings = obterSettingsPlataforma(distanceFilter: distanceFilter);
    double? kalmanLat;
    double? kalmanLng;
    double kalmanVar = 100.0;

    return Geolocator.getPositionStream(locationSettings: settings)
        .where((pos) => pos.accuracy <= 0 || pos.accuracy <= maxAcceptableAccuracy)
        .map((pos) {
      final acc = pos.accuracy > 1.5 ? pos.accuracy : 3.5;
      final measVar = acc * acc;

      if (kalmanLat == null || kalmanLng == null) {
        kalmanLat = pos.latitude;
        kalmanLng = pos.longitude;
        kalmanVar = measVar;
      } else {
        // Ruído de processo proporcional ao movimento
        final processNoise = (pos.speed.isFinite && pos.speed > 1.0) ? 9.0 : 1.5;
        kalmanVar += processNoise;
        final kGain = kalmanVar / (kalmanVar + measVar);
        kalmanLat = kalmanLat! + kGain * (pos.latitude - kalmanLat!);
        kalmanLng = kalmanLng! + kGain * (pos.longitude - kalmanLng!);
        kalmanVar = (1.0 - kGain) * kalmanVar;
      }

      return OmniPosicaoPrecisa(
        lat: kalmanLat!,
        lng: kalmanLng!,
        accuracyMeters: double.parse(acc.toStringAsFixed(1)),
        heading: pos.heading.isFinite && pos.heading >= 0 ? pos.heading : 0.0,
        speedMps: pos.speed.isFinite && pos.speed >= 0 ? pos.speed : 0.0,
        reducedAccuracyAlert: acc > _maxAccuracyMeters,
      );
    });
  }

  static String _normalizarVia(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    const mapa = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    mapa.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'\b(r\.?|rua)\b'), 'rua');
    s = s.replaceAll(RegExp(r'\b(av\.?|avenida)\b'), 'avenida');
    s = s.replaceAll(RegExp(r'\b(tv\.?|travessa)\b'), 'travessa');
    s = s.replaceAll(RegExp(r'\b(al\.?|alameda)\b'), 'alameda');
    s = s.replaceAll(RegExp(r'\b(rod\.?|rodovia)\b'), 'rodovia');
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _viasCompativeis(String a, String b) {
    final na = _normalizarVia(a);
    final nb = _normalizarVia(b);
    if (na.isEmpty || nb.isEmpty) return false;
    return na == nb || na.contains(nb) || nb.contains(na);
  }

  static Future<List<_OsrmRoadCandidate>> _consultarViasProximasOsrm(
    double lat,
    double lng, {
    double? headingDeg,
  }) async {
    try {
      final params = <String, String>{'number': '3'};
      if (headingDeg != null && headingDeg.isFinite && headingDeg >= 0 && headingDeg <= 360) {
        final b = headingDeg.round() % 360;
        params['bearings'] = '$b,45';
      }
      final uri = Uri.https(
        'router.project-osrm.org',
        '/nearest/v1/driving/$lng,$lat',
        params,
      );
      final resp = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final waypoints = data['waypoints'] as List?;
        if (waypoints != null) {
          final out = <_OsrmRoadCandidate>[];
          for (final raw in waypoints) {
            if (raw is! Map) continue;
            final name = (raw['name'] ?? '').toString().trim();
            final dist = (raw['distance'] as num?)?.toDouble() ?? double.infinity;
            final loc = raw['location'] as List?;
            if (loc == null || loc.length < 2) continue;
            out.add(
              _OsrmRoadCandidate(
                name: name,
                distanceMeters: dist,
                snappedLng: (loc[0] as num).toDouble(),
                snappedLat: (loc[1] as num).toDouble(),
              ),
            );
          }
          return out;
        }
      }
    } catch (_) {}
    return const [];
  }

  /// Geocodificação reversa 100% gratuita com arbitragem de eixo viário:
  /// - Consulta em paralelo Nominatim (`zoom=18`) + OSRM Nearest (`number=3`) + `geocoding` nativo
  ///   (+ Photon Reverse quando necessário para número ou confirmação de esquina)
  /// - Impede que POIs de esquina atribuam endereço da rua transversal (ex: Rua 620 vs Rua 700)
  /// - Cache espacial fino (~5.5m) ignorável via `forceRefresh: true`
  static Future<OmniEnderecoDetalhado?> reverterEnderecoPreciso(
    double lat,
    double lng, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${(lat * 20000).round()}_${(lng * 20000).round()}';
    if (!forceRefresh) {
      final cached = _reverseCache[cacheKey];
      if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
        return cached.data;
      }
    }

    String? fallbackDisplay;
    _GeoStreetRecord? nomRecord;
    final List<_GeoStreetRecord> nativeRecords = [];
    final List<_GeoStreetRecord> photonRecords = [];
    List<_OsrmRoadCandidate> osrmRoads = const [];

    // 1. Consulta paralela gratuita: Nominatim + OSRM Nearest (eixo viário) + Geocoder Nativo
    final Future<void> fNominatim = () async {
      try {
        final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
          'format': 'jsonv2',
          'zoom': '18',
          'addressdetails': '1',
          'extratags': '1',
          'lat': lat.toString(),
          'lon': lng.toString(),
          'accept-language': 'pt-BR',
        });
        final resp = await http
            .get(uri, headers: _osmHeaders)
            .timeout(const Duration(seconds: 6));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          fallbackDisplay = data['display_name'] as String?;
          final addr = data['address'] as Map<String, dynamic>?;
          if (addr != null) {
            final nLat = double.tryParse((data['lat'] ?? '').toString());
            final nLng = double.tryParse((data['lon'] ?? '').toString());
            final distM = (nLat != null && nLng != null)
                ? OmniMapasService.calcularDistanciaHaversine(
                      OmniCoordenada(lat: lat, lng: lng),
                      OmniCoordenada(lat: nLat, lng: nLng),
                    ) *
                    1000.0
                : null;
            final ufNom = (addr['ISO3166-2-lvl4'] ?? '')
                .toString()
                .replaceFirst('BR-', '')
                .trim();
            nomRecord = _GeoStreetRecord(
              rua: (addr['road'] ??
                      addr['pedestrian'] ??
                      addr['residential'] ??
                      addr['suburb'] ??
                      addr['neighbourhood'] ??
                      '')
                  .toString()
                  .trim(),
              numero: (addr['house_number'] ?? '').toString().trim(),
              bairro: (addr['suburb'] ?? addr['neighbourhood'] ?? addr['city_district'] ?? '')
                  .toString()
                  .trim(),
              cidade: (addr['city'] ?? addr['town'] ?? addr['municipality'] ?? addr['village'] ?? '')
                  .toString()
                  .trim(),
              uf: ufNom.isNotEmpty ? ufNom : (addr['state'] ?? '').toString().trim(),
              cep: (addr['postcode'] ?? '').toString().trim(),
              distanceMeters: distM,
              fonte: 'nominatim',
            );
          }
        }
      } catch (_) {}
    }();

    final Future<void> fOsrm = () async {
      osrmRoads = await _consultarViasProximasOsrm(lat, lng);
    }();

    final Future<void> fNative = () async {
      if (kIsWeb) return;
      try {
        final placemarks = await geocoding
            .placemarkFromCoordinates(lat, lng)
            .timeout(const Duration(seconds: 4));
        for (final p in placemarks.take(4)) {
          final pRua = (p.thoroughfare ?? p.street ?? '').trim();
          final pNum = (p.subThoroughfare ?? '').trim();
          final pBairro = (p.subLocality ?? '').trim();
          final pCidade = (p.subAdministrativeArea ?? p.locality ?? '').trim();
          final pUf = (p.administrativeArea ?? '').trim();
          final pCep = (p.postalCode ?? '').trim();
          if (pRua.isNotEmpty || pNum.isNotEmpty || pCidade.isNotEmpty) {
            nativeRecords.add(
              _GeoStreetRecord(
                rua: pRua,
                numero: pNum,
                bairro: pBairro,
                cidade: pCidade,
                uf: pUf,
                cep: pCep,
                fonte: 'native_geocoding',
              ),
            );
          }
        }
      } catch (_) {}
    }();

    await Future.wait([fNominatim, fOsrm, fNative]);

    // 2. Decide se precisa consultar Photon Reverse (sem número, sem rua ou conflito entre vias)
    final osrmNomeadas = osrmRoads.where((r) => r.name.isNotEmpty && r.distanceMeters <= 40.0).toList();
    final osrmMaisProxima = osrmNomeadas.isNotEmpty ? osrmNomeadas.first : null;
    final nomTemNum = nomRecord != null && nomRecord!.numero.isNotEmpty;
    final nativeTemNum = nativeRecords.any((r) => r.numero.isNotEmpty);
    final conflitoEsquina = osrmMaisProxima != null &&
        nomRecord != null &&
        nomRecord!.rua.isNotEmpty &&
        !_viasCompativeis(nomRecord!.rua, osrmMaisProxima.name);

    if (!nomTemNum && !nativeTemNum ||
        (nomRecord?.rua ?? '').isEmpty ||
        conflitoEsquina) {
      try {
        final photonUri = Uri.https('photon.komoot.io', '/reverse', {
          'lat': lat.toString(),
          'lon': lng.toString(),
          'limit': '5',
        });
        final pResp = await http
            .get(photonUri, headers: _osmHeaders)
            .timeout(const Duration(seconds: 5));
        if (pResp.statusCode == 200) {
          final pJson = jsonDecode(pResp.body) as Map<String, dynamic>;
          final features = (pJson['features'] as List?) ?? const [];
          for (final raw in features) {
            if (raw is! Map) continue;
            final props = raw['properties'] as Map?;
            final coords = (raw['geometry'] as Map?)?['coordinates'] as List?;
            if (props == null || coords == null || coords.length < 2) continue;
            final pLat = (coords[1] as num?)?.toDouble();
            final pLng = (coords[0] as num?)?.toDouble();
            if (pLat == null || pLng == null) continue;
            final distM = OmniMapasService.calcularDistanciaHaversine(
                  OmniCoordenada(lat: lat, lng: lng),
                  OmniCoordenada(lat: pLat, lng: pLng),
                ) *
                1000.0;
            if (distM > 55.0) continue;

            photonRecords.add(
              _GeoStreetRecord(
                rua: (props['street'] ?? props['name'] ?? '').toString().trim(),
                numero: (props['housenumber'] ?? '').toString().trim(),
                bairro: (props['district'] ?? props['suburb'] ?? props['locality'] ?? '')
                    .toString()
                    .trim(),
                cidade: (props['city'] ?? '').toString().trim(),
                uf: (props['state'] ?? '').toString().trim(),
                cep: (props['postcode'] ?? '').toString().trim(),
                distanceMeters: distM,
                fonte: 'photon',
              ),
            );
          }
        }
      } catch (_) {}
    }

    // 3. Arbitragem da via exata (combate desvio de quarteirão em esquinas)
    final allRecords = <_GeoStreetRecord>[
      if (nomRecord != null) nomRecord!,
      ...nativeRecords,
      ...photonRecords,
    ];

    String rua = nomRecord?.rua ?? '';
    String fonte = nomRecord?.fonte ?? 'nominatim';

    if (osrmMaisProxima != null && osrmMaisProxima.distanceMeters <= 25.0) {
      final nomBateComOsrm = rua.isNotEmpty && _viasCompativeis(rua, osrmMaisProxima.name);
      if (!nomBateComOsrm) {
        final nativeConfirmaOsrm = nativeRecords.any(
          (r) => r.rua.isNotEmpty && _viasCompativeis(r.rua, osrmMaisProxima.name),
        );
        final photonConfirmaOsrm = photonRecords.any(
          (r) => r.rua.isNotEmpty && _viasCompativeis(r.rua, osrmMaisProxima.name),
        );
        final nomBateComViaMaisDistante = osrmNomeadas.skip(1).any(
              (other) =>
                  _viasCompativeis(rua, other.name) &&
                  (other.distanceMeters - osrmMaisProxima.distanceMeters) >= 6.0,
            );

        if (rua.isEmpty ||
            nativeConfirmaOsrm ||
            photonConfirmaOsrm ||
            nomBateComViaMaisDistante ||
            osrmMaisProxima.distanceMeters <= 16.0) {
          // Prefere grafia acentuada de um provedor compatível quando existir
          final matchBonito = allRecords.firstWhere(
            (r) => r.rua.isNotEmpty && _viasCompativeis(r.rua, osrmMaisProxima.name),
            orElse: () => _GeoStreetRecord(rua: osrmMaisProxima.name, fonte: 'osrm_nearest'),
          );
          rua = matchBonito.rua;
          fonte = (nativeConfirmaOsrm || photonConfirmaOsrm)
              ? '${matchBonito.fonte}+osrm_centerline'
              : 'osrm_centerline';
        }
      }
    }

    if (rua.isEmpty) {
      for (final rec in allRecords) {
        if (rec.rua.isNotEmpty) {
          rua = rec.rua;
          fonte = rec.fonte;
          break;
        }
      }
    }

    // 4. Número da casa: prioriza sempre registro cuja via bate com a rua vencedora
    String numCasa = '';
    if (rua.isNotEmpty) {
      for (final rec in allRecords) {
        if (rec.numero.isNotEmpty && rec.rua.isNotEmpty && _viasCompativeis(rec.rua, rua)) {
          numCasa = rec.numero;
          if (!fonte.contains(rec.fonte)) {
            fonte = '$fonte+${rec.fonte}';
          }
          break;
        }
      }
    }
    // Se nenhum registro com número citou a rua vencedora, aceita número muito próximo (<= 25m)
    if (numCasa.isEmpty) {
      for (final rec in allRecords) {
        final perto = rec.distanceMeters == null || rec.distanceMeters! <= 25.0;
        if (rec.numero.isNotEmpty && perto) {
          numCasa = rec.numero;
          break;
        }
      }
    }

    String bairro = '';
    String cidade = '';
    String uf = '';
    String cep = '';
    for (final rec in allRecords) {
      if (bairro.isEmpty && rec.bairro.isNotEmpty) bairro = rec.bairro;
      if (cidade.isEmpty && rec.cidade.isNotEmpty) cidade = rec.cidade;
      if (uf.isEmpty && rec.uf.isNotEmpty) uf = rec.uf;
      if (cep.isEmpty && rec.cep.isNotEmpty) cep = rec.cep;
    }

    final viaFormatada = rua.isNotEmpty ? (numCasa.isNotEmpty ? '$rua, $numCasa' : rua) : '';
    final cidadeUf = [cidade, uf].where((e) => e.isNotEmpty).join(' - ');
    final subPartes = [
      if (bairro.isNotEmpty && bairro != rua) bairro,
      if (cidadeUf.isNotEmpty) cidadeUf,
      if (cep.isNotEmpty) 'CEP $cep',
    ];
    final completo = [
      if (viaFormatada.isNotEmpty) viaFormatada,
      if (subPartes.isNotEmpty) subPartes.join(', '),
    ].join(' - ');

    final textoFinal = completo.isNotEmpty ? completo : (fallbackDisplay ?? '');
    if (textoFinal.isEmpty) return null;

    final result = OmniEnderecoDetalhado(
      enderecoCompleto: textoFinal,
      rua: rua,
      numero: numCasa,
      bairro: bairro,
      cidade: cidade,
      uf: uf,
      cep: cep,
      fonte: fonte,
    );

    if (_reverseCache.length > 120) {
      _reverseCache.remove(_reverseCache.keys.first);
    }
    _reverseCache[cacheKey] = _ReverseGeoCacheEntry(
      result,
      DateTime.now().add(const Duration(minutes: 4)),
    );

    return result;
  }

  /// Ajuste fino do pino com Debounce de 700ms e filtro de deslocamento >= 6m
  static void reverterComDebounce(
    double lat,
    double lng,
    void Function(OmniEnderecoDetalhado? resultado) onResult, {
    bool force = false,
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () async {
      if (!force && _lastDebouncedLat != null && _lastDebouncedLng != null) {
        final distM = OmniMapasService.calcularDistanciaHaversine(
              OmniCoordenada(lat: _lastDebouncedLat!, lng: _lastDebouncedLng!),
              OmniCoordenada(lat: lat, lng: lng),
            ) *
            1000.0;
        if (distM < _debounceDisplacementMeters) {
          onResult(null);
          return;
        }
      }
      _lastDebouncedLat = lat;
      _lastDebouncedLng = lng;
      final res = await reverterEnderecoPreciso(lat, lng, forceRefresh: force);
      onResult(res);
    });
  }

  /// Snap-to-Road 100% gratuito usando OSRM Nearest (com suporte a `bearings` para direção do veículo)
  static Future<OmniCoordenada> alinharViaOsrmNearest(
    double lat,
    double lng, {
    double? headingDeg,
    double maxSnapMeters = 35.0,
  }) async {
    try {
      final params = <String, String>{'number': '1'};
      if (headingDeg != null &&
          headingDeg.isFinite &&
          headingDeg >= 0 &&
          headingDeg <= 360) {
        final b = headingDeg.round() % 360;
        params['bearings'] = '$b,45';
      }
      final uri = Uri.https(
        'router.project-osrm.org',
        '/nearest/v1/driving/$lng,$lat',
        params,
      );
      var resp = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 4));

      // Se com bearing restritivo o OSRM não encontrou segmento, refaz sem bearing
      if (resp.statusCode != 200 && params.containsKey('bearings')) {
        final fallbackUri = Uri.https(
          'router.project-osrm.org',
          '/nearest/v1/driving/$lng,$lat',
          const {'number': '1'},
        );
        resp = await http
            .get(fallbackUri, headers: const {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 4));
      }

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final waypoints = data['waypoints'] as List?;
        if (waypoints != null && waypoints.isNotEmpty) {
          final wp = waypoints.first as Map;
          final distMeters = (wp['distance'] as num?)?.toDouble() ?? double.infinity;
          final loc = wp['location'] as List?;
          if (distMeters <= maxSnapMeters && loc != null && loc.length >= 2) {
            final snappedLng = (loc[0] as num).toDouble();
            final snappedLat = (loc[1] as num).toDouble();
            final name = (wp['name'] ?? '').toString().trim();
            return OmniCoordenada(
              lat: snappedLat,
              lng: snappedLng,
              endereco: name.isNotEmpty ? name : null,
            );
          }
        }
      }
    } catch (_) {}
    return OmniCoordenada(lat: lat, lng: lng);
  }

  /// Interpolação linear de posição + cálculo de ângulo/heading para suavizar o marcador do carro no mapa
  static ({double lat, double lng, double headingDeg}) interpolarPosicaoComHeading({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    required double t,
    double? fallbackHeading,
  }) {
    final clampedT = t.clamp(0.0, 1.0);
    final lat = fromLat + ((toLat - fromLat) * clampedT);
    final lng = fromLng + ((toLng - fromLng) * clampedT);

    final dLat = toLat - fromLat;
    final dLng = toLng - fromLng;
    double heading = fallbackHeading ?? 0.0;

    if (dLat.abs() > 1e-6 || dLng.abs() > 1e-6) {
      final phi1 = fromLat * math.pi / 180.0;
      final phi2 = toLat * math.pi / 180.0;
      final dLambda = (toLng - fromLng) * math.pi / 180.0;
      final y = math.sin(dLambda) * math.cos(phi2);
      final x = math.cos(phi1) * math.sin(phi2) -
          math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
      final theta = math.atan2(y, x);
      heading = (theta * 180.0 / math.pi + 360.0) % 360.0;
    }

    return (lat: lat, lng: lng, headingDeg: heading);
  }
}
