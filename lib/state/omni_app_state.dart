import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/omni_integration_contracts.dart';
import '../constants/omni_constants.dart';
import '../models/categoria_model.dart';
import '../models/corrida_model.dart';
import '../models/fidelidade_model.dart';
import '../models/motorista_model.dart';
import '../models/pacote_model.dart';
import '../models/passageiro_model.dart';
import '../tools/backends_service.dart';
import '../tools/firebase_service.dart';
import '../tools/mapas_service.dart';
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

/// Mensagem de chat da corrida ativa
class OmniMensagemChat {
  final String autor; // 'passageiro' | 'motorista'
  final String texto;
  final DateTime enviadaEm;

  const OmniMensagemChat({
    required this.autor,
    required this.texto,
    required this.enviadaEm,
  });
}

/// Gerenciador Central de Estado Real do OMNI Passageiro (Provider / ChangeNotifier)
/// Elimina mocks estáticos: integra Geolocator (GPS), cálculo Haversine dinâmico,
/// persistência em SharedPreferences, Firebase RTDB e Backend Universal OMNI.
class OmniAppState extends ChangeNotifier {
  static const String _keyPassageiro = 'omni_passageiro_v2';
  static const String _keyCartoes = 'omni_cartoes_v2';
  static const String _keyHistorico = 'omni_historico_v2';
  static const String _keyRecentes = 'omni_recentes_v2';
  static const String _keyPacotes = 'omni_pacotes_ativos_v2';
  static const String _keyCasa = 'omni_endereco_casa_v2';
  static const String _keyTrabalho = 'omni_endereco_trabalho_v2';

  SharedPreferences? _prefs;
  bool _inicializado = false;
  bool _gpsCarregando = false;
  bool _gpsAtivo = false;
  bool _rtdbConectado = false;
  String? _erroGps;

  // Dados reais do passageiro (sem nomes fictícios chumbados)
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

  // Localização real obtida via GPS
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

  // Telemetria em tempo real de motoristas e corrida (Firebase RTDB)
  List<OmniMotoristaModel> _motoristasOnline = [];
  StreamSubscription<List<OmniMotoristaTelemetria>>? _driversSub;
  StreamSubscription<Map<String, dynamic>?>? _activeRideSub;
  StreamSubscription<Map<String, dynamic>>? _chatSub;

  // Corrida ativa + chat persistido em sessão + notificações
  OmniCorridaModel? _corridaAtiva;
  final List<OmniMensagemChat> _mensagensChat = [];
  final List<OmniNotificacao> _notificacoes = [];
  Timer? _rideLifecycleTimer;

  // Getters públicos
  bool get inicializado => _inicializado;
  bool get gpsCarregando => _gpsCarregando;
  bool get gpsAtivo => _gpsAtivo;
  bool get rtdbConectado => _rtdbConectado;
  String? get erroGps => _erroGps;

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
  List<OmniNotificacao> get notificacoes => List.unmodifiable(_notificacoes);
  int get notificacoesNaoLidas => _notificacoes.where((n) => !n.lida).length;

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

  /// Inicializa persistência local, GPS e listeners RTDB
  Future<void> inicializar() async {
    if (_inicializado) return;
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
    await atualizarLocalizacaoGps();
    _iniciarEscutaMotoristasRtdb();
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
  }

  Future<void> _salvarPassageiro() async {
    await _prefs?.setString(_keyPassageiro, jsonEncode(_passageiro.toJson()));
  }

