import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/omni_integration_contracts.dart';
import '../constants/omni_constants.dart';
import '../models/campanha_model.dart';
import '../models/categoria_model.dart';
import '../models/corrida_model.dart';
import '../models/fidelidade_model.dart';
import '../models/motorista_model.dart';
import '../models/pacote_model.dart';
import '../models/passageiro_model.dart';
import '../tools/backends_service.dart';
import '../tools/firebase_service.dart';
import '../tools/location_service.dart';
import '../tools/mapas_service.dart';
import '../tools/passenger_notification_service.dart';
import '../tools/sql_service.dart';

/// Cartão de crédito/débito salvo pelo passageiro
class OmniCartaoSalvo {
  final String id;
  final String bandeira;
  final String ultimos4;
  final String titular;

  const OmniCartaoSalvo({
    required this.id,
    required this.bandeira,
    required this.ultimos4,
    required this.titular,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'bandeira': bandeira,
    'ultimos4': ultimos4,
    'titular': titular,
  };

  factory OmniCartaoSalvo.fromJson(Map<String, dynamic> json) => OmniCartaoSalvo(
    id: json['id'] ?? '',
    bandeira: json['bandeira'] ?? 'Cartão',
    ultimos4: json['ultimos4'] ?? '0000',
    titular: json['titular'] ?? '',
  );
}

/// Registro real de corrida concluída no histórico
class OmniHistoricoCorrida {
  final String id;
  final String origem;
  final String destino;
  final String categoriaNome;
  final double valorTotal;
  final double gorjeta;
  final double distanciaKm;
  final int avaliacao;
  final int pontosGanhos;
  final DateTime concluidaEm;

  const OmniHistoricoCorrida({
    required this.id,
    required this.origem,
    required this.destino,
    required this.categoriaNome,
    required this.valorTotal,
    required this.gorjeta,
    required this.distanciaKm,
    required this.avaliacao,
    required this.pontosGanhos,
    required this.concluidaEm,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'origem': origem,
    'destino': destino,
    'categoria_nome': categoriaNome,
    'valor_total': valorTotal,
    'gorjeta': gorjeta,
    'distancia_km': distanciaKm,
    'avaliacao': avaliacao,
    'pontos_ganhos': pontosGanhos,
    'concluida_em': concluidaEm.toIso8601String(),
  };

  factory OmniHistoricoCorrida.fromJson(Map<String, dynamic> json) => OmniHistoricoCorrida(
    id: json['id'] ?? '',
    origem: json['origem'] ?? '',
    destino: json['destino'] ?? '',
    categoriaNome: json['categoria_nome'] ?? 'OMNI Pop',
    valorTotal: (json['valor_total'] as num?)?.toDouble() ?? 0.0,
    gorjeta: (json['gorjeta'] as num?)?.toDouble() ?? 0.0,
    distanciaKm: (json['distancia_km'] as num?)?.toDouble() ?? 0.0,
    avaliacao: (json['avaliacao'] as num?)?.toInt() ?? 5,
    pontosGanhos: (json['pontos_ganhos'] as num?)?.toInt() ?? 0,
    concluidaEm: DateTime.tryParse(json['concluida_em'] ?? '') ?? DateTime.now(),
  );
}

/// Notificação real da Caixa de Entrada do passageiro
class OmniNotificacao {
  final String id;
  final String titulo;
  final String mensagem;
  final DateTime criadaEm;
  final bool lida;
  final String? cupomAcao;

  const OmniNotificacao({
    required this.id,
    required this.titulo,
    required this.mensagem,
    required this.criadaEm,
    this.lida = false,
    this.cupomAcao,
  });

  OmniNotificacao copyWith({bool? lida}) => OmniNotificacao(
    id: id,
    titulo: titulo,
    mensagem: mensagem,
    criadaEm: criadaEm,
    lida: lida ?? this.lida,
    cupomAcao: cupomAcao,
  );
}

/// Mensagem de chat da corrida ativa sincronizada em tempo real via Firebase RTDB
class OmniMensagemChat {
  final String? id;
  final String autor; // 'passageiro' | 'motorista'
  final String texto;
  final DateTime enviadaEm;
  final bool lida;

  const OmniMensagemChat({
    this.id,
    required this.autor,
    required this.texto,
    required this.enviadaEm,
    this.lida = false,
  });

  OmniMensagemChat copyWith({String? id, bool? lida}) => OmniMensagemChat(
    id: id ?? this.id,
    autor: autor,
    texto: texto,
    enviadaEm: enviadaEm,
    lida: lida ?? this.lida,
  );
}

/// Gerenciador Central de Estado Real do OMNI Passageiro (Provider / ChangeNotifier)
/// 100% real: GPS alta precisão (bestForNavigation), geocodificação real OSRM/Nominatim/Photon,
/// persistência em SharedPreferences + MySQL (PHP) e tempo real via Firebase RTDB.
class OmniAppState extends ChangeNotifier {
  static const String _keyPassageiro = 'omni_passageiro_v2';
  static const String _keyCartoes = 'omni_cartoes_v2';
  static const String _keyHistorico = 'omni_historico_v2';
  static const String _keyRecentes = 'omni_recentes_v2';
  static const String _keyPacotes = 'omni_pacotes_ativos_v2';
  static const String _keyCasa = 'omni_endereco_casa_v2';
  static const String _keyTrabalho = 'omni_endereco_trabalho_v2';
  static const String _keyCampanhasNotificadas = 'omni_campanhas_notificadas_v1';

  SharedPreferences? _prefs;
  bool _inicializado = false;
  bool _gpsCarregando = false;
  bool _gpsAtivo = false;
  bool _rtdbConectado = false;
  String? _erroGps;
  double? _gpsPrecisaoMetros;
  bool _precisaoReduzidaAlerta = false;
  String _cidadeAtual = '';

  OmniPassageiroModel _passageiro = OmniPassageiroModel(
    id: 'pas_${DateTime.now().millisecondsSinceEpoch}',
    nome: 'Passageiro OMNI',
    email: '',
    telefone: '',
    cpf: '',
    nivelFidelidade: 'OMNI Start',
    saldoPontos: 0,
    codigoIndicacao: 'OMNI-${(1000 + math.Random().nextInt(9000))}',
    saldoCarteira: 0.0,
    avaliacaoMedia: 5.0,
  );

  OmniCoordenada _posicaoAtual = const OmniCoordenada(
    lat: -23.561414,
    lng: -46.655881,
    endereco: 'Obtendo localização GPS...',
  );

  String _enderecoCasa = '';
  String _enderecoTrabalho = '';
  List<OmniCartaoSalvo> _cartoesSalvos = [];
  List<OmniHistoricoCorrida> _historicoCorridas = [];
  List<OmniDestinoRecente> _destinosRecentes = [];
  Set<String> _pacotesAtivosIds = {};
  int _amigosIndicados = 0;
  double _bonusIndicacoes = 0.0;

  // Telemetria em tempo real de motoristas, campanhas e corrida (Firebase RTDB)
  List<OmniMotoristaModel> _motoristasOnline = [];
  List<OmniCampanhaPassageiro> _campanhasRaw = [];
  final Set<String> _campanhasNotificadasIds = {};
  DateTime? _sessionStartedAt;
  StreamSubscription<List<OmniMotoristaTelemetria>>? _driversSub;
  StreamSubscription<List<OmniCampanhaPassageiro>>? _campanhasSub;
  StreamSubscription<Map<String, dynamic>?>? _activeRideSub;
  StreamSubscription<Map<String, dynamic>>? _chatSub;

  // Corrida ativa + chat bidirecional RTDB + notificações
  OmniCorridaModel? _corridaAtiva;
  final List<OmniMensagemChat> _mensagensChat = [];
  final Set<String> _chatPushIdsVistos = {};
  final List<OmniNotificacao> _notificacoes = [];

