import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/omni_constants.dart';
import '../../models/corrida_model.dart';
import '../../state/omni_app_state.dart';
import '../../tools/mapas_service.dart';
import 'omni_schedule_sheet.dart';

/// Resultado estruturado do planejamento de viagem ("Planeje sua próxima viagem")
class OmniTripPlanResult {
  final String origem;
  final String destino;
  final List<String> paradas;
  final double distanciaKm;
  final int duracaoMinutos;
  final String routeProvider;
  final OmniAgendamentoCorrida? agendamento;
  final OmniPassageiroTerceiro? passageiroTerceiro;
  final OmniCoordenada? origemCoord;
  final OmniCoordenada? destinoCoord;
  final List<OmniCoordenada> paradasCoords;

  const OmniTripPlanResult({
    required this.origem,
    required this.destino,
    this.paradas = const [],
    required this.distanciaKm,
    required this.duracaoMinutos,
    this.routeProvider = 'haversine_viario',
    this.agendamento,
    this.passageiroTerceiro,
    this.origemCoord,
    this.destinoCoord,
    this.paradasCoords = const [],
  });
}

/// Modal "Planeje sua próxima viagem" conectado ao OmniAppState e Motor de Autocomplete por Proximidade
Future<OmniTripPlanResult?> showOmniTripPlannerSheet(
  BuildContext context, {
  required String origemInicial,
  String destinoInicial = '',
  List<String> paradasIniciais = const [],
  OmniAgendamentoCorrida? agendamentoInicial,
  OmniPassageiroTerceiro? passageiroTerceiroInicial,
  OmniCoordenada? origemCoordInicial,
  OmniCoordenada? destinoCoordInicial,
  List<OmniCoordenada> paradasCoordsIniciais = const [],
}) {
  return showModalBottomSheet<OmniTripPlanResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _OmniTripPlannerSheet(
      origemInicial: origemInicial,
      destinoInicial: destinoInicial,
      paradasIniciais: paradasIniciais,
      agendamentoInicial: agendamentoInicial,
      passageiroTerceiroInicial: passageiroTerceiroInicial,
      origemCoordInicial: origemCoordInicial,
      destinoCoordInicial: destinoCoordInicial,
      paradasCoordsIniciais: paradasCoordsIniciais,
    ),
  );
}

class _OmniTripPlannerSheet extends StatefulWidget {
  final String origemInicial;
  final String destinoInicial;
  final List<String> paradasIniciais;
  final OmniAgendamentoCorrida? agendamentoInicial;
  final OmniPassageiroTerceiro? passageiroTerceiroInicial;
  final OmniCoordenada? origemCoordInicial;
  final OmniCoordenada? destinoCoordInicial;
  final List<OmniCoordenada> paradasCoordsIniciais;

  const _OmniTripPlannerSheet({
    required this.origemInicial,
    required this.destinoInicial,
    required this.paradasIniciais,
    this.agendamentoInicial,
    this.passageiroTerceiroInicial,
    this.origemCoordInicial,
    this.destinoCoordInicial,
    this.paradasCoordsIniciais = const [],
  });

  @override
  State<_OmniTripPlannerSheet> createState() => _OmniTripPlannerSheetState();
}

class _OmniTripPlannerSheetState extends State<_OmniTripPlannerSheet> {
  late final TextEditingController _origemCtrl;
  late final TextEditingController _destinoCtrl;
  late final List<TextEditingController> _paradasCtrls;

  late final FocusNode _origemFocus;
  late final FocusNode _destinoFocus;
  late final List<FocusNode> _paradasFocus;

  OmniCoordenada? _origemCoord;
  OmniCoordenada? _destinoCoord;
  late final List<OmniCoordenada?> _paradasCoords;

  OmniAgendamentoCorrida? _agendamento;
  OmniPassageiroTerceiro? _terceiro;

  String _campoAtivo = 'destino'; // 'origem' | 'parada' | 'destino'
  int _paradaAtivaIdx = -1;
  Timer? _debounce;
  bool _buscando = false;
  bool _buscaRealizada = false;
  String? _sessionToken;
  int _buscaSeq = 0;
  int _rotaSeq = 0;
  OmniEstimativaRota? _estimativaReal;
  List<OmniEnderecoSugestao> _sugestoes = const [];

