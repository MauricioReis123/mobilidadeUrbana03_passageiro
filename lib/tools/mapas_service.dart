import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// Coordenada Geográfica
class OmniCoordenada {
  final double lat;
  final double lng;
  final String? endereco;

  const OmniCoordenada({
    required this.lat,
    required this.lng,
    this.endereco,
  });

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    if (endereco != null) 'endereco': endereco,
  };

  factory OmniCoordenada.fromJson(Map<String, dynamic> json) => OmniCoordenada(
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    endereco: json['endereco'],
  );
}

/// Sugestão de Endereço retornada pelo motor de autocomplete ordenada por proximidade
class OmniEnderecoSugestao {
  final String id;
  final String? placeId;
  final String titulo;
  final String subtitulo;
  final String enderecoCompleto;
  final double? lat;
  final double? lng;
  final double? distanciaKm;
  final String fonte; // 'google_places' | 'photon' | 'nominatim'
  final String tipoIcone; // 'address' | 'airport' | 'transit' | 'shopping' | 'hospital' | 'food' | 'hotel' | 'park' | 'fuel' | 'school'

  const OmniEnderecoSugestao({
    required this.id,
    this.placeId,
    required this.titulo,
    required this.subtitulo,
    required this.enderecoCompleto,
    this.lat,
    this.lng,
    this.distanciaKm,
    required this.fonte,
    this.tipoIcone = 'address',
  });
}

/// Estimativa de Rota (Haversine viário ou OSRM Driving real)
class OmniEstimativaRota {
  final double distanciaKm;
  final int duracaoMinutos;
  final List<OmniCoordenada> pontosPolilinha;
  final double precoBaseSugerido;
  final String routeProvider; // 'osrm_driving' | 'haversine_viario'

  OmniEstimativaRota({
    required this.distanciaKm,
    required this.duracaoMinutos,
    required this.pontosPolilinha,
    required this.precoBaseSugerido,
    this.routeProvider = 'haversine_viario',
  });
}

/// Serviço Central de Mapas, Autocomplete por Proximidade, Rota OSRM e Geolocalização OMNI
class OmniMapasService {
  /// Chave injetada opcionalmente em tempo de compilação via `--dart-define=GOOGLE_MAPS_API_KEY=...`
  static const String _googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
  static const String _attributionId = 'gmp_mcp_codeassist_v1_aistudio';
  static const Map<String, String> _osmHeaders = {
    'Accept': 'application/json',
    'Accept-Language': 'pt-BR,pt;q=0.9',
    'User-Agent': 'OMNI-Passageiro-Mobile/1.0 (https://omni.mobilidade.app)',
  };