  // Getters públicos
  bool get inicializado => _inicializado;
  bool get gpsCarregando => _gpsCarregando;
  bool get gpsAtivo => _gpsAtivo;
  bool get rtdbConectado => _rtdbConectado;
  String? get erroGps => _erroGps;
  double? get gpsPrecisaoMetros => _gpsPrecisaoMetros;
  bool get precisaoReduzidaAlerta => _precisaoReduzidaAlerta;
  String get cidadeAtual => _cidadeAtual;
  bool get ehProprietarioAutorizado =>
      _passageiro.email.trim().toLowerCase() == OmniRtdbConfig.ownerEmail;
  List<OmniCampanhaPassageiro> get campanhasAtivas => _campanhasRaw
      .where((c) => c.ehAtivaParaPassageiro && c.aplicaNaCidade(_cidadeAtual))
      .toList();

  OmniPassageiroModel get passageiro => _passageiro;
  OmniCoordenada get posicaoAtual => _posicaoAtual;
  String get enderecoCasa => _enderecoCasa;
  String get enderecoTrabalho => _enderecoTrabalho;
  List<OmniCartaoSalvo> get cartoesSalvos => List.unmodifiable(_cartoesSalvos);
  List<OmniHistoricoCorrida> get historicoCorridas => List.unmodifiable(_historicoCorridas);
  List<OmniDestinoRecente> get destinosRecentes => List.unmodifiable(_destinosRecentes);
  Set<String> get pacotesAtivosIds => Set.unmodifiable(_pacotesAtivosIds);
  int get amigosIndicados => _amigosIndicados;
  double get bonusIndicacoes => _bonusIndicacoes;

  List<OmniMotoristaModel> get motoristasOnline => List.unmodifiable(_motoristasOnline);
  OmniCorridaModel? get corridaAtiva => _corridaAtiva;
  List<OmniMensagemChat> get mensagensChat => List.unmodifiable(_mensagensChat);
  int get mensagensNaoLidasMotorista =>
      _mensagensChat.where((m) => m.autor == 'motorista' && !m.lida).length;
  List<OmniNotificacao> get notificacoes => List.unmodifiable(_notificacoes);
  int get notificacoesNaoLidas => _notificacoes.where((n) => !n.lida).length;

  OmniCampanhaPassageiro? encontrarCampanhaPorCupom(String codigo) {
    final norm = codigo.trim().toUpperCase();
    if (norm.isEmpty) return null;
    for (final c in campanhasAtivas) {
      if (c.codigoCupom.toUpperCase() == norm) return c;
    }
    return null;
  }

  /// Nível de fidelidade atual calculado dinamicamente pelos pontos reais
  OmniNivelFidelidade get nivelFidelidadeAtual {
    OmniNivelFidelidade atual = OmniNivelFidelidade.niveis.first;
    for (final niv in OmniNivelFidelidade.niveis) {
      if (_passageiro.saldoPontos >= niv.pontosNecessarios) {
        atual = niv;
      }
    }
    return atual;
  }

  String get backendDominio => OmniRouterConfig.configuredInput;

  Future<String> salvarBackendDominio(String rawValue) async {
    final saved = await OmniBackendUniversal.salvarDominioEmCache(rawValue);
    notifyListeners();
    return saved;
  }

  /// Inicializa persistência local, GPS (primeiro diálogo), Push/FCM (segundo diálogo) e listeners RTDB
  Future<void> inicializar() async {
    if (_inicializado) return;
    _sessionStartedAt = DateTime.now().toUtc();
    _prefs = await SharedPreferences.getInstance();
    await OmniBackendUniversal.carregarDominioDoCache();
    _carregarDadosLocais();
    _inicializado = true;

    if (_notificacoes.isEmpty) {
      _notificacoes.add(
        OmniNotificacao(
          id: 'notif_welcome',
          titulo: 'Bem-vindo ao OMNI Passageiro',
          mensagem: 'Ative o cupom OMNI15 para ganhar 15% de desconto na sua corrida.',
          criadaEm: DateTime.now(),
          cupomAcao: 'OMNI15',
        ),
      );
    }

    notifyListeners();
    _iniciarEscutaCampanhasRtdb();
    _iniciarEscutaMotoristasRtdb();

    // Sequencia GPS antes de Push para não colidir diálogos de permissão no Android e já ter `_cidadeAtual`
    await atualizarLocalizacaoGps(forceRefresh: true);
    await OmniPassengerNotificationService.inicializar(
      passengerId: _passageiro.id,
      cidadeAtual: _cidadeAtual,
    );
    unawaited(_sincronizarDadosIniciaisSql());
  }

  void _iniciarEscutaCampanhasRtdb() {
    _campanhasSub?.cancel();
    _campanhasSub = OmniFirebaseService.escutarCampanhasPassageiro().listen((lista) {
      _campanhasRaw = lista;
      final agoraUtc = DateTime.now().toUtc();
      bool salvouVistos = false;

      for (final c in lista) {
        if (c.status != 'enviada' || !c.ehAtivaParaPassageiro || !c.aplicaNaCidade(_cidadeAtual)) {
          continue;
        }
        if (_campanhasNotificadasIds.contains(c.id)) continue;

        final dispDt = DateTime.tryParse(c.disparadaEm.trim())?.toUtc();
        final recemDisparada = dispDt == null ||
            (_sessionStartedAt != null && !dispDt.isBefore(_sessionStartedAt!)) ||
            agoraUtc.difference(dispDt).inHours <= 24;

        _campanhasNotificadasIds.add(c.id);
        salvouVistos = true;

        if (recemDisparada) {
          _adicionarNotificacao(
            titulo: c.titulo.isNotEmpty ? c.titulo : 'Nova Campanha OMNI',
            mensagem: c.mensagem,
            cupomAcao: c.codigoCupom.isNotEmpty ? c.codigoCupom : null,
          );
          unawaited(
            OmniPassengerNotificationService.exibirNotificacaoHeadsUp(
              titulo: c.titulo.isNotEmpty ? c.titulo : 'Promoção OMNI',
              mensagem: c.mensagem,
              cupomCodigo: c.codigoCupom,
              campaignId: c.id,
            ),
          );
        }
      }

      if (salvouVistos) {
        unawaited(
          _prefs?.setStringList(
            _keyCampanhasNotificadas,
            _campanhasNotificadasIds.toList(),
          ),
        );
      }
      notifyListeners();
    });
  }

