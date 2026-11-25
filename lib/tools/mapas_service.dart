import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'location_service.dart';

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
  final String fonte; // 'photon' | 'nominatim'
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

  OmniEnderecoSugestao copyWith({
    String? titulo,
    String? subtitulo,
    String? enderecoCompleto,
  }) {
    return OmniEnderecoSugestao(
      id: id,
      placeId: placeId,
      titulo: titulo ?? this.titulo,
      subtitulo: subtitulo ?? this.subtitulo,
      enderecoCompleto: enderecoCompleto ?? this.enderecoCompleto,
      lat: lat,
      lng: lng,
      distanciaKm: distanciaKm,
      fonte: fonte,
      tipoIcone: tipoIcone,
    );
  }
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

/// Serviço Central de Mapas, Autocomplete por Proximidade, Rota OSRM e Geolocalização OMNI (100% Gratuito)
class OmniMapasService {
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

    // Velocidade média adaptativa (urbana 24 km/h, regional 52 km/h, rodoviária/interestadual 75 km/h)
    final double velocidadeMediaKmh = distanciaTotalKm > 100.0
        ? 75.0
        : (distanciaTotalKm > 25.0 ? 52.0 : 24.0);
    final duracaoMinutos =
        math.max(5, ((distanciaTotalKm / velocidadeMediaKmh) * 60).round() + (paradas.length * 3));
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
        const Duration(seconds: 9),
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

  /// Geocodificação reversa 100% gratuita delegada ao motor central OmniLocationService
  /// (Nominatim zoom=18 + OSRM Nearest centerline + geocoding nativo + Photon)
  static Future<String?> reverterCoordenada({
    required double lat,
    required double lng,
    bool forceRefresh = false,
  }) async {
    final res = await OmniLocationService.reverterEnderecoPreciso(
      lat,
      lng,
      forceRefresh: forceRefresh,
    );
    return res?.enderecoCompleto;
  }

  /// Geocodifica endereço digitado manualmente para coordenada real antes de calcular rota ou despachar
  static Future<OmniCoordenada?> geocodificarEnderecoPorTexto({
    required String query,
    required double latReferencia,
    required double lngReferencia,
  }) async {
    final limpo = query.trim();
    if (limpo.length < 3) return null;
    final sugestoes = await buscarEnderecosProximos(
      query: limpo,
      latReferencia: latReferencia,
      lngReferencia: lngReferencia,
    );
    for (final s in sugestoes) {
      if (s.lat != null && s.lng != null) {
        return OmniCoordenada(
          lat: s.lat!,
          lng: s.lng!,
          endereco: s.enderecoCompleto.isNotEmpty ? s.enderecoCompleto : limpo,
        );
      }
    }
    return null;
  }