  /// Infere o tipo de ícone contextual de mobilidade urbana a partir dos metadados ou texto
  static String inferirTipoIcone({
    String texto = '',
    String? osmKey,
    String? osmValue,
    List<String> googleTypes = const [],
  }) {
    final lowerTypes = googleTypes.map((e) => e.toLowerCase()).toList();
    final keyVal = '${osmKey ?? ''} ${osmValue ?? ''}'.toLowerCase();
    final lowerText = texto.toLowerCase();

    if (lowerTypes.any((t) => t.contains('airport')) ||
        keyVal.contains('aeroway') ||
        keyVal.contains('aerodrome') ||
        RegExp(r'\b(aeroporto|terminal aéreo|congonhas|guarulhos|viracopos|galeão|santos dumont)\b')
            .hasMatch(lowerText)) {
      return 'airport';
    }
    if (lowerTypes.any((t) =>
            t.contains('transit') ||
            t.contains('subway') ||
            t.contains('train') ||
            t.contains('bus')) ||
        keyVal.contains('railway') ||
        keyVal.contains('station') ||
        keyVal.contains('bus_stop') ||
        keyVal.contains('public_transport') ||
        RegExp(r'\b(metr[ôo]|esta[çc][ãa]o|rodovi[áa]ria|terminal|trem|cptm)\b').hasMatch(lowerText)) {
      return 'transit';
    }
    if (lowerTypes.any((t) => t.contains('shopping') || t.contains('store') || t.contains('supermarket')) ||
        keyVal.contains('shop') ||
        keyVal.contains('mall') ||
        keyVal.contains('supermarket') ||
        RegExp(r'\b(shopping|mall|supermercado|hipermercado|mercado|galeria)\b').hasMatch(lowerText)) {
      return 'shopping';
    }
    if (lowerTypes.any((t) => t.contains('hospital') || t.contains('pharmacy') || t.contains('doctor')) ||
        keyVal.contains('hospital') ||
        keyVal.contains('clinic') ||
        keyVal.contains('pharmacy') ||
        RegExp(r'\b(hospital|cl[íi]nica|pronto.?socorro|upa|farm[áa]cia|drogaria)\b').hasMatch(lowerText)) {
      return 'hospital';
    }
    if (lowerTypes.any((t) => t.contains('restaurant') || t.contains('cafe') || t.contains('bakery') || t.contains('bar')) ||
        keyVal.contains('restaurant') ||
        keyVal.contains('cafe') ||
        keyVal.contains('fast_food') ||
        keyVal.contains('bakery') ||
        RegExp(r'\b(restaurante|caf[ée]|padaria|lanchonete|churrascaria|pizzaria)\b').hasMatch(lowerText)) {
      return 'food';
    }
    if (lowerTypes.any((t) => t.contains('lodging') || t.contains('hotel')) ||
        keyVal.contains('hotel') ||
        keyVal.contains('hostel') ||
        keyVal.contains('motel') ||
        RegExp(r'\b(hotel|pousada|resort|hostel)\b').hasMatch(lowerText)) {
      return 'hotel';
    }
    if (lowerTypes.any((t) => t.contains('park') || t.contains('stadium')) ||
        keyVal.contains('park') ||
        keyVal.contains('garden') ||
        keyVal.contains('stadium') ||
        RegExp(r'\b(parque|pra[çc]a|bosque|jardim|est[áa]dio|arena)\b').hasMatch(lowerText)) {
      return 'park';
    }
    if (lowerTypes.any((t) => t.contains('gas_station')) ||
        keyVal.contains('fuel') ||
        RegExp(r'\b(posto|combust[íi]vel|ipiranga|shell|petrobras)\b').hasMatch(lowerText)) {
      return 'fuel';
    }
    if (lowerTypes.any((t) => t.contains('school') || t.contains('university')) ||
        keyVal.contains('school') ||
        keyVal.contains('university') ||
        keyVal.contains('college') ||
        RegExp(r'\b(escola|col[ée]gio|faculdade|universidade|campus|usp|unicamp)\b').hasMatch(lowerText)) {
      return 'school';
    }
    return 'address';
  }