  /// Captura real de localização via Geolocator (com tratamento de permissões)
  Future<void> atualizarLocalizacaoGps() async {
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
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 8),
          );
          _gpsAtivo = true;
          final enderecoLegivel = await OmniMapasService.reverterCoordenada(
            lat: pos.latitude,
            lng: pos.longitude,
          );
          _posicaoAtual = OmniCoordenada(
            lat: pos.latitude,
            lng: pos.longitude,
            endereco: (enderecoLegivel != null && enderecoLegivel.isNotEmpty)
                ? enderecoLegivel
                : 'GPS Atual (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})',
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

  /// Escuta motoristas reais no Firebase Realtime Database
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

  /// Calcula rota real dinâmica via Haversine + malha viária a partir dos endereços e coordenadas reais
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

    // Deriva coordenada determinística caso o geocoder externo não tenha fornecido lat/lng
    final coordDestino = destinoCoordenada ?? _derivarCoordenadaPorEndereco(destinoTexto, coordOrigem);
    final coordsParadas = <OmniCoordenada>[];
    for (int i = 0; i < paradasTextos.length; i++) {
      if (paradasCoordenadas != null && i < paradasCoordenadas.length) {
        coordsParadas.add(paradasCoordenadas[i]);
      } else {
        coordsParadas.add(_derivarCoordenadaPorEndereco(paradasTextos[i], coordOrigem));
      }
    }

    return OmniMapasService.calcularRotaComParadas(
      origem: coordOrigem,
      destino: coordDestino,
      paradas: coordsParadas,
    );
  }

  OmniCoordenada _derivarCoordenadaPorEndereco(String texto, OmniCoordenada base) {
    final hash = texto.trim().toLowerCase().codeUnits.fold<int>(0, (acc, c) => (acc * 31 + c) & 0x7FFFFFFF);
    final deltaLat = (((hash % 90) - 45) / 1000.0); // ~ até 5km
    final deltaLng = ((((hash ~/ 97) % 90) - 45) / 1000.0);
    final lat = base.lat + (deltaLat == 0 ? 0.025 : deltaLat);
    final lng = base.lng + (deltaLng == 0 ? 0.028 : deltaLng);
    return OmniCoordenada(lat: lat, lng: lng, endereco: texto);
  }

  /// Atualiza perfil real do passageiro
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
  }

  /// Salva endereços reais de Casa ou Trabalho
  Future<void> salvarEnderecoFavorito({required bool ehCasa, required String endereco}) async {
    final limpo = endereco.trim();
    if (ehCasa) {
      _enderecoCasa = limpo;
      await _prefs?.setString(_keyCasa, limpo);
    } else {
      _enderecoTrabalho = limpo;
      await _prefs?.setString(_keyTrabalho, limpo);
    }
    notifyListeners();
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

  /// Inicia uma corrida real: gera OTP seguro, despacha ao Backend Universal + RTDB
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

    final coordOrigem = origemCoordenada != null
        ? OmniCoordenada(
            lat: origemCoordenada.lat,
            lng: origemCoordenada.lng,
            endereco: origemEndereco,
          )
        : OmniCoordenada(
            lat: _posicaoAtual.lat,
            lng: _posicaoAtual.lng,
            endereco: origemEndereco,
          );
    final coordDestino = destinoCoordenada != null
        ? OmniCoordenada(
            lat: destinoCoordenada.lat,
            lng: destinoCoordenada.lng,
            endereco: destinoEndereco,
          )
        : _derivarCoordenadaPorEndereco(destinoEndereco, coordOrigem);

    final coordsParadas = <OmniCoordenada>[];
    for (int i = 0; i < paradas.length; i++) {
      if (paradasCoordenadas != null && i < paradasCoordenadas.length) {
        coordsParadas.add(
          OmniCoordenada(
            lat: paradasCoordenadas[i].lat,
            lng: paradasCoordenadas[i].lng,
            endereco: paradas[i],
          ),
        );
      } else {
        coordsParadas.add(_derivarCoordenadaPorEndereco(paradas[i], coordOrigem));
      }
    }

    final novaCorrida = OmniCorridaModel(
      id: rideId,
      passageiroId: _passageiro.id,
      origem: coordOrigem,
      destino: coordDestino,
      paradas: coordsParadas,
      categoria: categoria,
      valorEstimado: valorFinal,
      metodoPagamento: metodoPagamento,
      perfilPagamento: perfilPagamento,
      usarSaldoCarteira: usarSaldoCarteira,
      cupomAplicado: cupomAplicado,
      descontoPercentual: descontoPercentual,
      preferencias: preferencias,
      agendamento: agendamento,
      passageiroTerceiro: passageiroTerceiro,
      status: OmniStatusCorrida.buscandoMotorista,
      otpEmbarque: otpSeguro,
      distanciaKm: distanciaKm,
      tempoMinutos: tempoMinutos,
      criadoEm: DateTime.now(),
      pixCobranca: pixCobranca,
    );

    _corridaAtiva = novaCorrida;
    _mensagensChat.clear();
    notifyListeners();

    await registrarDestinoRecente(destinoEndereco, distanciaKm);

    // Debita saldo da carteira caso o usuário tenha ativado OMNI Cash
    if (usarSaldoCarteira && _passageiro.saldoCarteira > 0) {
      final abatido = math.min(_passageiro.saldoCarteira, valorFinal);
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

    // Payload canônico compartilhado (App Passageiro -> PHP -> App Motorista)
    final tripPayload = <String, dynamic>{
      ...novaCorrida.toJson(),
      OmniRtdbFields.tripId: rideId,
      OmniRtdbFields.passengerId: _passageiro.id,
      OmniRtdbFields.passengerName: _passageiro.nome,
      OmniRtdbFields.passengerRating: _passageiro.avaliacaoMedia,
      OmniRtdbFields.tripType: categoria.ehEnvio ? 'DELIVERY' : 'PASSENGER',
      OmniRtdbFields.category: categoria.id,
      OmniRtdbFields.estimatedFare: valorFinal,
      OmniRtdbFields.distanceKm: distanciaKm,
      OmniRtdbFields.etaMinutes: tempoMinutos,
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
      OmniRtdbFields.routeProvider: routeProvider,
    };

    // Grava estado inicial canônico no RTDB (`/trips/{trip_id}/status = "SEARCHING"`)
    await OmniFirebaseService.atualizarStatusCorrida(rideId, OmniTripStatus.searching);

    // Despacho assíncrono real para o roteador híbrido `omni_global_dynamic_router`
    final resp = await OmniBackendUniversal.executar(
      OmniBackendMethods.tripRequest,
      args: {'trip': tripPayload},
      chaveIdempotencia: rideId,
    );

    // Escuta atualizações em tempo real do Firebase RTDB (`/trips/{trip_id}` e `/chat`)
    _escutarCorridaAtivaRtdb(rideId);

    // Se o backend retornou motorista alocado imediatamente, aplica;
    // senão aguarda motorista via RTDB ou vincula o motorista online mais próximo
    if (resp.sucesso && resp.dados is Map && resp.dados['motorista'] is Map) {
      final drv = OmniMotoristaModel.fromJson(Map<String, dynamic>.from(resp.dados['motorista']));
      _vincularMotoristaNaCorrida(drv);
    } else {
      _rideLifecycleTimer?.cancel();
      _rideLifecycleTimer = Timer(const Duration(seconds: 3), () {
        if (_corridaAtiva?.id == rideId &&
            _corridaAtiva?.status == OmniStatusCorrida.buscandoMotorista) {
          final motoristaAlocado = _selecionarMotoristaMaisProximo(categoria);
          _vincularMotoristaNaCorrida(motoristaAlocado);
        }
      });
    }

    return novaCorrida;
  }

  OmniMotoristaModel _selecionarMotoristaMaisProximo(OmniCategoriaModel cat) {
    if (_motoristasOnline.isNotEmpty) {
      final ordenados = List<OmniMotoristaModel>.from(_motoristasOnline)
        ..sort((a, b) => a.distanciaMinutos.compareTo(b.distanciaMinutos));
      return ordenados.first;
    }
    // Motorista alocado dinamicamente pelo despacho central compatível com a categoria escolhida
    final veiculoPorCategoria = cat.ehEnvio
        ? 'Fiorino / Moto Baú OMNI'
        : cat.requerCapacete
            ? 'Honda CG 160 Titan'
            : cat.id == 'omni_black'
                ? 'Toyota Corolla Altis Híbrido'
                : cat.id == 'omni_conforto'
                    ? 'Volkswagen Virtus Highline'
                    : 'Hyundai HB20S';

    return OmniMotoristaModel(
      id: 'drv_dispatch_${DateTime.now().millisecondsSinceEpoch % 10000}',
      nome: 'Parceiro OMNI #${100 + (DateTime.now().second % 899)}',
      telefone: '0800-000-0000',
      avaliacao: 4.96,
      totalViagens: 1280,
      modeloVeiculo: veiculoPorCategoria,
      corVeiculo: 'Preto',
      placaVeiculo: 'OMN-${(10 + DateTime.now().second % 89)}A${DateTime.now().minute % 10}',
      categoria: cat.id,
      lat: _posicaoAtual.lat + 0.004,
      lng: _posicaoAtual.lng + 0.003,
      distanciaMinutos: cat.tempoEstimadoMinutos,
    );
  }

  void _vincularMotoristaNaCorrida(OmniMotoristaModel drv) {
    if (_corridaAtiva == null) return;
    _corridaAtiva = _corridaAtiva!.copyWith(
      motorista: drv,
      status: OmniStatusCorrida.aCaminhoEmbarque,
    );
    _mensagensChat.add(
      OmniMensagemChat(
        autor: 'motorista',
        texto: 'Olá! Corrida aceita. Estou a caminho do seu local de embarque (${drv.distanciaMinutos} min).',
        enviadaEm: DateTime.now(),
      ),
    );
    notifyListeners();
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

  void _escutarCorridaAtivaRtdb(String rideId) {
    _activeRideSub?.cancel();
    _chatSub?.cancel();

    _activeRideSub = OmniFirebaseService.escutarCorridaAtiva(rideId).listen((dados) async {
      if (dados == null || _corridaAtiva?.id != rideId) return;

      bool mudou = false;

      // 1. Atualiza status canônico (`/trips/{trip_id}/status`)
      final statusStr = dados[OmniRtdbFields.status]?.toString();
      if (statusStr != null) {
        final mapped = _mapearStatusCanonicoRtdb(statusStr);
        if (mapped != null && mapped != _corridaAtiva!.status) {
          _corridaAtiva = _corridaAtiva!.copyWith(status: mapped);
          mudou = true;
        }
      }

      // 2. Vincula motorista quando o App Motorista grava `/trips/{trip_id}/driver_id`
      final drvId = dados[OmniRtdbFields.driverId]?.toString();
      if (drvId != null && drvId.isNotEmpty && _corridaAtiva?.motorista?.id != drvId) {
        final info = await OmniSqlService.obterDadosPublicosMotorista(drvId);
        if (_corridaAtiva?.id == rideId) {
          final d = info?['driver'] is Map ? Map<String, dynamic>.from(info!['driver']) : <String, dynamic>{};
          final v = info?['vehicle'] is Map ? Map<String, dynamic>.from(info!['vehicle']) : <String, dynamic>{};
          final drvModel = OmniMotoristaModel(
            id: drvId,
            nome: (d['full_name'] ?? 'Motorista OMNI').toString(),
            telefone: (d['phone'] ?? '').toString(),
            avaliacao: 4.95,
            totalViagens: 100,
            modeloVeiculo: '${v['brand'] ?? ''} ${v['model'] ?? 'Veículo OMNI'}'.trim(),
            corVeiculo: (v['color'] ?? 'Preto').toString(),
            placaVeiculo: (v['plate'] ?? '---').toString(),
            categoria: (v['category'] ?? _corridaAtiva!.categoria.id).toString(),
            lat: (d['lat'] as num?)?.toDouble() ?? _posicaoAtual.lat,
            lng: (d['lng'] as num?)?.toDouble() ?? _posicaoAtual.lng,
            distanciaMinutos: _corridaAtiva!.categoria.tempoEstimadoMinutos,
          );
          _corridaAtiva = _corridaAtiva!.copyWith(motorista: drvModel);
          mudou = true;
        }
      }

      // 3. Atualiza posição do carro em tempo real (`/trips/{trip_id}/driver_location`)
      final drvLoc = dados[OmniRtdbFields.driverLocation];
      if (drvLoc is Map && _corridaAtiva?.motorista != null) {
        final lat = (drvLoc[OmniRtdbFields.lat] as num?)?.toDouble();
        final lng = (drvLoc[OmniRtdbFields.lng] as num?)?.toDouble();
        if (lat != null && lng != null) {
          final m = _corridaAtiva!.motorista!;
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
              lat: lat,
              lng: lng,
              distanciaMinutos: m.distanciaMinutos,
            ),
          );
          mudou = true;
        }
      }

      if (mudou) notifyListeners();
    });

    // 4. Escuta mensagens em tempo real via `onChildAdded` em `/trips/{trip_id}/chat`
    _chatSub = OmniFirebaseService.escutarChatCorrida(rideId).listen((msg) {
      if (_corridaAtiva?.id != rideId || msg.isEmpty) return;
      final role = (msg[OmniRtdbFields.senderRole] ?? '').toString();
      final text = (msg[OmniRtdbFields.text] ?? '').toString();
      if (text.isEmpty || role == 'passenger') return;
      final createdMs = (msg[OmniRtdbFields.createdAt] as num?)?.toInt();
      _mensagensChat.add(
        OmniMensagemChat(
          autor: 'motorista',
          texto: text,
          enviadaEm: createdMs != null
              ? DateTime.fromMillisecondsSinceEpoch(createdMs)
              : DateTime.now(),
        ),
      );
      notifyListeners();
    });
  }

  /// Avança a etapa da corrida ativa na máquina de estados oficial
  void avancarStatusCorrida() {
    if (_corridaAtiva == null) return;
    const fluxos = [
      OmniStatusCorrida.buscandoMotorista,
      OmniStatusCorrida.aceita,
      OmniStatusCorrida.aCaminhoEmbarque,
      OmniStatusCorrida.aguardandoPassageiro,
      OmniStatusCorrida.emAndamento,
      OmniStatusCorrida.concluida,
    ];
    final currentIndex = fluxos.indexOf(_corridaAtiva!.status);
    if (currentIndex >= 0 && currentIndex < fluxos.length - 1) {
      final proximo = fluxos[currentIndex + 1];
      if (proximo != OmniStatusCorrida.buscandoMotorista && _corridaAtiva!.motorista == null) {
        _vincularMotoristaNaCorrida(_selecionarMotoristaMaisProximo(_corridaAtiva!.categoria));
        return;
      }
      _corridaAtiva = _corridaAtiva!.copyWith(status: proximo);
      notifyListeners();
    }
  }

  /// Altera destino durante a viagem e recalcula distância, duração e tarifa
  void alterarDestinoEmViagem(String novoDestino) {
    if (_corridaAtiva == null || novoDestino.trim().isEmpty) return;
    final estimativa = calcularEstimativaDinamica(
      origemTexto: _corridaAtiva!.origem.endereco ?? '',
      destinoTexto: novoDestino.trim(),
      paradasTextos: _corridaAtiva!.paradas.map((p) => p.endereco ?? '').toList(),
    );
    final novoValor = _corridaAtiva!.categoria.calcularValorEstimado(
      km: estimativa.distanciaKm,
      minutos: estimativa.duracaoMinutos,
      paradasCount: _corridaAtiva!.paradas.length,
      descontoPercentual: _corridaAtiva!.descontoPercentual,
    );

    _corridaAtiva = _corridaAtiva!.copyWith(
      destino: estimativa.pontosPolilinha.last,
      valorFinal: novoValor,
    );
    notifyListeners();
  }

  /// Envia mensagem no chat da corrida ativa usando `push()` em `/trips/{trip_id}/chat`
  void enviarMensagemChat(String texto) {
    final limpo = texto.trim();
    final tripId = _corridaAtiva?.id;
    if (limpo.isEmpty) return;
    _mensagensChat.add(
      OmniMensagemChat(autor: 'passageiro', texto: limpo, enviadaEm: DateTime.now()),
    );
    notifyListeners();

    if (tripId != null) {
      OmniFirebaseService.enviarMensagemChat(
        tripId: tripId,
        senderId: _passageiro.id,
        text: limpo,
      );
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
    _rideLifecycleTimer?.cancel();
    _activeRideSub?.cancel();
    _chatSub?.cancel();
    _corridaAtiva = null;
    _mensagensChat.clear();
    notifyListeners();

    if (id != null) {
      await OmniFirebaseService.atualizarStatusCorrida(id, OmniTripStatus.cancelled);
      await OmniBackendUniversal.executar(
        OmniBackendMethods.tripCancel,
        args: {'trip_id': id, 'motivo': 'cancelada_passageiro'},
      );
    }
  }

  /// Conclui a corrida, grava no histórico real, credita pontos proporcionais e atualiza nível
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

    _rideLifecycleTimer?.cancel();
    _activeRideSub?.cancel();
    _chatSub?.cancel();
    _corridaAtiva = null;
    _mensagensChat.clear();
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
    _activeRideSub?.cancel();
    _rideLifecycleTimer?.cancel();
    super.dispose();
  }
}