  /// Extrai número de residência/comércio digitado pelo passageiro (ex: "Av Paulista 1578", "Rua X, 420", "Rua X 420, Bairro")
  static ({String consultaSemNumero, String? numeroDigitado}) extrairConsultaENumero(String query) {
    final q = query.trim();
    if (q.isEmpty || RegExp(r'^\d{5}-?\d{3}$').hasMatch(q)) {
      return (consultaSemNumero: q, numeroDigitado: null);
    }

    // 1. Formato com vírgula antes do número: "Av. Paulista, 1578" ou "Rua 13, nº 450 - Centro"
    final commaMatch = RegExp(
      r'^(.+?)\s*,\s*(?:n[º°o.]?\s*)?(\d{1,5}[a-zA-Z]?)(?:\s*[-–,]\s*(.*))?$',
      caseSensitive: false,
    ).firstMatch(q);
    if (commaMatch != null) {
      final before = commaMatch.group(1)!.trim();
      final numStr = commaMatch.group(2)!.trim();
      final after = (commaMatch.group(3) ?? '').trim();
      final ehPrefixoCep = RegExp(r'^\d{5}$').hasMatch(numStr) &&
          RegExp('${RegExp.escape(numStr)}-\\d{3}').hasMatch(q);
      if (!ehPrefixoCep && before.length >= 2) {
        final consulta = after.isNotEmpty ? '$before $after' : before;
        return (consultaSemNumero: consulta, numeroDigitado: numStr);
      }
    }

    // 2. Formato separado por espaço no final ou antes de vírgula/traço: "Av Paulista 1578" ou "Rua Augusta 500, Consolação"
    final spaceMatch = RegExp(
      r'^(.+?)\s+(?:n[º°o.]?\s*)?(\d{1,5}[a-zA-Z]?)(?:\s*[-–,]\s*(.+))?$',
      caseSensitive: false,
    ).firstMatch(q);
    if (spaceMatch != null) {
      final before = spaceMatch.group(1)!.trim();
      final numStr = spaceMatch.group(2)!.trim();
      final after = (spaceMatch.group(3) ?? '').trim();
      final ehPrefixoCep = RegExp(r'^\d{5}$').hasMatch(numStr) &&
          RegExp('${RegExp.escape(numStr)}-\\d{3}').hasMatch(q);
      final beforeCore = before
          .replaceFirst(
            RegExp(
              r'^(?:rua|r\.|av\.?|avenida|al\.?|alameda|travessa|tv\.?|pra[çc]a|p[çc]a\.?|largo|estrada|rodovia|rod\.?|viela|beco|quadra|qd\.?|lote|lt\.?|setor|br|sp|km|terminal|bloco)\s+',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      final terminaComSiglaRodoviaOuSetor = RegExp(
        r'\b(?:km|br|sp|mg|rj|pr|rs|ba|sc|go|df|terminal|port[aã]o|bloco|m[oó]dulo)\s*$',
        caseSensitive: false,
      ).hasMatch(before);
      if (!ehPrefixoCep && beforeCore.isNotEmpty && !terminaComSiglaRodoviaOuSetor) {
        final consulta = after.isNotEmpty ? '$before $after' : before;
        return (consultaSemNumero: consulta, numeroDigitado: numStr);
      }
    }

    return (consultaSemNumero: q, numeroDigitado: null);
  }

  static bool _possuiNumeroNoEndereco(String texto, String? numeroDigitado) {
    // Remove CEPs brasileiros (00000-000) antes de verificar se já existe número de imóvel/comércio
    final semCep = texto.replaceAll(RegExp(r'\b\d{5}-\d{3}\b'), '');
    if (RegExp(r'(?:,\s*|\bn[º°o.]?\s*)\d{1,5}[a-zA-Z]?(?!\d)', caseSensitive: false).hasMatch(semCep)) {
      return true;
    }
    if (numeroDigitado != null && numeroDigitado.isNotEmpty) {
      return RegExp(
        '(?:^|[\\s,])${RegExp.escape(numeroDigitado)}(?:\$|[\\s,-])',
        caseSensitive: false,
      ).hasMatch(semCep);
    }
    return false;
  }

  /// Garante que o número digitado pelo passageiro apareça no endereço sugerido caso o provedor retorne apenas a rua/comércio sem número
  static OmniEnderecoSugestao _aplicarNumeroDigitado(
    OmniEnderecoSugestao sug,
    String? numeroDigitado,
  ) {
    if (numeroDigitado == null || numeroDigitado.isEmpty) return sug;
    if (_possuiNumeroNoEndereco(sug.titulo, numeroDigitado) ||
        _possuiNumeroNoEndereco(sug.enderecoCompleto, numeroDigitado)) {
      return sug;
    }

    final bool pareceLogradouroOuComercioNaVia = sug.tipoIcone == 'address' ||
        sug.titulo.contains(' · ') ||
        RegExp(
          r'\b(?:rua|r\.|av\.?|avenida|al\.?|alameda|travessa|tv\.?|pra[çc]a|estrada|rodovia|largo|viela)\b',
          caseSensitive: false,
        ).hasMatch(sug.titulo);

    if (!pareceLogradouroOuComercioNaVia) return sug;

    final novoTitulo = '${sug.titulo}, $numeroDigitado';
    final sub = sug.subtitulo.trim();
    final novoCompleto = (sub.isNotEmpty && sub != 'Localização no mapa')
        ? '$novoTitulo - $sub'
        : novoTitulo;
    return sug.copyWith(
      titulo: novoTitulo,
      enderecoCompleto: novoCompleto,
    );
  }

  /// Preserva o número da residência/comércio caso detalhes do lugar retornem apenas o logradouro sem número
  static String preservarNumeroNoEndereco(String fetchedAddress, String suggestionFullAddress) {
    final semCepFetched = fetchedAddress.replaceAll(RegExp(r'\b\d{5}-\d{3}\b'), '');
    if (RegExp(r'(?:,\s*|\bn[º°o.]?\s*)\d{1,5}[a-zA-Z]?(?!\d)', caseSensitive: false).hasMatch(semCepFetched)) {
      return fetchedAddress;
    }
    final semCepSug = suggestionFullAddress.replaceAll(RegExp(r'\b\d{5}-\d{3}\b'), '');
    final numMatch = RegExp(r',\s*(\d{1,5}[a-zA-Z]?)(?!\d)').firstMatch(semCepSug);
    if (numMatch == null) return fetchedAddress;
    final numero = numMatch.group(1)!;
    final idxDash = fetchedAddress.indexOf(' - ');
    if (idxDash > 0) {
      return '${fetchedAddress.substring(0, idxDash)}, $numero${fetchedAddress.substring(idxDash)}';
    }
    final idxComma = fetchedAddress.indexOf(',');
    if (idxComma > 0) {
      return '${fetchedAddress.substring(0, idxComma)}, $numero${fetchedAddress.substring(idxComma)}';
    }
    return '$fetchedAddress, $numero';
  }

  /// Busca global de endereços 100% gratuita com bias geográfico e ordenação estrita por proximidade (Photon + Nominatim)
  static Future<List<OmniEnderecoSugestao>> buscarEnderecosProximos({
    required String query,
    required double latReferencia,
    required double lngReferencia,
    String? sessionToken,
  }) async {
    final limpo = query.trim();
    if (limpo.length < 2) return const [];

    final parsed = extrairConsultaENumero(limpo);
    final numeroDigitado = parsed.numeroDigitado;
    final consultaSemNumero = parsed.consultaSemNumero;

    // Consulta paralela Photon + Nominatim (100% gratuita) para resposta instantânea no Android/iOS APK
    final lotes = await Future.wait<List<OmniEnderecoSugestao>>([
      _buscarPhoton(limpo, latReferencia, lngReferencia),
      _buscarNominatim(limpo, latReferencia, lngReferencia),
    ]);

    final resultados = <OmniEnderecoSugestao>[
      ...lotes[0],
      ...lotes[1],
    ];

    // Se o passageiro digitou número ainda não indexado no OSM, busca também pelo logradouro base e injeta o número
    if (numeroDigitado != null &&
        consultaSemNumero.length >= 2 &&
        consultaSemNumero != limpo &&
        (resultados.length < 4 ||
            !resultados.any((r) => _possuiNumeroNoEndereco(r.enderecoCompleto, numeroDigitado)))) {
      final lotesBase = await Future.wait<List<OmniEnderecoSugestao>>([
        _buscarPhoton(consultaSemNumero, latReferencia, lngReferencia),
        _buscarNominatim(consultaSemNumero, latReferencia, lngReferencia),
      ]);
      resultados.addAll(lotesBase[0]);
      resultados.addAll(lotesBase[1]);
    }

    // Deduplica mantendo a ocorrência exata/menor distância e aplica o número digitado quando ausente
    final mapaUnico = <String, OmniEnderecoSugestao>{};
    for (final rawItem in resultados) {
      final item = _aplicarNumeroDigitado(rawItem, numeroDigitado);
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

          final rawNome = (props['name'] ?? '').toString().trim();
          final rawStreet = (props['street'] ?? '').toString().trim();
          final rawNum = (props['housenumber'] ?? '').toString().trim();
          final ruaBase = rawStreet.isNotEmpty ? rawStreet : rawNome;
          final ruaCompleta = (rawNum.isNotEmpty &&
                  ruaBase.isNotEmpty &&
                  !ruaBase.toLowerCase().contains(rawNum.toLowerCase()))
              ? '$ruaBase, $rawNum'
              : ruaBase;
          final titulo = (rawNome.isNotEmpty &&
                  rawStreet.isNotEmpty &&
                  rawNome.toLowerCase() != rawStreet.toLowerCase())
              ? '$rawNome · $ruaCompleta'
              : (ruaCompleta.isNotEmpty ? ruaCompleta : (rawNome.isNotEmpty ? rawNome : query));

          final bairro = (props['district'] ?? props['suburb'] ?? props['locality'] ?? '').toString().trim();
          final cidade = (props['city'] ?? props['county'] ?? props['state'] ?? '').toString().trim();
          final cep = (props['postcode'] ?? '').toString().trim();
          final pais = (props['country'] ?? '').toString().trim();
          final subtituloPartes = [bairro, cidade, cep, pais].where((e) => e.isNotEmpty).toList();
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
          final rua = (addr['road'] ?? addr['pedestrian'] ?? addr['cycleway'] ?? addr['residential'] ?? poiName).toString().trim();
          final numCasa = (addr['house_number'] ?? '').toString().trim();
          final ruaNum = (rua.isNotEmpty &&
                  numCasa.isNotEmpty &&
                  !rua.toLowerCase().contains(numCasa.toLowerCase()))
              ? '$rua, $numCasa'
              : rua;
          final titulo = (poiName.isNotEmpty &&
                  ruaNum.isNotEmpty &&
                  poiName.toLowerCase() != rua.toLowerCase())
              ? '$poiName · $ruaNum'
              : (ruaNum.isNotEmpty
                  ? ruaNum
                  : (item['display_name']?.toString().split(',').first.trim() ?? query));

          final bairro = (addr['suburb'] ?? addr['neighbourhood'] ?? addr['city_district'] ?? '').toString().trim();
          final cidade = (addr['city'] ?? addr['town'] ?? addr['municipality'] ?? addr['state'] ?? '').toString().trim();
          final cep = (addr['postcode'] ?? '').toString().trim();
          final subtitulo = [bairro, cidade, cep].where((e) => e.isNotEmpty).join(', ');
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

  /// Resolve coordenada exata (lat/lng) ao selecionar uma sugestão do autocomplete gratuito
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

    return OmniCoordenada(
      lat: fallbackLat,
      lng: fallbackLng,
      endereco: sugestao.enderecoCompleto,
    );
  }
}