  /// Calcula distância euclidiana/Haversine entre dois pontos em km
  static double calcularDistanciaHaversine(OmniCoordenada p1, OmniCoordenada p2) {
    const double r = 6371; // Raio da Terra em km
    final dLat = _grausParaRadianos(p2.lat - p1.lat);
    final dLng = _grausParaRadianos(p2.lng - p1.lng);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_grausParaRadianos(p1.lat)) *
            math.cos(_grausParaRadianos(p2.lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _grausParaRadianos(double grau) => grau * (math.pi / 180.0);

  static String? formatarDistanciaProximidade(double? distanciaKm) {
    if (distanciaKm == null || distanciaKm.isNaN || distanciaKm < 0) {
      return null;
    }
    if (distanciaKm < 1.0) {
      final metros = math.max(10, (distanciaKm * 1000).round());
      return '$metros m';
    }
    return '${distanciaKm.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  /// Calcula estimativa imediata de rota com suporte a paradas intermediárias (Haversine × 1.32)
  static OmniEstimativaRota calcularRotaComParadas({
    required OmniCoordenada origem,
    required OmniCoordenada destino,
    List<OmniCoordenada> paradas = const [],
    double tarifaBase = 5.50,
    double valorPorKm = 2.10,
    double valorPorMinuto = 0.35,
    double tarifaMinima = 9.90,
  }) {
    double distanciaTotalKm = 0.0;
    OmniCoordenada pontoAtual = origem;

    final todosPontos = [origem, ...paradas, destino];
    for (int i = 1; i < todosPontos.length; i++) {
      distanciaTotalKm += calcularDistanciaHaversine(pontoAtual, todosPontos[i]);
      pontoAtual = todosPontos[i];
    }

    // Fator de correção de malha viária urbana (~1.32x da distância reta)
    distanciaTotalKm = distanciaTotalKm * 1.32;
    if (distanciaTotalKm < 1.0) distanciaTotalKm = 1.0;

    // Estimativa de velocidade média urbana (22 km/h) + 3 min por parada
    final duracaoMinutos = math.max(5, ((distanciaTotalKm / 22.0) * 60).round() + (paradas.length * 3));
    final taxaParadas = paradas.length * 1.50;
    final bruto = tarifaBase + (distanciaTotalKm * valorPorKm) + (duracaoMinutos * valorPorMinuto) + taxaParadas;
    final precoSugerido = math.max(tarifaMinima, bruto);

    return OmniEstimativaRota(
      distanciaKm: double.parse(distanciaTotalKm.toStringAsFixed(1)),
      duracaoMinutos: duracaoMinutos,
      pontosPolilinha: todosPontos,
      precoBaseSugerido: double.parse(precoSugerido.toStringAsFixed(2)),
      routeProvider: 'haversine_viario',
    );
  }

  /// Calcula rota real na malha viária usando OSRM Driving (Origem -> Paradas -> Destino)
  /// com fallback automático e transparente para `calcularRotaComParadas`
  static Future<OmniEstimativaRota> calcularRotaRealComParadas({
    required OmniCoordenada origem,
    required OmniCoordenada destino,
    List<OmniCoordenada> paradas = const [],
    double tarifaBase = 5.50,
    double valorPorKm = 2.10,
    double valorPorMinuto = 0.35,
    double tarifaMinima = 9.90,
  }) async {
    final baseline = calcularRotaComParadas(
      origem: origem,
      destino: destino,
      paradas: paradas,
      tarifaBase: tarifaBase,
      valorPorKm: valorPorKm,
      valorPorMinuto: valorPorMinuto,
      tarifaMinima: tarifaMinima,
    );

    final todosPontos = [origem, ...paradas, destino];
    if (todosPontos.length < 2) return baseline;

    try {
      final coordPath = todosPontos.map((p) => '${p.lng},${p.lat}').join(';');
      final uri = Uri.https('router.project-osrm.org', '/route/v1/driving/$coordPath', {
        'overview': 'false',
      });
      final resp = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(
        const Duration(seconds: 5),
      );

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes.first as Map;
          final distanceMeters = (route['distance'] as num?)?.toDouble();
          final durationSeconds = (route['duration'] as num?)?.toDouble();

          if (distanceMeters != null && durationSeconds != null && distanceMeters > 0) {
            final kmReal = math.max(1.0, distanceMeters / 1000.0);
            final minReal = math.max(4, (durationSeconds / 60.0).round() + (paradas.length * 3));
            final taxaParadas = paradas.length * 1.50;
            final bruto = tarifaBase + (kmReal * valorPorKm) + (minReal * valorPorMinuto) + taxaParadas;
            final precoFinal = math.max(tarifaMinima, bruto);

            return OmniEstimativaRota(
              distanciaKm: double.parse(kmReal.toStringAsFixed(1)),
              duracaoMinutos: minReal,
              pontosPolilinha: todosPontos,
              precoBaseSugerido: double.parse(precoFinal.toStringAsFixed(2)),
              routeProvider: 'osrm_driving',
            );
          }
        }
      }
    } catch (_) {}

    return baseline;
  }

  /// Geocodificação reversa: converte latitude/longitude GPS em nome legível da rua e bairro
  static Future<String?> reverterCoordenada({
    required double lat,
    required double lng,
  }) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': lat.toString(),
        'lon': lng.toString(),
        'accept-language': 'pt-BR',
      });
      final resp = await http
          .get(uri, headers: _osmHeaders)
          .timeout(const Duration(seconds: 6));

      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr == null) return data['display_name'] as String?;

      final rua = (addr['road'] ?? addr['pedestrian'] ?? addr['suburb'] ?? addr['neighbourhood'] ?? '').toString();
      final numCasa = addr['house_number'] != null ? ', ${addr['house_number']}' : '';
      final bairro = (addr['suburb'] ?? addr['neighbourhood'] ?? addr['city_district'] ?? '').toString();
      final cidade = (addr['city'] ?? addr['town'] ?? addr['municipality'] ?? addr['state'] ?? '').toString();

      final partes = <String>[
        if (rua.isNotEmpty) '$rua$numCasa',
        if (bairro.isNotEmpty && bairro != rua) bairro,
        if (cidade.isNotEmpty) cidade,
      ];
      return partes.isNotEmpty ? partes.join(' - ') : (data['display_name'] as String?);
    } catch (_) {
      return null;
    }
  }

  /// Busca global de endereços com bias geográfico e ordenação estrita por proximidade (menor distância primeiro)
  /// Usa Google Places API (New) quando `GOOGLE_MAPS_API_KEY` está configurada e Photon + Nominatim em paralelo.
  static Future<List<OmniEnderecoSugestao>> buscarEnderecosProximos({
    required String query,
    required double latReferencia,
    required double lngReferencia,
    String? sessionToken,
  }) async {
    final limpo = query.trim();
    if (limpo.length < 2) return const [];

    // 1. Google Places API (New) caso GOOGLE_MAPS_API_KEY tenha sido injetada no build Android/Dart
    if (_googleMapsApiKey.isNotEmpty) {
      final googleRes = await _buscarGooglePlacesNew(
        query: limpo,
        latRef: latReferencia,
        lngRef: lngReferencia,
        sessionToken: sessionToken,
      );
      if (googleRes.isNotEmpty) {
        return googleRes;
      }
    }

    // 2. Consulta paralela Photon + Nominatim para resposta instantânea e alta cobertura no Android APK
    final lotes = await Future.wait<List<OmniEnderecoSugestao>>([
      _buscarPhoton(limpo, latReferencia, lngReferencia),
      _buscarNominatim(limpo, latReferencia, lngReferencia),
    ]);

    final resultados = <OmniEnderecoSugestao>[
      ...lotes[0],
      ...lotes[1],
    ];

    // Deduplica mantendo sempre a ocorrência de menor distância e ordena estritamente crescente
    final mapaUnico = <String, OmniEnderecoSugestao>{};
    for (final item in resultados) {
      final chave = '${item.titulo.toLowerCase()}|${item.subtitulo.toLowerCase()}';
      final existente = mapaUnico[chave];
      if (existente == null ||
          (item.distanciaKm ?? double.infinity) < (existente.distanciaKm ?? double.infinity)) {
        mapaUnico[chave] = item;
      }
    }

    final ordenados = mapaUnico.values.toList()
      ..sort((a, b) => (a.distanciaKm ?? double.infinity).compareTo(b.distanciaKm ?? double.infinity));

    return ordenados.take(12).toList();
  }

  static Future<List<OmniEnderecoSugestao>> _buscarPhoton(
    String query,
    double latReferencia,
    double lngReferencia,
  ) async {
    final list = <OmniEnderecoSugestao>[];
    try {
      final photonUri = Uri.https('photon.komoot.io', '/api/', {
        'q': query,
        'lat': latReferencia.toString(),
        'lon': lngReferencia.toString(),
        'limit': '10',
      });
      final resp = await http
          .get(photonUri, headers: _osmHeaders)
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final features = (json['features'] as List?) ?? const [];
        for (final raw in features) {
          if (raw is! Map) continue;
          final geometry = raw['geometry'] as Map?;
          final coords = geometry?['coordinates'] as List?;
          final props = raw['properties'] as Map?;
          if (coords == null || coords.length < 2 || props == null) continue;

          final lng = (coords[0] as num?)?.toDouble();
          final lat = (coords[1] as num?)?.toDouble();
          if (lat == null || lng == null) continue;

          final nome = (props['name'] ?? props['street'] ?? '').toString().trim();
          final numCasa = props['housenumber'] != null ? ', ${props['housenumber']}' : '';
          final ruaCompleta = props['street'] != null ? '${props['street']}$numCasa' : nome;
          final titulo = (nome.isNotEmpty && props['street'] != null && nome != props['street'])
              ? '$nome · $ruaCompleta'
              : (ruaCompleta.isNotEmpty ? ruaCompleta : (nome.isNotEmpty ? nome : query));

          final bairro = (props['district'] ?? props['suburb'] ?? props['locality'] ?? '').toString().trim();
          final cidade = (props['city'] ?? props['county'] ?? props['state'] ?? '').toString().trim();
          final pais = (props['country'] ?? '').toString().trim();
          final subtituloPartes = [bairro, cidade, pais].where((e) => e.isNotEmpty).toList();
          final subtitulo = subtituloPartes.join(', ');
          final enderecoCompleto = subtitulo.isNotEmpty ? '$titulo - $subtitulo' : titulo;

          final distanciaKm = calcularDistanciaHaversine(
            OmniCoordenada(lat: latReferencia, lng: lngReferencia),
            OmniCoordenada(lat: lat, lng: lng),
          );

          final tipoIcone = inferirTipoIcone(
            texto: '$titulo $subtitulo',
            osmKey: props['osm_key']?.toString(),
            osmValue: props['osm_value']?.toString(),
          );

          list.add(
            OmniEnderecoSugestao(
              id: 'photon_${props['osm_id'] ?? '${lat}_$lng'}_${list.length}',
              titulo: titulo,
              subtitulo: subtitulo.isNotEmpty ? subtitulo : 'Localização no mapa',
              enderecoCompleto: enderecoCompleto,
              lat: lat,
              lng: lng,
              distanciaKm: distanciaKm,
              fonte: 'photon',
              tipoIcone: tipoIcone,
            ),
          );
        }
      }
    } catch (_) {}
    return list;
  }

  static Future<List<OmniEnderecoSugestao>> _buscarNominatim(
    String query,
    double latReferencia,
    double lngReferencia,
  ) async {
    final list = <OmniEnderecoSugestao>[];
    try {
      const double d = 0.55;
      final viewbox = '${lngReferencia - d},${latReferencia + d},${lngReferencia + d},${latReferencia - d}';
      final nomUri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '8',
        'accept-language': 'pt-BR',
        'viewbox': viewbox,
        'q': query,
      });
      final resp = await http
          .get(nomUri, headers: _osmHeaders)
          .timeout(const Duration(seconds: 5));

      if (resp.statusCode == 200) {
        final rawList = jsonDecode(resp.body) as List;
        for (final item in rawList) {
          if (item is! Map) continue;
          final lat = double.tryParse(item['lat']?.toString() ?? '');
          final lng = double.tryParse(item['lon']?.toString() ?? '');
          if (lat == null || lng == null) continue;

          final addr = (item['address'] as Map?) ?? {};
          final poiName = (item['name'] ?? '').toString().trim();
          final rua = (addr['road'] ?? addr['pedestrian'] ?? addr['cycleway'] ?? poiName).toString().trim();
          final numCasa = addr['house_number'] != null ? ', ${addr['house_number']}' : '';
          final ruaNum = rua.isNotEmpty ? '$rua$numCasa' : '';
          final titulo = (poiName.isNotEmpty && ruaNum.isNotEmpty && poiName != rua)
              ? '$poiName · $ruaNum'
              : (ruaNum.isNotEmpty
                  ? ruaNum
                  : (item['display_name']?.toString().split(',').first.trim() ?? query));

          final bairro = (addr['suburb'] ?? addr['neighbourhood'] ?? addr['city_district'] ?? '').toString().trim();
          final cidade = (addr['city'] ?? addr['town'] ?? addr['municipality'] ?? addr['state'] ?? '').toString().trim();
          final subtitulo = [bairro, cidade].where((e) => e.isNotEmpty).join(', ');
          final enderecoCompleto = subtitulo.isNotEmpty
              ? '$titulo - $subtitulo'
              : (item['display_name']?.toString() ?? titulo);

          final distanciaKm = calcularDistanciaHaversine(
            OmniCoordenada(lat: latReferencia, lng: lngReferencia),
            OmniCoordenada(lat: lat, lng: lng),
          );

          final tipoIcone = inferirTipoIcone(
            texto: '$titulo $subtitulo',
            osmKey: item['category']?.toString(),
            osmValue: item['type']?.toString(),
          );

          list.add(
            OmniEnderecoSugestao(
              id: 'nom_${item['place_id'] ?? list.length}',
              titulo: titulo,
              subtitulo: subtitulo.isNotEmpty ? subtitulo : (item['display_name']?.toString() ?? ''),
              enderecoCompleto: enderecoCompleto,
              lat: lat,
              lng: lng,
              distanciaKm: distanciaKm,
              fonte: 'nominatim',
              tipoIcone: tipoIcone,
            ),
          );
        }
      }
    } catch (_) {}
    return list;
  }

  /// Chamada oficial Places API (New) via HTTP POST (Android/Dart nativo não sofre bloqueio CORS)
  static Future<List<OmniEnderecoSugestao>> _buscarGooglePlacesNew({
    required String query,
    required double latRef,
    required double lngRef,
    String? sessionToken,
  }) async {
    try {
      final uri = Uri.parse('https://places.googleapis.com/v1/places:autocomplete');
      final body = <String, dynamic>{
        'input': query,
        'languageCode': 'pt-BR',
        'regionCode': 'BR',
        'origin': {'latitude': latRef, 'longitude': lngRef},
        'locationBias': {
          'circle': {
            'center': {'latitude': latRef, 'longitude': lngRef},
            'radius': 50000.0,
          },
        },
        if (sessionToken != null && sessionToken.isNotEmpty) 'sessionToken': sessionToken,
      };

      final resp = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': _googleMapsApiKey,
              'X-Goog-Maps-Solution-ID': _attributionId,
              'X-Goog-FieldMask':
                  'suggestions.placePrediction.placeId,suggestions.placePrediction.text.text,suggestions.placePrediction.structuredFormat,suggestions.placePrediction.distanceMeters,suggestions.placePrediction.types',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 7));

      if (resp.statusCode != 200) return const [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final suggestions = (data['suggestions'] as List?) ?? const [];

      final list = <OmniEnderecoSugestao>[];
      for (int i = 0; i < suggestions.length; i++) {
        final raw = suggestions[i];
        if (raw is! Map || raw['placePrediction'] == null) continue;
        final pred = raw['placePrediction'] as Map;
        final placeId = pred['placeId']?.toString();
        final fullText = (pred['text']?['text'] ?? '').toString();
        final mainText = (pred['structuredFormat']?['mainText']?['text'] ?? fullText).toString();
        final secondaryText = (pred['structuredFormat']?['secondaryText']?['text'] ?? '').toString();
        final distMeters = (pred['distanceMeters'] as num?)?.toDouble();
        final rawTypes = (pred['types'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];

        if (fullText.isEmpty) continue;
        list.add(
          OmniEnderecoSugestao(
            id: 'gplaces_${placeId ?? i}',
            placeId: placeId,
            titulo: mainText,
            subtitulo: secondaryText,
            enderecoCompleto: fullText,
            distanciaKm: (distMeters != null && distMeters >= 0) ? distMeters / 1000.0 : null,
            fonte: 'google_places',
            tipoIcone: inferirTipoIcone(texto: fullText, googleTypes: rawTypes),
          ),
        );
      }

      list.sort((a, b) => (a.distanciaKm ?? double.infinity).compareTo(b.distanciaKm ?? double.infinity));
      return list;
    } catch (_) {
      return const [];
    }
  }

  /// Resolve coordenada exata (lat/lng) ao selecionar uma sugestão do autocomplete
  static Future<OmniCoordenada> obterDetalhesLugar({
    required OmniEnderecoSugestao sugestao,
    required double fallbackLat,
    required double fallbackLng,
    String? sessionToken,
  }) async {
    if (sugestao.lat != null && sugestao.lng != null) {
      return OmniCoordenada(
        lat: sugestao.lat!,
        lng: sugestao.lng!,
        endereco: sugestao.enderecoCompleto,
      );
    }

    if (_googleMapsApiKey.isNotEmpty && sugestao.placeId != null && sugestao.placeId!.isNotEmpty) {
      try {
        final uri = Uri.https(
          'places.googleapis.com',
          '/v1/places/${sugestao.placeId}',
          {
            'languageCode': 'pt-BR',
            if (sessionToken != null && sessionToken.isNotEmpty) 'sessionToken': sessionToken,
          },
        );
        final resp = await http
            .get(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'X-Goog-Api-Key': _googleMapsApiKey,
                'X-Goog-Maps-Solution-ID': _attributionId,
                'X-Goog-FieldMask': 'id,displayName,formattedAddress,location',
              },
            )
            .timeout(const Duration(seconds: 7));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final loc = data['location'] as Map?;
          final lat = (loc?['latitude'] as num?)?.toDouble();
          final lng = (loc?['longitude'] as num?)?.toDouble();
          final formatted = data['formattedAddress']?.toString();
          if (lat != null && lng != null) {
            return OmniCoordenada(
              lat: lat,
              lng: lng,
              endereco: (formatted != null && formatted.isNotEmpty) ? formatted : sugestao.enderecoCompleto,
            );
          }
        }
      } catch (_) {}
    }

    return OmniCoordenada(
      lat: fallbackLat,
      lng: fallbackLng,
      endereco: sugestao.enderecoCompleto,
    );
  }
}