  @override
  void initState() {
    super.initState();
    _origemCtrl = TextEditingController(text: widget.origemInicial);
    _destinoCtrl = TextEditingController(text: widget.destinoInicial);
    _paradasCtrls = widget.paradasIniciais.map((p) => TextEditingController(text: p)).toList();

    _origemCoord = widget.origemCoordInicial;
    _destinoCoord = widget.destinoCoordInicial;
    _paradasCoords = List<OmniCoordenada?>.generate(
      _paradasCtrls.length,
      (i) => i < widget.paradasCoordsIniciais.length ? widget.paradasCoordsIniciais[i] : null,
    );

    _origemFocus = FocusNode()..addListener(() {
      if (_origemFocus.hasFocus && mounted) {
        final txt = _origemCtrl.text.trim();
        final podeBuscar = txt.length >= 2 &&
            !txt.toLowerCase().startsWith('obtendo ') &&
            !txt.toLowerCase().startsWith('localização ');
        if (_campoAtivo != 'origem' || _paradaAtivaIdx != -1 || !podeBuscar) {
          setState(() {
            _campoAtivo = 'origem';
            _paradaAtivaIdx = -1;
            if (!podeBuscar) {
              _sugestoes = const [];
              _buscaRealizada = false;
            }
          });
        }
        if (podeBuscar) {
          _dispararBuscaCampo(context.read<OmniAppState>(), txt);
        }
      }
    });
    _destinoFocus = FocusNode()..addListener(() {
      if (_destinoFocus.hasFocus && mounted) {
        final txt = _destinoCtrl.text.trim();
        final podeBuscar = txt.length >= 2;
        if (_campoAtivo != 'destino' || _paradaAtivaIdx != -1 || !podeBuscar) {
          setState(() {
            _campoAtivo = 'destino';
            _paradaAtivaIdx = -1;
            if (!podeBuscar) {
              _sugestoes = const [];
              _buscaRealizada = false;
            }
          });
        }
        if (podeBuscar) {
          _dispararBuscaCampo(context.read<OmniAppState>(), txt);
        }
      }
    });
    _paradasFocus = List<FocusNode>.generate(_paradasCtrls.length, _criarFocusParada);

    _agendamento = widget.agendamentoInicial;
    _terceiro = widget.passageiroTerceiroInicial;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.destinoInicial.isEmpty) {
        _destinoFocus.requestFocus();
      }
      if (_destinoCtrl.text.trim().isNotEmpty) {
        _atualizarRotaReal(context.read<OmniAppState>());
      }
    });
  }

  FocusNode _criarFocusParada(int idx) {
    final node = FocusNode();
    node.addListener(() {
      if (node.hasFocus && mounted) {
        final currentIdx = _paradasFocus.indexOf(node);
        if (currentIdx >= 0) {
          final txt = _paradasCtrls[currentIdx].text.trim();
          final podeBuscar = txt.length >= 2;
          if (_campoAtivo != 'parada' || _paradaAtivaIdx != currentIdx || !podeBuscar) {
            setState(() {
              _campoAtivo = 'parada';
              _paradaAtivaIdx = currentIdx;
              if (!podeBuscar) {
                _sugestoes = const [];
                _buscaRealizada = false;
              }
            });
          }
          if (podeBuscar) {
            _dispararBuscaCampo(context.read<OmniAppState>(), txt);
          }
        }
      }
    });
    return node;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _origemCtrl.dispose();
    _destinoCtrl.dispose();
    _origemFocus.dispose();
    _destinoFocus.dispose();
    for (final c in _paradasCtrls) {
      c.dispose();
    }
    for (final f in _paradasFocus) {
      f.dispose();
    }
    super.dispose();
  }

  void _adicionarParada(OmniAppState appState) {
    if (_paradasCtrls.length >= 3) return;
    setState(() {
      final ctrl = TextEditingController();
      final focus = _criarFocusParada(_paradasCtrls.length);
      _paradasCtrls.add(ctrl);
      _paradasFocus.add(focus);
      _paradasCoords.add(null);
      _campoAtivo = 'parada';
      _paradaAtivaIdx = _paradasCtrls.length - 1;
      _sugestoes = const [];
      _buscaRealizada = false;
      _estimativaReal = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _paradasFocus.isNotEmpty) {
        _paradasFocus.last.requestFocus();
      }
    });
    _atualizarRotaReal(appState);
  }

  void _removerParada(OmniAppState appState, int index) {
    setState(() {
      final c = _paradasCtrls.removeAt(index);
      c.dispose();
      final f = _paradasFocus.removeAt(index);
      f.dispose();
      _paradasCoords.removeAt(index);
      if (_campoAtivo == 'parada' && _paradaAtivaIdx >= _paradasCtrls.length) {
        _campoAtivo = 'destino';
        _paradaAtivaIdx = -1;
      }
      _sugestoes = const [];
      _estimativaReal = null;
    });
    _atualizarRotaReal(appState);
  }

  void _dispararBuscaCampo(OmniAppState appState, String q) {
    _debounce?.cancel();
    if (q.length < 2) {
      if (_buscando || _buscaRealizada || _sugestoes.isNotEmpty) {
        setState(() {
          _buscando = false;
          _buscaRealizada = false;
          _sugestoes = const [];
        });
      }
      return;
    }

    _sessionToken ??= 'omni_${DateTime.now().millisecondsSinceEpoch}';
    final seqAtual = ++_buscaSeq;
    if (!_buscando) {
      setState(() => _buscando = true);
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final resultados = await OmniMapasService.buscarEnderecosProximos(
        query: q,
        latReferencia: appState.posicaoAtual.lat,
        lngReferencia: appState.posicaoAtual.lng,
        sessionToken: _sessionToken,
      );
      if (!mounted || seqAtual != _buscaSeq) return;
      setState(() {
        _buscando = false;
        _buscaRealizada = true;
        _sugestoes = resultados;
      });
    });
  }

  void _onCampoAlterado(
    OmniAppState appState, {
    required String campo,
    int paradaIdx = -1,
    required String texto,
  }) {
    final bool coordMudou = (campo == 'origem' && _origemCoord != null) ||
        (campo == 'destino' && _destinoCoord != null) ||
        (campo == 'parada' &&
            paradaIdx >= 0 &&
            paradaIdx < _paradasCoords.length &&
            _paradasCoords[paradaIdx] != null);

    if (_campoAtivo != campo || _paradaAtivaIdx != paradaIdx || _estimativaReal != null || coordMudou) {
      setState(() {
        _campoAtivo = campo;
        _paradaAtivaIdx = paradaIdx;
        _estimativaReal = null;
        if (campo == 'origem') {
          _origemCoord = null;
        } else if (campo == 'destino') {
          _destinoCoord = null;
        } else if (campo == 'parada' && paradaIdx >= 0 && paradaIdx < _paradasCoords.length) {
          _paradasCoords[paradaIdx] = null;
        }
      });
    }

    _dispararBuscaCampo(appState, texto.trim());
  }

  Future<void> _atualizarRotaReal(OmniAppState appState) async {
    final destino = _destinoCtrl.text.trim();
    if (destino.isEmpty) return;

    final origemTexto = _origemCtrl.text.trim().isEmpty
        ? (appState.posicaoAtual.endereco ?? 'Localização atual GPS')
        : _origemCtrl.text.trim();
    final paradasTextos = _paradasCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    final coordsOrigem = _origemCoord ??
        OmniCoordenada(
          lat: appState.posicaoAtual.lat,
          lng: appState.posicaoAtual.lng,
          endereco: origemTexto,
        );
    final coordsDestino = _destinoCoord;
    if (coordsDestino == null) return;

    final paradasCoords = _coletarParadasCoords(appState, origemTexto);
    final seq = ++_rotaSeq;
    final realEst = await OmniMapasService.calcularRotaRealComParadas(
      origem: coordsOrigem,
      destino: OmniCoordenada(lat: coordsDestino.lat, lng: coordsDestino.lng, endereco: destino),
      paradas: paradasCoords,
    );
    if (!mounted || seq != _rotaSeq) return;
    if (paradasTextos.length == paradasCoords.length) {
      setState(() => _estimativaReal = realEst);
    }
  }

  Future<void> _selecionarSugestao(OmniAppState appState, OmniEnderecoSugestao sug) async {
    _debounce?.cancel();
    _buscaSeq++;
    final tokenUsado = _sessionToken;
    _sessionToken = null;

    final campoAlvo = _campoAtivo;
    final paradaAlvo = _paradaAtivaIdx;

    void aplicarTexto(String texto) {
      final tv = TextEditingValue(
        text: texto,
        selection: TextSelection.collapsed(offset: texto.length),
      );
      if (campoAlvo == 'origem') {
        _origemCtrl.value = tv;
      } else if (campoAlvo == 'parada' && paradaAlvo >= 0 && paradaAlvo < _paradasCtrls.length) {
        _paradasCtrls[paradaAlvo].value = tv;
      } else {
        _destinoCtrl.value = tv;
      }
    }

    setState(() {
      _buscando = false;
      _buscaRealizada = false;
      _sugestoes = const [];
      _estimativaReal = null;
      aplicarTexto(sug.enderecoCompleto);
    });

    final coord = await OmniMapasService.obterDetalhesLugar(
      sugestao: sug,
      fallbackLat: appState.posicaoAtual.lat,
      fallbackLng: appState.posicaoAtual.lng,
      sessionToken: tokenUsado,
    );
    if (!mounted) return;

    final enderecoFinal = (coord.endereco != null && coord.endereco!.isNotEmpty)
        ? coord.endereco!
        : sug.enderecoCompleto;

    setState(() {
      aplicarTexto(enderecoFinal);
      if (campoAlvo == 'origem') {
        _origemCoord = coord;
      } else if (campoAlvo == 'parada' && paradaAlvo >= 0 && paradaAlvo < _paradasCoords.length) {
        _paradasCoords[paradaAlvo] = coord;
      } else {
        _destinoCoord = coord;
      }
    });

    unawaited(_atualizarRotaReal(appState));

    if (campoAlvo == 'origem' && _destinoCtrl.text.trim().isEmpty) {
      _destinoFocus.requestFocus();
    } else if (campoAlvo == 'parada' && _destinoCtrl.text.trim().isEmpty) {
      _destinoFocus.requestFocus();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  String _rotuloCampoAtivo() {
    if (_campoAtivo == 'origem') return 'Origem';
    if (_campoAtivo == 'parada' && _paradaAtivaIdx >= 0) return 'Parada ${_paradaAtivaIdx + 1}';
    return 'Destino';
  }

  IconData _iconePorTipo(String tipoIcone) {
    switch (tipoIcone) {
      case 'airport':
        return Icons.flight_takeoff_rounded;
      case 'transit':
        return Icons.directions_transit_rounded;
      case 'shopping':
        return Icons.shopping_bag_rounded;
      case 'hospital':
        return Icons.local_hospital_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      case 'hotel':
        return Icons.hotel_rounded;
      case 'park':
        return Icons.park_rounded;
      case 'fuel':
        return Icons.local_gas_station_rounded;
      case 'school':
        return Icons.school_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  Future<void> _abrirAgendamento() async {
    final res = await showOmniScheduleSheet(context, initialSchedule: _agendamento);
    if (!mounted) return;
    setState(() => _agendamento = res);
  }

  Future<void> _configurarEnderecoFavorito(OmniAppState appState, {required bool ehCasa}) async {
    final ctrl = TextEditingController(text: ehCasa ? appState.enderecoCasa : appState.enderecoTrabalho);
    final salvo = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (ctx) => Dialog(
        backgroundColor: OmniConstants.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: OmniConstants.darkBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ehCasa ? 'Salvar endereço de Casa' : 'Salvar endereço do Trabalho',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Digite rua, número e bairro',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: OmniConstants.textMuted,
                        side: const BorderSide(color: OmniConstants.darkBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OmniConstants.neonCyan,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Salvar', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();

    if (salvo != null && salvo.isNotEmpty && mounted) {
      await appState.salvarEnderecoFavorito(ehCasa: ehCasa, endereco: salvo);
    }
  }

  Future<void> _abrirSeletorPassageiro() async {
    final nomeCtrl = TextEditingController(text: _terceiro?.nome ?? '');
    final foneCtrl = TextEditingController(text: _terceiro?.telefone ?? '');

    final result = await showDialog<OmniPassageiroTerceiro?>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (ctx) => Dialog(
        backgroundColor: OmniConstants.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: OmniConstants.darkBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Quem vai viajar?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Você pode solicitar para você ou enviar o link de acompanhamento e OTP para outra pessoa.',
                  style: TextStyle(fontSize: 12, color: OmniConstants.textMuted),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nomeCtrl,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nome do passageiro',
                    hintText: 'Nome completo',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: foneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp / Telefone',
                    hintText: '(DDD) 90000-0000',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(const OmniPassageiroTerceiro(nome: '', telefone: '')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: OmniConstants.textSecondary,
                          side: const BorderSide(color: OmniConstants.darkBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Para mim', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final nome = nomeCtrl.text.trim();
                          if (nome.isEmpty) {
                            Navigator.of(ctx).pop(const OmniPassageiroTerceiro(nome: '', telefone: ''));
                          } else {
                            Navigator.of(ctx).pop(
                              OmniPassageiroTerceiro(nome: nome, telefone: foneCtrl.text.trim()),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OmniConstants.neonCyan,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Confirmar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    nomeCtrl.dispose();
    foneCtrl.dispose();

    if (!mounted || result == null) return;
    setState(() {
      _terceiro = result.nome.isEmpty ? null : result;
    });
  }

  void _selecionarDestino(OmniAppState appState, String endereco, {OmniCoordenada? coord}) {
    setState(() {
      _destinoCtrl.value = TextEditingValue(
        text: endereco,
        selection: TextSelection.collapsed(offset: endereco.length),
      );
      _destinoCoord = coord;
      _sugestoes = const [];
      _estimativaReal = null;
    });
    _confirmarRota(appState);
  }

  List<OmniCoordenada> _coletarParadasCoords(OmniAppState appState, String origem) {
    final list = <OmniCoordenada>[];
    for (int i = 0; i < _paradasCtrls.length; i++) {
      final texto = _paradasCtrls[i].text.trim();
      if (texto.isEmpty) continue;
      final coord = _paradasCoords[i];
      if (coord != null) {
        list.add(coord);
      } else {
        final est = appState.calcularEstimativaDinamica(
          origemTexto: origem,
          destinoTexto: texto,
          origemCoordenada: _origemCoord,
        );
        list.add(est.pontosPolilinha.last);
      }
    }
    return list;
  }

  OmniEstimativaRota? _calcularPreviewAtual(OmniAppState appState) {
    if (_estimativaReal != null) return _estimativaReal;
    final destino = _destinoCtrl.text.trim();
    if (destino.isEmpty) return null;
    final origem = _origemCtrl.text.trim().isEmpty
        ? (appState.posicaoAtual.endereco ?? 'Localização atual GPS')
        : _origemCtrl.text.trim();
    final paradas = _paradasCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    final paradasCoords = _coletarParadasCoords(appState, origem);

    return appState.calcularEstimativaDinamica(
      origemTexto: origem,
      destinoTexto: destino,
      paradasTextos: paradas,
      origemCoordenada: _origemCoord,
      destinoCoordenada: _destinoCoord,
      paradasCoordenadas: paradasCoords,
    );
  }

  Future<void> _confirmarRota(OmniAppState appState) async {
    final destino = _destinoCtrl.text.trim();
    if (destino.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o endereço de destino para calcular a viagem.')),
      );
      return;
    }

    final origem = _origemCtrl.text.trim().isEmpty
        ? (appState.posicaoAtual.endereco ?? 'Localização atual GPS')
        : _origemCtrl.text.trim();
    final paradas = _paradasCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    final paradasCoords = _coletarParadasCoords(appState, origem);

    OmniEstimativaRota estimativa = _estimativaReal ??
        appState.calcularEstimativaDinamica(
          origemTexto: origem,
          destinoTexto: destino,
          paradasTextos: paradas,
          origemCoordenada: _origemCoord,
          destinoCoordenada: _destinoCoord,
          paradasCoordenadas: paradasCoords,
        );

    if (_estimativaReal == null && _destinoCoord != null) {
      final origemBase = _origemCoord ??
          OmniCoordenada(
            lat: appState.posicaoAtual.lat,
            lng: appState.posicaoAtual.lng,
            endereco: origem,
          );
      estimativa = await OmniMapasService.calcularRotaRealComParadas(
        origem: origemBase,
        destino: OmniCoordenada(lat: _destinoCoord!.lat, lng: _destinoCoord!.lng, endereco: destino),
        paradas: paradasCoords,
      );
      if (!mounted) return;
    }

    Navigator.of(context).pop(
      OmniTripPlanResult(
        origem: origem,
        destino: destino,
        paradas: paradas,
        distanciaKm: estimativa.distanciaKm,
        duracaoMinutos: estimativa.duracaoMinutos,
        routeProvider: estimativa.routeProvider,
        agendamento: _agendamento,
        passageiroTerceiro: _terceiro,
        origemCoord: _origemCoord,
        destinoCoord: _destinoCoord,
        paradasCoords: paradasCoords,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<OmniAppState>();
    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom;
    final bool keyboardOpen = bottomInset > 40;
    final bool buscaAtiva = _buscando || _sugestoes.isNotEmpty || _buscaRealizada;
    final double adjustedBottomInset = (bottomInset - mq.viewPadding.bottom) < 0
        ? 0.0
        : (bottomInset - mq.viewPadding.bottom);
    final estimativaPreview = _calcularPreviewAtual(appState);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double maxSafeH = constraints.maxHeight;
          final double sheetHeight = maxSafeH > 320.0 ? maxSafeH * 0.96 : maxSafeH;
          final double visibleAreaHeight = sheetHeight - adjustedBottomInset;

          return SizedBox(
            height: sheetHeight,
            child: Padding(
              padding: EdgeInsets.only(bottom: adjustedBottomInset),
              child: Container(
                decoration: const BoxDecoration(
                  color: OmniConstants.darkCard,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                  border: Border(top: BorderSide(color: OmniConstants.darkBorder)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                SizedBox(height: keyboardOpen ? 6 : 10),
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(8, keyboardOpen ? 2 : 6, 14, keyboardOpen ? 2 : 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Expanded(
                        child: Text(
                          'Planeje sua próxima viagem',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),

                KeyedSubtree(
                  key: const ValueKey('omni_planner_pills_slot'),
                  child: (!keyboardOpen || !buscaAtiva)
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                child: Row(
                                  children: [
                                    _HeaderPillChip(
                                      icon: Icons.access_time_filled_rounded,
                                      label: _agendamento == null ? 'Ir agora' : _agendamento!.resumoCurto,
                                      highlighted: _agendamento != null,
                                      onTap: _abrirAgendamento,
                                    ),
                                    const SizedBox(width: 8),
                                    _HeaderPillChip(
                                      icon: Icons.person_rounded,
                                      label: _terceiro == null ? 'Para mim' : 'Para ${_terceiro!.nome}',
                                      highlighted: _terceiro != null,
                                      onTap: _abrirSeletorPassageiro,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: keyboardOpen ? 8 : 10),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),

                Padding(
                  key: const ValueKey('omni_planner_inputs_card'),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: OmniConstants.darkSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.45)),
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: keyboardOpen ? 136 : 220),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _EditableAddressRow(
                                    key: const ValueKey('omni_planner_row_origem'),
                                    dotColor: OmniConstants.neonCyan,
                                    isSquare: false,
                                    controller: _origemCtrl,
                                    focusNode: _origemFocus,
                                    hint: 'Local de partida',
                                    onChanged: (txt) => _onCampoAlterado(
                                      appState,
                                      campo: 'origem',
                                      texto: txt,
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        KeyedSubtree(
                                          key: const ValueKey('omni_planner_origem_clear_slot'),
                                          child: (_origemFocus.hasFocus && _origemCtrl.text.isNotEmpty)
                                              ? IconButton(
                                                  icon: const Icon(Icons.cancel_rounded, size: 15, color: OmniConstants.textDim),
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                                  onPressed: () {
                                                    _origemCtrl.clear();
                                                    _onCampoAlterado(appState, campo: 'origem', texto: '');
                                                    _origemFocus.requestFocus();
                                                  },
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            appState.gpsCarregando ? Icons.sync_rounded : Icons.my_location_rounded,
                                            size: 16,
                                            color: OmniConstants.neonCyan,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                          onPressed: () async {
                                            await appState.atualizarLocalizacaoGps();
                                            if (mounted && appState.posicaoAtual.endereco != null) {
                                              setState(() {
                                                _origemCtrl.value = TextEditingValue(
                                                  text: appState.posicaoAtual.endereco!,
                                                  selection: TextSelection.collapsed(
                                                    offset: appState.posicaoAtual.endereco!.length,
                                                  ),
                                                );
                                                _origemCoord = appState.posicaoAtual;
                                                _sugestoes = const [];
                                              });
                                              unawaited(_atualizarRotaReal(appState));
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  for (int i = 0; i < _paradasCtrls.length; i++)
                                    Column(
                                      key: ObjectKey(_paradasCtrls[i]),
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Divider(height: 10, color: OmniConstants.darkBorderSubtle),
                                        _EditableAddressRow(
                                          key: ValueKey('omni_planner_row_parada_${identityHashCode(_paradasCtrls[i])}'),
                                          dotColor: OmniConstants.goldAccent,
                                          isSquare: false,
                                          controller: _paradasCtrls[i],
                                          focusNode: _paradasFocus[i],
                                          hint: 'Parada ${i + 1} (digite rua ou local)',
                                          onChanged: (txt) => _onCampoAlterado(
                                            appState,
                                            campo: 'parada',
                                            paradaIdx: i,
                                            texto: txt,
                                          ),
                                          trailing: IconButton(
                                            icon: const Icon(Icons.close_rounded, size: 16, color: OmniConstants.rubyRedAlert),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                            onPressed: () => _removerParada(appState, i),
                                          ),
                                        ),
                                      ],
                                    ),
                                  const Divider(height: 10, color: OmniConstants.darkBorderSubtle),
                                  _EditableAddressRow(
                                    key: const ValueKey('omni_planner_row_destino'),
                                    dotColor: OmniConstants.rubyRedAlert,
                                    isSquare: true,
                                    controller: _destinoCtrl,
                                    focusNode: _destinoFocus,
                                    hint: 'Para onde você vai?',
                                    onChanged: (txt) => _onCampoAlterado(
                                      appState,
                                      campo: 'destino',
                                      texto: txt,
                                    ),
                                    onSubmitted: (_) => _confirmarRota(appState),
                                    trailing: KeyedSubtree(
                                      key: const ValueKey('omni_planner_destino_clear_slot'),
                                      child: (_destinoFocus.hasFocus && _destinoCtrl.text.isNotEmpty)
                                          ? IconButton(
                                              icon: const Icon(Icons.cancel_rounded, size: 15, color: OmniConstants.textDim),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                              onPressed: () {
                                                _destinoCtrl.clear();
                                                _onCampoAlterado(appState, campo: 'destino', texto: '');
                                                _destinoFocus.requestFocus();
                                              },
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: OmniConstants.darkSurface,
                        shape: const CircleBorder(),
                        child: InkWell(
                          onTap: () => _adicionarParada(appState),
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: OmniConstants.darkBorder),
                            ),
                            child: const Icon(Icons.add_rounded, color: OmniConstants.neonCyan, size: 21),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Lista rolável garantida com Expanded e teclado mantido estável durante digitação e rolagem
                Expanded(
                  key: const ValueKey('omni_planner_results_area'),
                  child: ListView(
                    key: const ValueKey('omni_planner_scroll_list'),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    children: [
                      if (buscaAtiva) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A0F14),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.45)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: const BoxDecoration(
                                  color: OmniConstants.darkSurface,
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                                  border: Border(bottom: BorderSide(color: OmniConstants.darkBorderSubtle)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          const Icon(Icons.near_me_rounded, size: 13, color: OmniConstants.neonCyan),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'MAIS PRÓXIMOS DE VOCÊ · ${_rotuloCampoAtivo().toUpperCase()}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.7,
                                                color: OmniConstants.neonCyan,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _buscando ? 'Buscando...' : '${_sugestoes.length} locais',
                                      style: const TextStyle(fontSize: 10.5, color: OmniConstants.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              if (_buscando && _sugestoes.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 15,
                                        height: 15,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: OmniConstants.neonCyan,
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Buscando endereços mais próximos da sua localização...',
                                          style: TextStyle(fontSize: 12, color: OmniConstants.textMuted),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (_sugestoes.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: Text(
                                    'Nenhum endereço próximo sugerido. Continue digitando ou toque em Calcular Rota abaixo.',
                                    style: TextStyle(fontSize: 12, color: OmniConstants.textMuted),
                                  ),
                                )
                              else
                                ..._sugestoes.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final sug = entry.value;
                                  final distLabel = OmniMapasService.formatarDistanciaProximidade(sug.distanciaKm);
                                  final isMaisProximo = idx == 0;
                                  return Column(
                                    key: ValueKey('planner_sug_${sug.id}_$idx'),
                                    children: [
                                      if (idx > 0)
                                        const Divider(height: 1, color: OmniConstants.darkBorderSubtle),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () => _selecionarSugestao(appState, sug),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 34,
                                                  height: 34,
                                                  decoration: BoxDecoration(
                                                    color: isMaisProximo
                                                        ? OmniConstants.neonCyan.withValues(alpha: 0.14)
                                                        : Colors.white.withValues(alpha: 0.05),
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(
                                                      color: isMaisProximo
                                                          ? OmniConstants.neonCyan.withValues(alpha: 0.45)
                                                          : OmniConstants.darkBorder,
                                                    ),
                                                  ),
                                                  child: Icon(
                                                    _iconePorTipo(sug.tipoIcone),
                                                    size: 17,
                                                    color: OmniConstants.neonCyan,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              sug.titulo,
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: const TextStyle(
                                                                fontSize: 13,
                                                                fontWeight: FontWeight.w700,
                                                                color: Colors.white,
                                                              ),
                                                            ),
                                                          ),
                                                          if (isMaisProximo && distLabel != null) ...[
                                                            const SizedBox(width: 5),
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                              decoration: BoxDecoration(
                                                                color: OmniConstants.emeraldSuccess.withValues(alpha: 0.16),
                                                                borderRadius: BorderRadius.circular(4),
                                                              ),
                                                              child: const Text(
                                                                'Mais próximo',
                                                                style: TextStyle(
                                                                  fontSize: 8.5,
                                                                  fontWeight: FontWeight.w800,
                                                                  color: Color(0xFF34D399),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                      if (sug.subtitulo.isNotEmpty)
                                                        Text(
                                                          sug.subtitulo,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(
                                                            fontSize: 11,
                                                            color: OmniConstants.textMuted,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                if (distLabel != null) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: OmniConstants.neonCyan.withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(999),
                                                      border: Border.all(
                                                        color: OmniConstants.neonCyan.withValues(alpha: 0.32),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      distLabel,
                                                      style: const TextStyle(
                                                        fontFamily: 'monospace',
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w800,
                                                        color: OmniConstants.neonCyan,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }),
                            ],
                          ),
                        ),
                      ],

                      Row(
                        children: [
                          Expanded(
                            child: _SavedPlaceTile(
                              icon: Icons.home_rounded,
                              label: 'Casa',
                              subtitle: appState.enderecoCasa.isEmpty
                                  ? 'Toque para cadastrar'
                                  : appState.enderecoCasa,
                              onTap: () {
                                if (appState.enderecoCasa.isEmpty) {
                                  _configurarEnderecoFavorito(appState, ehCasa: true);
                                } else {
                                  _selecionarDestino(appState, appState.enderecoCasa);
                                }
                              },
                              onLongPress: () => _configurarEnderecoFavorito(appState, ehCasa: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _SavedPlaceTile(
                              icon: Icons.work_rounded,
                              label: 'Trabalho',
                              subtitle: appState.enderecoTrabalho.isEmpty
                                  ? 'Toque para cadastrar'
                                  : appState.enderecoTrabalho,
                              onTap: () {
                                if (appState.enderecoTrabalho.isEmpty) {
                                  _configurarEnderecoFavorito(appState, ehCasa: false);
                                } else {
                                  _selecionarDestino(appState, appState.enderecoTrabalho);
                                }
                              },
                              onLongPress: () => _configurarEnderecoFavorito(appState, ehCasa: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'DESTINOS RECENTES',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: OmniConstants.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (appState.destinosRecentes.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: OmniConstants.darkSurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: OmniConstants.darkBorderSubtle),
                          ),
                          child: const Text(
                            'Nenhum destino recente salvo ainda. Digite seu destino acima para calcular a rota e salvar no histórico.',
                            style: TextStyle(fontSize: 12, color: OmniConstants.textMuted),
                          ),
                        )
                      else
                        ...appState.destinosRecentes.map((rec) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: OmniConstants.darkSurface,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                onTap: () => _selecionarDestino(appState, rec.titulo),
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                  child: Row(
                                    children: [
                                      Column(
                                        children: [
                                          Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.06),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.history_rounded,
                                              size: 17,
                                              color: OmniConstants.textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${rec.distanciaKm.toStringAsFixed(1)} km',
                                            style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 9.5,
                                              color: OmniConstants.textDim,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              rec.titulo,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              rec.subtitulo,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 11.5, color: OmniConstants.textMuted),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right_rounded, size: 18, color: OmniConstants.textDim),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),

                      Material(
                        color: OmniConstants.darkSurface,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () {
                            final pos = appState.posicaoAtual;
                            final coord = OmniCoordenada(
                              lat: pos.lat + 0.018,
                              lng: pos.lng + 0.014,
                              endereco: 'Ponto no mapa (${(pos.lat + 0.018).toStringAsFixed(4)}, ${(pos.lng + 0.014).toStringAsFixed(4)})',
                            );
                            _selecionarDestino(appState, coord.endereco!, coord: coord);
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: OmniConstants.darkBorderSubtle),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.pin_drop_outlined, color: OmniConstants.neonCyan, size: 20),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Definir localização no mapa (GPS)',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, size: 18, color: OmniConstants.textDim),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                KeyedSubtree(
                  key: const ValueKey('omni_planner_footer_slot'),
                  child: (visibleAreaHeight >= 300)
                      ? Container(
                          padding: EdgeInsets.fromLTRB(16, keyboardOpen ? 6 : 10, 16, keyboardOpen ? 8 : 12),
                          decoration: const BoxDecoration(
                            color: OmniConstants.darkSurface,
                            border: Border(top: BorderSide(color: OmniConstants.darkBorder)),
                          ),
                          child: ElevatedButton(
                            onPressed: () => _confirmarRota(appState),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: OmniConstants.neonCyan,
                              foregroundColor: Colors.black,
                              minimumSize: Size(double.infinity, keyboardOpen ? 42 : 48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                estimativaPreview != null
                                    ? 'CALCULAR ROTA (${estimativaPreview.distanciaKm.toStringAsFixed(1)} KM · ~${estimativaPreview.duracaoMinutos} MIN)'
                                    : 'CALCULAR ROTA E VER OPÇÕES',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
        },
      ),
    );
  }
}

class _HeaderPillChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;
  final VoidCallback onTap;

  const _HeaderPillChip({
    required this.icon,
    required this.label,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? OmniConstants.neonCyan.withValues(alpha: 0.16) : OmniConstants.darkSurface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: highlighted ? OmniConstants.neonCyan : OmniConstants.darkBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: highlighted ? OmniConstants.neonCyan : OmniConstants.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: highlighted ? OmniConstants.neonCyan : Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: OmniConstants.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableAddressRow extends StatelessWidget {
  final Color dotColor;
  final bool isSquare;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _EditableAddressRow({
    super.key,
    required this.dotColor,
    required this.isSquare,
    required this.controller,
    this.focusNode,
    required this.hint,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: dotColor,
            shape: isSquare ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: isSquare ? BorderRadius.circular(2) : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          key: const ValueKey('omni_row_input_expanded'),
          child: TextField(
            key: ObjectKey(controller),
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(fontSize: 13, color: OmniConstants.textDim),
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _SavedPlaceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SavedPlaceTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: OmniConstants.darkSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: OmniConstants.darkBorderSubtle),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: OmniConstants.neonCyan),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: OmniConstants.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