  Future<void> _sincronizarDadosIniciaisSql() async {
    try {
      await OmniBackendUniversal.executar(OmniBackendMethods.bootstrapTables);
      final sqlRows = await OmniSqlService.obterHistoricoCorridas(_passageiro.id);
      if (sqlRows.isEmpty) return;

      final existentesIds = _historicoCorridas.map((h) => h.id).toSet();
      bool adicionou = false;

      for (final row in sqlRows) {
        final tripId = (row['trip_id'] ?? '').toString();
        if (tripId.isEmpty || existentesIds.contains(tripId)) continue;

        Map<String, dynamic> tripJson = {};
        final rawJson = row['trip_json'];
        if (rawJson is String && rawJson.isNotEmpty) {
          try {
            final parsed = jsonDecode(rawJson);
            if (parsed is Map) tripJson = Map<String, dynamic>.from(parsed);
          } catch (_) {}
        }

        final origMap = tripJson['origin'] ?? tripJson['origem'];
        final destMap = tripJson['destination'] ?? tripJson['destino'];
        final origAddr = origMap is Map ? (origMap['address'] ?? origMap['endereco'] ?? 'Origem').toString() : 'Origem';
        final destAddr = destMap is Map ? (destMap['address'] ?? destMap['endereco'] ?? 'Destino').toString() : 'Destino';
        final fare = double.tryParse((row['fare_amount'] ?? tripJson['estimated_fare'] ?? '0').toString()) ?? 0.0;
        final dist = (tripJson['distance_km'] as num?)?.toDouble() ??
            (tripJson['distancia_km'] as num?)?.toDouble() ??
            0.0;
        final cat = (tripJson['category'] ?? tripJson['categoria']?['nome'] ?? 'OMNI Pop').toString();
        final statusStr = (row['status'] ?? '').toString().toUpperCase();
        if (statusStr == OmniTripStatus.cancelled) continue;

        _historicoCorridas.add(
          OmniHistoricoCorrida(
            id: tripId,
            origem: origAddr,
            destino: destAddr,
            categoriaNome: cat,
            valorTotal: fare,
            gorjeta: 0.0,
            distanciaKm: dist,
            avaliacao: 5,
            pontosGanhos: math.max(10, fare.round()),
            concluidaEm: DateTime.tryParse((row['created_at'] ?? '').toString()) ?? DateTime.now(),
          ),
        );
        existentesIds.add(tripId);
        adicionou = true;
      }

      if (adicionou) {
        _historicoCorridas.sort((a, b) => b.concluidaEm.compareTo(a.concluidaEm));
        await _prefs?.setString(
          _keyHistorico,
          jsonEncode(_historicoCorridas.map((h) => h.toJson()).toList()),
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  void _carregarDadosLocais() {
    final pStr = _prefs?.getString(_keyPassageiro);
    if (pStr != null) {
      try {
        _passageiro = OmniPassageiroModel.fromJson(jsonDecode(pStr) as Map<String, dynamic>);
      } catch (_) {}
    }

    _enderecoCasa = _prefs?.getString(_keyCasa) ?? '';
    _enderecoTrabalho = _prefs?.getString(_keyTrabalho) ?? '';

    final cStr = _prefs?.getString(_keyCartoes);
    if (cStr != null) {
      try {
        final list = jsonDecode(cStr) as List;
        _cartoesSalvos = list.map((e) => OmniCartaoSalvo.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (_) {}
    }

    final hStr = _prefs?.getString(_keyHistorico);
    if (hStr != null) {
      try {
        final list = jsonDecode(hStr) as List;
        _historicoCorridas = list
            .map((e) => OmniHistoricoCorrida.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }

    final rStr = _prefs?.getString(_keyRecentes);
    if (rStr != null) {
      try {
        final list = jsonDecode(rStr) as List;
        _destinosRecentes = list
            .map((e) => OmniDestinoRecente.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }

    final pIds = _prefs?.getStringList(_keyPacotes);
    if (pIds != null) {
      _pacotesAtivosIds = pIds.toSet();
    }

    final notifiedIds = _prefs?.getStringList(_keyCampanhasNotificadas);
    if (notifiedIds != null) {
      _campanhasNotificadasIds.addAll(notifiedIds);
    }
  }

  Future<void> _salvarPassageiro() async {
    await _prefs?.setString(_keyPassageiro, jsonEncode(_passageiro.toJson()));
  }

  /// Captura real de localização em máxima precisão (bestForNavigation + Kalman 1D + 100% gratuito)
  Future<void> atualizarLocalizacaoGps({bool forceRefresh = false}) async {
    _gpsCarregando = true;
    _erroGps = null;
    notifyListeners();

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _gpsAtivo = false;
        _erroGps = 'Serviço de localização (GPS) desativado no aparelho.';
        _posicaoAtual = OmniCoordenada(
          lat: _posicaoAtual.lat,
          lng: _posicaoAtual.lng,
          endereco: 'Localização manual · Ative o GPS',
        );
      } else {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          _gpsAtivo = false;
          _erroGps = 'Permissão de GPS negada. Você pode digitar seu endereço de partida.';
          _posicaoAtual = OmniCoordenada(
            lat: _posicaoAtual.lat,
            lng: _posicaoAtual.lng,
            endereco: 'Digite seu endereço de partida',
          );
        } else {
          final posPrecisa = await OmniLocationService.capturarPosicaoFina(
            resolverEndereco: true,
            forceRefreshAddress: forceRefresh,
          );
          _gpsAtivo = true;
          _gpsPrecisaoMetros = posPrecisa.accuracyMeters;
          _precisaoReduzidaAlerta = posPrecisa.reducedAccuracyAlert;
          if (posPrecisa.cidade.isNotEmpty) {
            _cidadeAtual = posPrecisa.cidade;
          }
          final enderecoLegivel = posPrecisa.enderecoCompleto;
          _posicaoAtual = OmniCoordenada(
            lat: posPrecisa.lat,
            lng: posPrecisa.lng,
            endereco: (enderecoLegivel != null && enderecoLegivel.isNotEmpty)
                ? enderecoLegivel
                : 'GPS Atual (${posPrecisa.lat.toStringAsFixed(5)}, ${posPrecisa.lng.toStringAsFixed(5)})',
          );
          unawaited(
            OmniPassengerNotificationService.sincronizarTopicosPassageiro(
              passengerId: _passageiro.id,
              cidadeAtual: _cidadeAtual,
            ),
          );
        }
      }
    } catch (_) {
      _gpsAtivo = false;
      _erroGps = 'GPS indisponível neste ambiente. Digite seu endereço normalmente.';
      if (_posicaoAtual.endereco == 'Obtendo localização GPS...') {
        _posicaoAtual = OmniCoordenada(
          lat: _posicaoAtual.lat,
          lng: _posicaoAtual.lng,
          endereco: 'Localização atual (informe sua rua)',
        );
      }
    } finally {
      _gpsCarregando = false;
      notifyListeners();
    }
  }

  /// Ajuste fino do pino de partida no mapa com Debounce 800ms + deslocamento mínimo 10m
  void ajustarPinoOrigem(
    double deltaLat,
    double deltaLng, {
    void Function(OmniCoordenada novaPosicao)? onEnderecoResolvido,
  }) {
    final novaLat = _posicaoAtual.lat + deltaLat;
    final novaLng = _posicaoAtual.lng + deltaLng;
    _posicaoAtual = OmniCoordenada(
      lat: novaLat,
      lng: novaLng,
      endereco: _posicaoAtual.endereco,
    );
    notifyListeners();

    OmniLocationService.reverterComDebounce(novaLat, novaLng, (detalhado) {
      if (detalhado == null) return;
      _posicaoAtual = OmniCoordenada(
        lat: novaLat,
        lng: novaLng,
        endereco: detalhado.enderecoCompleto,
      );
      if (detalhado.cidade.isNotEmpty) {
        _cidadeAtual = detalhado.cidade;
      }
      notifyListeners();
      onEnderecoResolvido?.call(_posicaoAtual);
    });
  }

  /// Escuta motoristas reais no Firebase Realtime Database (`/drivers_online`)
  void _iniciarEscutaMotoristasRtdb() {
    _driversSub?.cancel();
    _driversSub = OmniFirebaseService.escutarMotoristasProximos().listen(
      (telemetriaList) {
        _rtdbConectado = true;
        _motoristasOnline = telemetriaList
            .where((t) => t.status != 'offline')
            .map((t) {
              final distKm = OmniMapasService.calcularDistanciaHaversine(
                _posicaoAtual,
                OmniCoordenada(lat: t.lat, lng: t.lng),
              );
              final etaMin = math.max(2, ((distKm / 25.0) * 60).round());
              return OmniMotoristaModel.fromTelemetria(t, distanciaMinutos: etaMin);
            })
            .toList();
        notifyListeners();
      },
      onError: (_) {
        _rtdbConectado = false;
        notifyListeners();
      },
    );
  }

  /// Calcula rota dinâmica utilizando as coordenadas reais selecionadas ou atuais
  OmniEstimativaRota calcularEstimativaDinamica({
    required String origemTexto,
    required String destinoTexto,
    List<String> paradasTextos = const [],
    OmniCoordenada? origemCoordenada,
    OmniCoordenada? destinoCoordenada,
    List<OmniCoordenada>? paradasCoordenadas,
  }) {
    final coordOrigem = origemCoordenada != null
        ? OmniCoordenada(
            lat: origemCoordenada.lat,
            lng: origemCoordenada.lng,
            endereco: origemTexto,
          )
        : OmniCoordenada(
            lat: _posicaoAtual.lat,
            lng: _posicaoAtual.lng,
            endereco: origemTexto,
          );

    final coordDestino = destinoCoordenada != null
        ? OmniCoordenada(
            lat: destinoCoordenada.lat,
            lng: destinoCoordenada.lng,
            endereco: destinoTexto,
          )
        : OmniCoordenada(
            lat: coordOrigem.lat,
            lng: coordOrigem.lng,
            endereco: destinoTexto,
          );

    final coordsParadas = <OmniCoordenada>[];
    for (int i = 0; i < paradasTextos.length; i++) {
      if (paradasCoordenadas != null && i < paradasCoordenadas.length) {
        coordsParadas.add(paradasCoordenadas[i]);
      }
    }

    return OmniMapasService.calcularRotaComParadas(
      origem: coordOrigem,
      destino: coordDestino,
      paradas: coordsParadas,
    );
  }

  /// Atualiza perfil real do passageiro (Local + MySQL `omni_passageiros`)
  Future<void> atualizarPerfil({
    required String nome,
    required String email,
    required String telefone,
    required String cpf,
  }) async {
    final cleanNome = nome.trim().isEmpty ? _passageiro.nome : nome.trim();
    final prefixo = cleanNome.split(' ').first.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    final codigo = prefixo.isEmpty
        ? _passageiro.codigoIndicacao
        : 'OMNI-$prefixo-${_passageiro.codigoIndicacao.split('-').last}';

    _passageiro = OmniPassageiroModel(
      id: _passageiro.id,
      nome: cleanNome,
      email: email.trim(),
      telefone: telefone.trim(),
      cpf: cpf.trim(),
      fotoUrl: _passageiro.fotoUrl,
      nivelFidelidade: nivelFidelidadeAtual.nome,
      saldoPontos: _passageiro.saldoPontos,
      codigoIndicacao: codigo,
      saldoCarteira: _passageiro.saldoCarteira,
      avaliacaoMedia: _passageiro.avaliacaoMedia,
    );
    await _salvarPassageiro();
    notifyListeners();

    unawaited(
      OmniBackendUniversal.executar(
        OmniBackendMethods.profileUpsert,
        args: {
          'passenger_id': _passageiro.id,
          'full_name': _passageiro.nome,
          'email': _passageiro.email,
          'phone': _passageiro.telefone,
          'cpf': _passageiro.cpf,
          'loyalty_tier': _passageiro.nivelFidelidade,
          'loyalty_points': _passageiro.saldoPontos,
          'wallet_balance': _passageiro.saldoCarteira,
          'profile_json': _passageiro.toJson(),
        },
      ),
    );
  }

  /// Salva endereços reais de Casa ou Trabalho (Local + MySQL `omni_passageiro_favoritos`)
  Future<void> salvarEnderecoFavorito({required bool ehCasa, required String endereco}) async {
    final limpo = endereco.trim();
    if (limpo.isEmpty) return;

    if (ehCasa) {
      _enderecoCasa = limpo;
      await _prefs?.setString(_keyCasa, limpo);
    } else {
      _enderecoTrabalho = limpo;
      await _prefs?.setString(_keyTrabalho, limpo);
    }
    notifyListeners();

    final coord = await OmniMapasService.geocodificarEnderecoPorTexto(
      query: limpo,
      latReferencia: _posicaoAtual.lat,
      lngReferencia: _posicaoAtual.lng,
    );
    await OmniSqlService.salvarLocalFavorito(
      passageiroId: _passageiro.id,
      rotulo: ehCasa ? 'Casa' : 'Trabalho',
      endereco: coord?.endereco ?? limpo,
      lat: coord?.lat ?? _posicaoAtual.lat,
      lng: coord?.lng ?? _posicaoAtual.lng,
    );
  }

  /// Cadastra cartão real (armazena apenas bandeira e últimos 4 dígitos por segurança PCI)
  Future<OmniCartaoSalvo> adicionarCartao({
    required String numeroCompleto,
    required String titular,
  }) async {
    final digitos = numeroCompleto.replaceAll(RegExp(r'\D'), '');
    final ultimos4 = digitos.length >= 4 ? digitos.substring(digitos.length - 4) : digitos.padLeft(4, '0');
    String bandeira = 'Cartão';
    if (digitos.startsWith('4')) {
      bandeira = 'Visa';
    } else if (digitos.startsWith('5')) {
      bandeira = 'Mastercard';
    } else if (digitos.startsWith('6') || digitos.startsWith('50')) {
      bandeira = 'Elo';
    }

    final novo = OmniCartaoSalvo(
      id: 'card_${DateTime.now().millisecondsSinceEpoch}',
      bandeira: bandeira,
      ultimos4: ultimos4,
      titular: titular.trim().isEmpty ? _passageiro.nome : titular.trim(),
    );
    _cartoesSalvos.insert(0, novo);
    await _prefs?.setString(_keyCartoes, jsonEncode(_cartoesSalvos.map((c) => c.toJson()).toList()));
    notifyListeners();
    return novo;
  }

  Future<void> removerCartao(String cardId) async {
    _cartoesSalvos.removeWhere((c) => c.id == cardId);
    await _prefs?.setString(_keyCartoes, jsonEncode(_cartoesSalvos.map((c) => c.toJson()).toList()));
    notifyListeners();
  }

  /// Adiciona crédito real à carteira OMNI Cash após confirmação Pix
  Future<void> creditarSaldoCarteira(double valor) async {
    _passageiro = OmniPassageiroModel(
      id: _passageiro.id,
      nome: _passageiro.nome,
      email: _passageiro.email,
      telefone: _passageiro.telefone,
      cpf: _passageiro.cpf,
      fotoUrl: _passageiro.fotoUrl,
      nivelFidelidade: nivelFidelidadeAtual.nome,
      saldoPontos: _passageiro.saldoPontos,
      codigoIndicacao: _passageiro.codigoIndicacao,
      saldoCarteira: double.parse((_passageiro.saldoCarteira + valor).toStringAsFixed(2)),
      avaliacaoMedia: _passageiro.avaliacaoMedia,
    );
    await _salvarPassageiro();
    _adicionarNotificacao(
      titulo: 'Recarga OMNI Cash confirmada',
      mensagem: 'R\$ ${valor.toStringAsFixed(2)} adicionados ao seu saldo disponível.',
    );
    notifyListeners();
  }

  /// Ativa pacote de viagens após confirmação Pix
  Future<void> ativarPacote(OmniPacoteModel pacote) async {
    _pacotesAtivosIds.add(pacote.id);
    await _prefs?.setStringList(_keyPacotes, _pacotesAtivosIds.toList());
    _adicionarNotificacao(
      titulo: '${pacote.titulo} ativado!',
      mensagem: '${pacote.totalViagens} viagens com ${pacote.porcentagemDesconto}% OFF válidas por ${pacote.validadeDias} dias.',
    );
    notifyListeners();
  }

  /// Registra um destino recente real pesquisado ou utilizado
  Future<void> registrarDestinoRecente(String endereco, double distanciaKm) async {
    final limpo = endereco.trim();
    if (limpo.isEmpty) return;
    _destinosRecentes.removeWhere((d) => d.titulo.toLowerCase() == limpo.toLowerCase());
    _destinosRecentes.insert(
      0,
      OmniDestinoRecente(
        titulo: limpo,
        subtitulo: 'Distância estimada: ${distanciaKm.toStringAsFixed(1)} km',
        distanciaKm: distanciaKm,
        precoAbaixoNormal: distanciaKm < 8.0,
      ),
    );
    if (_destinosRecentes.length > 8) {
      _destinosRecentes = _destinosRecentes.sublist(0, 8);
    }
    await _prefs?.setString(_keyRecentes, jsonEncode(_destinosRecentes.map((r) => r.toJson()).toList()));
    notifyListeners();
  }

  String _normalizarCodigoCategoria(String rawId) {
    final c = rawId.toLowerCase();
    if (c.contains('black')) return 'BLACK';
    if (c.contains('confort') || c.contains('comfort')) return 'COMFORT';
    if (c.contains('moto')) return 'MOTO';
    if (c.contains('envio') || c.contains('delivery')) return 'DELIVERY';
    return 'POP';
  }

  /// Inicia corrida 100% real: geocodifica endereços ausentes, calcula rota OSRM real,
  /// grava em SQL + `/trips/{trip_id}` + `/dispatch_queue/{driver_id}/{trip_id}` e escuta motorista real no RTDB.
  Future<OmniCorridaModel> iniciarCorrida({
    required String origemEndereco,
    required String destinoEndereco,
    required List<String> paradas,
    OmniCoordenada? origemCoordenada,
    OmniCoordenada? destinoCoordenada,
    List<OmniCoordenada>? paradasCoordenadas,
    required OmniCategoriaModel categoria,
    required double valorFinal,
    required String metodoPagamento,
    required String perfilPagamento,
    required bool usarSaldoCarteira,
    String? cupomAplicado,
    double descontoPercentual = 0.0,
    double descontoValorFixo = 0.0,
    required OmniPreferenciasViagem preferencias,
    OmniAgendamentoCorrida? agendamento,
    OmniPassageiroTerceiro? passageiroTerceiro,
    required double distanciaKm,
    required int tempoMinutos,
    String routeProvider = 'haversine_viario',
    OmniPixResumo? pixCobranca,
  }) async {
    final otpSeguro = (1000 + math.Random.secure().nextInt(9000)).toString();
    final rideId = 'rid_omni_${DateTime.now().millisecondsSinceEpoch}';

    OmniCoordenada coordOrigem = origemCoordenada != null
        ? OmniCoordenada(
            lat: origemCoordenada.lat,
            lng: origemCoordenada.lng,
            endereco: origemEndereco,
          )
        : (await OmniMapasService.geocodificarEnderecoPorTexto(
              query: origemEndereco,
              latReferencia: _posicaoAtual.lat,
              lngReferencia: _posicaoAtual.lng,
            ) ??
            OmniCoordenada(
              lat: _posicaoAtual.lat,
              lng: _posicaoAtual.lng,
              endereco: origemEndereco,
            ));

    OmniCoordenada coordDestino = destinoCoordenada != null
        ? OmniCoordenada(
            lat: destinoCoordenada.lat,
            lng: destinoCoordenada.lng,
            endereco: destinoEndereco,
          )
        : (await OmniMapasService.geocodificarEnderecoPorTexto(
              query: destinoEndereco,
              latReferencia: coordOrigem.lat,
              lngReferencia: coordOrigem.lng,
            ) ??
            OmniCoordenada(
              lat: coordOrigem.lat,
              lng: coordOrigem.lng,
              endereco: destinoEndereco,
            ));

    final coordsParadas = <OmniCoordenada>[];
    for (int i = 0; i < paradas.length; i++) {
      final pText = paradas[i].trim();
      if (pText.isEmpty) continue;
      if (paradasCoordenadas != null && i < paradasCoordenadas.length) {
        coordsParadas.add(
          OmniCoordenada(
            lat: paradasCoordenadas[i].lat,
            lng: paradasCoordenadas[i].lng,
            endereco: pText,
          ),
        );
      } else {
        final geoParada = await OmniMapasService.geocodificarEnderecoPorTexto(
          query: pText,
          latReferencia: coordOrigem.lat,
          lngReferencia: coordOrigem.lng,
        );
        coordsParadas.add(
          geoParada ?? OmniCoordenada(lat: coordOrigem.lat, lng: coordOrigem.lng, endereco: pText),
        );
      }
    }

    // Recalcula rota OSRM caso destino tenha acabado de ser geocodificado
    double kmEfetivo = distanciaKm;
    int minEfetivo = tempoMinutos;
    double valorEfetivo = valorFinal;
    String providerEfetivo = routeProvider;

    if (destinoCoordenada == null &&
        (coordDestino.lat != coordOrigem.lat || coordDestino.lng != coordOrigem.lng)) {
      final rotaReal = await OmniMapasService.calcularRotaRealComParadas(
        origem: coordOrigem,
        destino: coordDestino,
        paradas: coordsParadas,
      );
      kmEfetivo = rotaReal.distanciaKm;
      minEfetivo = rotaReal.duracaoMinutos;
      providerEfetivo = rotaReal.routeProvider;
      valorEfetivo = categoria.calcularValorEstimado(
        km: kmEfetivo,
        minutos: minEfetivo,
        paradasCount: coordsParadas.length,
        descontoPercentual: descontoPercentual,
        descontoValorFixo: descontoValorFixo,
      );
    }

    final novaCorrida = OmniCorridaModel(
      id: rideId,
      passageiroId: _passageiro.id,
      origem: coordOrigem,
      destino: coordDestino,
      paradas: coordsParadas,
      categoria: categoria,
      valorEstimado: valorEfetivo,
      metodoPagamento: metodoPagamento,
      perfilPagamento: perfilPagamento,
      usarSaldoCarteira: usarSaldoCarteira,
      cupomAplicado: cupomAplicado,
      descontoPercentual: descontoPercentual,
      descontoValorFixo: descontoValorFixo,
      preferencias: preferencias,
      agendamento: agendamento,
      passageiroTerceiro: passageiroTerceiro,
      status: OmniStatusCorrida.buscandoMotorista,
      otpEmbarque: otpSeguro,
      distanciaKm: kmEfetivo,
      tempoMinutos: minEfetivo,
      criadoEm: DateTime.now(),
      pixCobranca: pixCobranca,
    );

    _corridaAtiva = novaCorrida;
    _mensagensChat.clear();
    _chatPushIdsVistos.clear();
    notifyListeners();

    await registrarDestinoRecente(destinoEndereco, kmEfetivo);

    // Debita saldo da carteira caso o usuário tenha ativado OMNI Cash
    if (usarSaldoCarteira && _passageiro.saldoCarteira > 0) {
      final abatido = math.min(_passageiro.saldoCarteira, valorEfetivo);
      _passageiro = OmniPassageiroModel(
        id: _passageiro.id,
        nome: _passageiro.nome,
        email: _passageiro.email,
        telefone: _passageiro.telefone,
        cpf: _passageiro.cpf,
        fotoUrl: _passageiro.fotoUrl,
        nivelFidelidade: nivelFidelidadeAtual.nome,
        saldoPontos: _passageiro.saldoPontos,
        codigoIndicacao: _passageiro.codigoIndicacao,
        saldoCarteira: double.parse((_passageiro.saldoCarteira - abatido).toStringAsFixed(2)),
        avaliacaoMedia: _passageiro.avaliacaoMedia,
      );
      await _salvarPassageiro();
    }

    final catCode = _normalizarCodigoCategoria(categoria.id);
    final tripType = categoria.ehEnvio ? 'DELIVERY' : 'PASSENGER';
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final tripPayload = <String, dynamic>{
      ...novaCorrida.toJson(),
      OmniRtdbFields.tripId: rideId,
      OmniRtdbFields.status: OmniTripStatus.searching,
      OmniRtdbFields.passengerId: _passageiro.id,
      OmniRtdbFields.passengerName: _passageiro.nome,
      OmniRtdbFields.passengerRating: _passageiro.avaliacaoMedia,
      OmniRtdbFields.tripType: tripType,
      OmniRtdbFields.category: catCode,
      OmniRtdbFields.estimatedFare: valorEfetivo,
      OmniRtdbFields.distanceKm: kmEfetivo,
      OmniRtdbFields.etaMinutes: minEfetivo,
      OmniRtdbFields.otpCode: novaCorrida.otpEmbarque,
      OmniRtdbFields.origin: {
        OmniRtdbFields.address: origemEndereco,
        OmniRtdbFields.lat: novaCorrida.origem.lat,
        OmniRtdbFields.lng: novaCorrida.origem.lng,
      },
      OmniRtdbFields.destination: {
        OmniRtdbFields.address: destinoEndereco,
        OmniRtdbFields.lat: novaCorrida.destino.lat,
        OmniRtdbFields.lng: novaCorrida.destino.lng,
      },
      if (coordsParadas.isNotEmpty)
        OmniRtdbFields.waypoints: coordsParadas
            .map((p) => {
                  OmniRtdbFields.address: p.endereco ?? '',
                  OmniRtdbFields.lat: p.lat,
                  OmniRtdbFields.lng: p.lng,
                })
            .toList(),
      OmniRtdbFields.routeProvider: providerEfetivo,
      OmniRtdbFields.createdAt: nowIso,
    };

    // 1. Grava estado e snapshot completo imediatamente em `/trips/{trip_id}` no Firebase RTDB
    await OmniFirebaseService.registrarDadosCorridaRtdb(rideId, tripPayload);

    // 2. Inicia escuta em tempo real de `/trips/{trip_id}` e `/trips/{trip_id}/chat`
    _escutarCorridaAtivaRtdb(rideId);

    // 3. Despacha para o Backend PHP -> SQL `omni_corridas` + `/dispatch_queue`
    final resp = await OmniBackendUniversal.executar(
      OmniBackendMethods.tripRequest,
      args: {'trip': tripPayload},
      chaveIdempotencia: rideId,
    );

    final dispatchedByPhp = (resp.sucesso &&
            resp.dados is Map &&
            resp.dados['dispatched_drivers'] is List &&
            (resp.dados['dispatched_drivers'] as List).isNotEmpty);

    // Se o backend PHP não alcançou ou retornou lista vazia, despacha diretamente para motoristas em `/drivers_online`
    if (!dispatchedByPhp && _motoristasOnline.isNotEmpty) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final offerPayload = <String, dynamic>{
        OmniRtdbFields.tripId: rideId,
        OmniRtdbFields.passengerId: _passageiro.id,
        OmniRtdbFields.passengerName: _passageiro.nome,
        OmniRtdbFields.passengerRating: _passageiro.avaliacaoMedia,
        OmniRtdbFields.tripType: tripType,
        OmniRtdbFields.category: catCode,
        OmniRtdbFields.estimatedFare: valorEfetivo,
        OmniRtdbFields.distanceKm: kmEfetivo,
        OmniRtdbFields.etaMinutes: minEfetivo,
        OmniRtdbFields.otpCode: novaCorrida.otpEmbarque,
        OmniRtdbFields.origin: tripPayload[OmniRtdbFields.origin],
        OmniRtdbFields.destination: tripPayload[OmniRtdbFields.destination],
        if (coordsParadas.isNotEmpty) OmniRtdbFields.waypoints: tripPayload[OmniRtdbFields.waypoints],
        OmniRtdbFields.routeProvider: providerEfetivo,
        OmniRtdbFields.createdAt: nowIso,
        OmniRtdbFields.expiresAt: nowMs + 30000,
      };
      for (final drv in _motoristasOnline) {
        unawaited(
          OmniFirebaseService.enviarOfertaDespacho(
            driverId: drv.id,
            tripId: rideId,
            offerPayload: offerPayload,
          ),
        );
      }
    }

    // Se o backend já retornou driver vinculado na resposta imediata:
    if (resp.sucesso && resp.dados is Map && resp.dados['motorista'] is Map) {
      final drv = OmniMotoristaModel.fromJson(Map<String, dynamic>.from(resp.dados['motorista']));
      _corridaAtiva = _corridaAtiva?.copyWith(
        motorista: drv,
        status: OmniStatusCorrida.aceita,
      );
      notifyListeners();
    }

    return _corridaAtiva ?? novaCorrida;
  }

  OmniStatusCorrida? _mapearStatusCanonicoRtdb(String raw) {
    switch (raw.toUpperCase()) {
      case OmniTripStatus.searching:
        return OmniStatusCorrida.buscandoMotorista;
      case OmniTripStatus.accepted:
        return OmniStatusCorrida.aceita;
      case OmniTripStatus.driverEnRoute:
        return OmniStatusCorrida.aCaminhoEmbarque;
      case OmniTripStatus.driverArrived:
      case OmniTripStatus.boardingConfirmed:
        return OmniStatusCorrida.aguardandoPassageiro;
      case OmniTripStatus.inProgress:
        return OmniStatusCorrida.emAndamento;
      case OmniTripStatus.completed:
        return OmniStatusCorrida.concluida;
      case OmniTripStatus.cancelled:
        return OmniStatusCorrida.canceladaPassageiro;
      case OmniTripStatus.declined:
        return OmniStatusCorrida.canceladaMotorista;
      default:
        final match = OmniStatusCorrida.values.where((s) => s.name == raw);
        return match.isNotEmpty ? match.first : null;
    }
  }

  Future<void> _aplicarSnapshotCorridaRtdb(String rideId, Map<String, dynamic>? dados) async {
    if (dados == null || _corridaAtiva?.id != rideId) return;

    bool mudou = false;

    // 1. Atualiza status canônico (`/trips/{trip_id}/status`)
    final statusStr = dados[OmniRtdbFields.status]?.toString();
    if (statusStr != null) {
      final mapped = _mapearStatusCanonicoRtdb(statusStr);
      if (mapped != null && mapped != _corridaAtiva!.status) {
        _corridaAtiva = _corridaAtiva!.copyWith(status: mapped);
        mudou = true;
        if (mapped == OmniStatusCorrida.aguardandoPassageiro) {
          _adicionarNotificacao(
            titulo: 'Motorista chegou ao embarque',
            mensagem: 'Informe seu OTP ${_corridaAtiva!.otpEmbarque} ao entrar no veículo.',
          );
        }
      }
    }

    // 2. Vincula motorista real quando App Motorista grava `/trips/{trip_id}/driver_id`
    final drvId = dados[OmniRtdbFields.driverId]?.toString();
    if (drvId != null && drvId.isNotEmpty && _corridaAtiva?.motorista?.id != drvId) {
      final onlineMatch = _motoristasOnline.where((m) => m.id == drvId).toList();
      final telemetria = onlineMatch.isEmpty
          ? await OmniFirebaseService.obterTelemetriaMotorista(drvId)
          : null;
      final infoSql = await OmniSqlService.obterDadosPublicosMotorista(drvId);

      if (_corridaAtiva?.id == rideId) {
        final d = infoSql?['driver'] is Map
            ? Map<String, dynamic>.from(infoSql!['driver'])
            : <String, dynamic>{};
        final v = infoSql?['vehicle'] is Map
            ? Map<String, dynamic>.from(infoSql!['vehicle'])
            : <String, dynamic>{};

        final fallbackOnline = onlineMatch.isNotEmpty ? onlineMatch.first : null;
        final nomeMotorista = (d['full_name'] ??
                dados['driver_name'] ??
                telemetria?.nome ??
                fallbackOnline?.nome ??
                'Motorista OMNI')
            .toString();
        final modelo = ('${v['brand'] ?? ''} ${v['model'] ?? ''}'.trim().isNotEmpty)
            ? '${v['brand'] ?? ''} ${v['model'] ?? ''}'.trim()
            : (dados['vehicle_model'] ??
                    telemetria?.modeloVeiculo ??
                    fallbackOnline?.modeloVeiculo ??
                    'Veículo OMNI')
                .toString();
        final placa = (v['plate'] ??
                dados['plate'] ??
                telemetria?.placa ??
                fallbackOnline?.placaVeiculo ??
                '---')
            .toString();
        final telefone = (d['phone'] ?? dados['driver_phone'] ?? fallbackOnline?.telefone ?? '').toString();
        final drvLat = (d['lat'] as num?)?.toDouble() ??
            telemetria?.lat ??
            fallbackOnline?.lat ??
            _posicaoAtual.lat;
        final drvLng = (d['lng'] as num?)?.toDouble() ??
            telemetria?.lng ??
            fallbackOnline?.lng ??
            _posicaoAtual.lng;

        final distPickup = OmniMapasService.calcularDistanciaHaversine(
          _posicaoAtual,
          OmniCoordenada(lat: drvLat, lng: drvLng),
        );
        final etaPickup = math.max(1, ((distPickup / 25.0) * 60).round());

        final drvModel = OmniMotoristaModel(
          id: drvId,
          nome: nomeMotorista,
          telefone: telefone,
          avaliacao: telemetria?.avaliacao ?? fallbackOnline?.avaliacao ?? 4.95,
          totalViagens: fallbackOnline?.totalViagens ?? 120,
          modeloVeiculo: modelo,
          corVeiculo: (v['color'] ?? fallbackOnline?.corVeiculo ?? 'Preto').toString(),
          placaVeiculo: placa,
          categoria: (v['category'] ?? _corridaAtiva!.categoria.id).toString(),
          lat: drvLat,
          lng: drvLng,
          distanciaMinutos: etaPickup,
        );

        _corridaAtiva = _corridaAtiva!.copyWith(
          motorista: drvModel,
          status: _corridaAtiva!.status == OmniStatusCorrida.buscandoMotorista
              ? OmniStatusCorrida.aceita
              : _corridaAtiva!.status,
        );
        mudou = true;
      }
    }

    // 3. Atualiza posição em tempo real (`/trips/{trip_id}/driver_location`) com Snap-to-Road gratuito OSRM Nearest + bearing
    final drvLoc = dados[OmniRtdbFields.driverLocation];
    if (drvLoc is Map && _corridaAtiva?.motorista != null) {
      final rawLat = (drvLoc[OmniRtdbFields.lat] as num?)?.toDouble();
      final rawLng = (drvLoc[OmniRtdbFields.lng] as num?)?.toDouble();
      final bearing = (drvLoc[OmniRtdbFields.bearing] as num?)?.toDouble();
      if (rawLat != null && rawLng != null) {
        final snapped = await OmniLocationService.alinharViaOsrmNearest(
          rawLat,
          rawLng,
          headingDeg: bearing,
        );
        if (_corridaAtiva?.id == rideId && _corridaAtiva?.motorista != null) {
          final m = _corridaAtiva!.motorista!;
          final distPickup = OmniMapasService.calcularDistanciaHaversine(
            _corridaAtiva!.origem,
            OmniCoordenada(lat: snapped.lat, lng: snapped.lng),
          );
          final etaPickup = math.max(1, ((distPickup / 25.0) * 60).round());
          _corridaAtiva = _corridaAtiva!.copyWith(
            motorista: OmniMotoristaModel(
              id: m.id,
              nome: m.nome,
              fotoUrl: m.fotoUrl,
              telefone: m.telefone,
              avaliacao: m.avaliacao,
              totalViagens: m.totalViagens,
              modeloVeiculo: m.modeloVeiculo,
              corVeiculo: m.corVeiculo,
              placaVeiculo: m.placaVeiculo,
              categoria: m.categoria,
              lat: snapped.lat,
              lng: snapped.lng,
              distanciaMinutos: etaPickup,
            ),
          );
          mudou = true;
        }
      }
    }

    if (mudou) notifyListeners();
  }

  void _escutarCorridaAtivaRtdb(String rideId) {
    _activeRideSub?.cancel();
    _chatSub?.cancel();

    _activeRideSub = OmniFirebaseService.escutarCorridaAtiva(rideId).listen((dados) async {
      _rtdbConectado = true;
      await _aplicarSnapshotCorridaRtdb(rideId, dados);
    });

    // 4. Escuta mensagens em tempo real (bidirecional motorista <-> passageiro) em `/trips/{trip_id}/chat`
    _chatSub = OmniFirebaseService.escutarChatCorrida(rideId).listen((msg) {
      if (_corridaAtiva?.id != rideId || msg.isEmpty) return;
      final pushId = msg['push_id']?.toString();
      if (pushId != null && _chatPushIdsVistos.contains(pushId)) return;

      final role = (msg[OmniRtdbFields.senderRole] ?? '').toString().toLowerCase();
      final text = (msg[OmniRtdbFields.text] ?? '').toString().trim();
      if (text.isEmpty) return;

      final isPassengerMsg = role == 'passenger' || role == 'passageiro';
      final createdMs = (msg[OmniRtdbFields.createdAt] as num?)?.toInt();
      final dt = createdMs != null
          ? DateTime.fromMillisecondsSinceEpoch(createdMs)
          : DateTime.now();

      if (pushId != null) {
        _chatPushIdsVistos.add(pushId);
      }

      if (isPassengerMsg) {
        // Reconcilia eventual envio otimista local sem duplicar bolha
        final optIdx = _mensagensChat.indexWhere(
          (m) => m.id == null && m.autor == 'passageiro' && m.texto == text,
        );
        if (optIdx >= 0) {
          _mensagensChat[optIdx] = _mensagensChat[optIdx].copyWith(id: pushId);
          return;
        }
      }

      _mensagensChat.add(
        OmniMensagemChat(
          id: pushId,
          autor: isPassengerMsg ? 'passageiro' : 'motorista',
          texto: text,
          enviadaEm: dt,
          lida: msg[OmniRtdbFields.isRead] == true,
        ),
      );
      _mensagensChat.sort((a, b) => a.enviadaEm.compareTo(b.enviadaEm));
      notifyListeners();
    });
  }

  /// Sincroniza imediatamente com o Firebase RTDB (substitui qualquer avanço simulado local)
  Future<void> sincronizarCorridaRtdb() async {
    final id = _corridaAtiva?.id;
    if (id == null) return;
    final snap = await OmniFirebaseService.obterSnapshotCorrida(id);
    if (snap != null) {
      _rtdbConectado = true;
      await _aplicarSnapshotCorridaRtdb(id, snap);
    }
  }

  /// Alias mantido para compatibilidade de assinatura nos widgets: executa sincronia real no RTDB
  void avancarStatusCorrida() {
    unawaited(sincronizarCorridaRtdb());
  }

  /// Marca mensagens do motorista como lidas no estado e no RTDB
  Future<void> marcarChatMotoristaComoLido() async {
    final tripId = _corridaAtiva?.id;
    final idsParaMarcar = <String>[];
    bool mudou = false;

    for (int i = 0; i < _mensagensChat.length; i++) {
      final m = _mensagensChat[i];
      if (m.autor == 'motorista' && !m.lida) {
        _mensagensChat[i] = m.copyWith(lida: true);
        if (m.id != null && m.id!.isNotEmpty) {
          idsParaMarcar.add(m.id!);
        }
        mudou = true;
      }
    }

    if (mudou) notifyListeners();
    if (tripId != null && idsParaMarcar.isNotEmpty) {
      await OmniFirebaseService.marcarMensagensChatLidas(tripId, idsParaMarcar);
    }
  }

  /// Altera destino durante a viagem com geocodificação real, recálculo OSRM e espelhamento no RTDB
  Future<void> alterarDestinoEmViagem(String novoDestino) async {
    final corrida = _corridaAtiva;
    final limpo = novoDestino.trim();
    if (corrida == null || limpo.isEmpty) return;

    final coordDestino = (await OmniMapasService.geocodificarEnderecoPorTexto(
          query: limpo,
          latReferencia: corrida.origem.lat,
          lngReferencia: corrida.origem.lng,
        )) ??
        OmniCoordenada(lat: corrida.destino.lat, lng: corrida.destino.lng, endereco: limpo);

    final estimativa = await OmniMapasService.calcularRotaRealComParadas(
      origem: corrida.origem,
      destino: coordDestino,
      paradas: corrida.paradas,
    );

    final novoValor = corrida.categoria.calcularValorEstimado(
      km: estimativa.distanciaKm,
      minutos: estimativa.duracaoMinutos,
      paradasCount: corrida.paradas.length,
      descontoPercentual: corrida.descontoPercentual,
      descontoValorFixo: corrida.descontoValorFixo,
    );

    if (_corridaAtiva?.id != corrida.id) return;
    _corridaAtiva = _corridaAtiva!.copyWith(
      destino: OmniCoordenada(
        lat: coordDestino.lat,
        lng: coordDestino.lng,
        endereco: limpo,
      ),
      distanciaKm: estimativa.distanciaKm,
      tempoMinutos: estimativa.duracaoMinutos,
      valorFinal: novoValor,
    );
    notifyListeners();

    await OmniFirebaseService.registrarDadosCorridaRtdb(corrida.id, {
      OmniRtdbFields.destination: {
        OmniRtdbFields.address: limpo,
        OmniRtdbFields.lat: coordDestino.lat,
        OmniRtdbFields.lng: coordDestino.lng,
      },
      OmniRtdbFields.distanceKm: estimativa.distanciaKm,
      OmniRtdbFields.etaMinutes: estimativa.duracaoMinutos,
      OmniRtdbFields.estimatedFare: novoValor,
      OmniRtdbFields.routeProvider: estimativa.routeProvider,
    });
  }

  /// Envia mensagem no chat em tempo real em `/trips/{trip_id}/chat`
  Future<void> enviarMensagemChat(String texto) async {
    final limpo = texto.trim();
    final tripId = _corridaAtiva?.id;
    if (limpo.isEmpty || tripId == null) return;

    final otimista = OmniMensagemChat(
      autor: 'passageiro',
      texto: limpo,
      enviadaEm: DateTime.now(),
      lida: false,
    );
    _mensagensChat.add(otimista);
    notifyListeners();

    final pushId = await OmniFirebaseService.enviarMensagemChat(
      tripId: tripId,
      senderId: _passageiro.id,
      text: limpo,
    );

    if (pushId != null) {
      _chatPushIdsVistos.add(pushId);
      final idx = _mensagensChat.indexOf(otimista);
      if (idx >= 0) {
        _mensagensChat[idx] = otimista.copyWith(id: pushId);
        notifyListeners();
      }
    }
  }

  /// Aciona alerta SOS de emergência (RTDB `/trips/{trip_id}/sos` + Backend PHP)
  Future<void> acionarSosCorrida() async {
    final corrida = _corridaAtiva;
    final tripId = corrida?.id ?? '';
    final driverId = corrida?.motorista?.id ?? '';
    if (tripId.isNotEmpty) {
      await OmniFirebaseService.enviarAlertaSos(
        tripId: tripId,
        passengerId: _passageiro.id,
        driverId: driverId,
        lat: _posicaoAtual.lat,
        lng: _posicaoAtual.lng,
      );
    }
    await OmniBackendUniversal.executar(
      OmniBackendMethods.tripSos,
      args: {
        'trip_id': tripId,
        'passenger_id': _passageiro.id,
        'driver_id': driverId,
        'lat': _posicaoAtual.lat,
        'lng': _posicaoAtual.lng,
      },
    );
  }

  /// Cancela corrida ativa, atualiza `/trips/{trip_id}/status = "CANCELLED"` e notifica backend PHP
  Future<void> cancelarCorridaAtiva() async {
    final id = _corridaAtiva?.id;
    _activeRideSub?.cancel();
    _chatSub?.cancel();
    _corridaAtiva = null;
    _mensagensChat.clear();
    _chatPushIdsVistos.clear();
    notifyListeners();

    if (id != null) {
      await OmniFirebaseService.atualizarStatusCorrida(id, OmniTripStatus.cancelled);
      await OmniBackendUniversal.executar(
        OmniBackendMethods.tripCancel,
        args: {'trip_id': id, 'motivo': 'cancelada_passageiro'},
      );
    }
  }

  /// Conclui a corrida, grava no histórico real, credita pontos proporcionais e atualiza perfil SQL
  Future<int> finalizarCorridaComAvaliacao({
    required int estrelas,
    required double gorjeta,
    required List<String> elogios,
  }) async {
    final corrida = _corridaAtiva;
    if (corrida == null) return 0;

    final valorBase = corrida.valorFinal ?? corrida.valorEstimado;
    final totalPago = double.parse((valorBase + gorjeta).toStringAsFixed(2));
    final cashbackRate = nivelFidelidadeAtual.cashbackPorCorrida;
    final pontosGanhos = math.max(10, (totalPago * (1 + cashbackRate * 10)).round());

    final registro = OmniHistoricoCorrida(
      id: corrida.id,
      origem: corrida.origem.endereco ?? 'Origem',
      destino: corrida.destino.endereco ?? 'Destino',
      categoriaNome: corrida.categoria.nome,
      valorTotal: totalPago,
      gorjeta: gorjeta,
      distanciaKm: corrida.distanciaKm,
      avaliacao: estrelas,
      pontosGanhos: pontosGanhos,
      concluidaEm: DateTime.now(),
    );

    _historicoCorridas.insert(0, registro);
    await _prefs?.setString(
      _keyHistorico,
      jsonEncode(_historicoCorridas.map((h) => h.toJson()).toList()),
    );

    final novosPontos = _passageiro.saldoPontos + pontosGanhos;
    _passageiro = OmniPassageiroModel(
      id: _passageiro.id,
      nome: _passageiro.nome,
      email: _passageiro.email,
      telefone: _passageiro.telefone,
      cpf: _passageiro.cpf,
      fotoUrl: _passageiro.fotoUrl,
      nivelFidelidade: _calcularNomeNivel(novosPontos),
      saldoPontos: novosPontos,
      codigoIndicacao: _passageiro.codigoIndicacao,
      saldoCarteira: _passageiro.saldoCarteira,
      avaliacaoMedia: _passageiro.avaliacaoMedia,
    );
    await _salvarPassageiro();

    _adicionarNotificacao(
      titulo: 'Recibo disponível · +$pontosGanhos pts',
      mensagem: '${corrida.categoria.nome} para ${corrida.destino.endereco ?? "destino"} · Total R\$ ${totalPago.toStringAsFixed(2)}.',
    );

    await OmniBackendUniversal.executar(
      OmniBackendMethods.tripRate,
      args: {
        'trip_id': corrida.id,
        'passenger_id': _passageiro.id,
        'driver_id': corrida.motorista?.id ?? '',
        'estrelas': estrelas,
        'gorjeta': gorjeta,
        'elogios': elogios,
      },
    );

    unawaited(
      OmniBackendUniversal.executar(
        OmniBackendMethods.profileUpsert,
        args: {
          'passenger_id': _passageiro.id,
          'full_name': _passageiro.nome,
          'email': _passageiro.email,
          'phone': _passageiro.telefone,
          'cpf': _passageiro.cpf,
          'loyalty_tier': _passageiro.nivelFidelidade,
          'loyalty_points': _passageiro.saldoPontos,
          'wallet_balance': _passageiro.saldoCarteira,
          'profile_json': _passageiro.toJson(),
        },
      ),
    );

    _activeRideSub?.cancel();
    _chatSub?.cancel();
    _corridaAtiva = null;
    _mensagensChat.clear();
    _chatPushIdsVistos.clear();
    notifyListeners();
    return pontosGanhos;
  }

  String _calcularNomeNivel(int pontos) {
    String nome = OmniNivelFidelidade.niveis.first.nome;
    for (final niv in OmniNivelFidelidade.niveis) {
      if (pontos >= niv.pontosNecessarios) nome = niv.nome;
    }
    return nome;
  }

  /// Registra protocolo real de item esquecido ou suporte
  Future<void> registrarProtocoloSuporte(String assunto, String detalhes) async {
    await OmniBackendUniversal.executar(
      OmniBackendMethods.supportOpenTicket,
      args: {
        'passageiro_id': _passageiro.id,
        'assunto': assunto,
        'detalhes': detalhes,
        'trip_id': _corridaAtiva?.id ?? '',
      },
    );
    _adicionarNotificacao(
      titulo: 'Protocolo OMNI aberto',
      mensagem: '$assunto — Nossa equipe está analisando seu chamado.',
    );
    notifyListeners();
  }

  void _adicionarNotificacao({
    required String titulo,
    required String mensagem,
    String? cupomAcao,
  }) {
    _notificacoes.insert(
      0,
      OmniNotificacao(
        id: 'notif_${DateTime.now().millisecondsSinceEpoch}',
        titulo: titulo,
        mensagem: mensagem,
        criadaEm: DateTime.now(),
        cupomAcao: cupomAcao,
      ),
    );
  }

  void marcarTodasNotificacoesLidas() {
    for (int i = 0; i < _notificacoes.length; i++) {
      _notificacoes[i] = _notificacoes[i].copyWith(lida: true);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _driversSub?.cancel();
    _campanhasSub?.cancel();
    _activeRideSub?.cancel();
    _chatSub?.cancel();
    super.dispose();
  }
}
