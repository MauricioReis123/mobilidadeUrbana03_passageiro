import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/omni_constants.dart';
import '../models/categoria_model.dart';
import '../models/corrida_model.dart';
import '../state/omni_app_state.dart';
import '../tools/mapas_service.dart';
import '../widgets/omni_booking_panel.dart';
import '../widgets/omni_map_canvas.dart';
import 'corrida_andamento_screen.dart';

/// Tela Dedicada de Solicitação de Viagem — Conectada ao OmniAppState e OSRM Driving
class OmniSolicitarCorridaScreen extends StatefulWidget {
  final String? categoriaPreSelecionada;

  const OmniSolicitarCorridaScreen({super.key, this.categoriaPreSelecionada});

  @override
  State<OmniSolicitarCorridaScreen> createState() => _OmniSolicitarCorridaScreenState();
}

class _OmniSolicitarCorridaScreenState extends State<OmniSolicitarCorridaScreen> {
  final TextEditingController _origemController = TextEditingController();
  final TextEditingController _destinoController = TextEditingController();
  final List<TextEditingController> _paradasControllers = [];

  OmniCoordenada? _origemCoord;
  OmniCoordenada? _destinoCoord;
  final List<OmniCoordenada?> _paradasCoords = [];

  late OmniCategoriaModel _categoriaSelecionada;
  String _metodoPagamento = 'pix';
  String _pixStatus = 'pendente';
  bool _solicitando = false;
  int _rotaSeq = 0;
  OmniEstimativaRota? _estimativaReal;

  @override
  void initState() {
    super.initState();
    _categoriaSelecionada = OmniCategoriaModel.categoriasPadrao.firstWhere(
      (c) => c.id == widget.categoriaPreSelecionada,
      orElse: () => OmniCategoriaModel.categoriasPadrao.first,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final appState = context.read<OmniAppState>();
      if (_origemController.text.isEmpty && appState.posicaoAtual.endereco != null) {
        _origemController.text = appState.posicaoAtual.endereco!;
        _origemCoord = appState.posicaoAtual;
      }
    });
  }

  @override
  void dispose() {
    _origemController.dispose();
    _destinoController.dispose();
    for (final c in _paradasControllers) {
      c.dispose();
    }
    super.dispose();
  }

  OmniCoordenada? _coordSeBate(OmniCoordenada? coord, String textoAtual) {
    if (coord == null) return null;
    if (coord.endereco != null && coord.endereco!.trim() != textoAtual.trim()) {
      return null;
    }
    return coord;
  }

  List<OmniCoordenada> _coletarParadasCoords(OmniAppState appState, String origemTexto, OmniCoordenada? origemCoord) {
    final list = <OmniCoordenada>[];
    for (int i = 0; i < _paradasControllers.length; i++) {
      final texto = _paradasControllers[i].text.trim();
      if (texto.isEmpty) continue;
      final coord = i < _paradasCoords.length ? _coordSeBate(_paradasCoords[i], texto) : null;
      if (coord != null) {
        list.add(coord);
      } else {
        final est = appState.calcularEstimativaDinamica(
          origemTexto: origemTexto,
          destinoTexto: texto,
          origemCoordenada: origemCoord,
        );
        list.add(est.pontosPolilinha.last);
      }
    }
    return list;
  }

  Future<void> _recalcularRotaReal(OmniAppState appState) async {
    final destinoTexto = _destinoController.text.trim();
    if (destinoTexto.isEmpty) {
      if (_estimativaReal != null) setState(() => _estimativaReal = null);
      return;
    }

    final origemTexto = _origemController.text.trim();
    final origemCoordEfetiva = _coordSeBate(_origemCoord, origemTexto) ?? appState.posicaoAtual;
    final destinoCoordEfetiva = _coordSeBate(_destinoCoord, destinoTexto);
    if (destinoCoordEfetiva == null) return;

    final paradasCoords = _coletarParadasCoords(appState, origemTexto, origemCoordEfetiva);
    final seq = ++_rotaSeq;
    final realEst = await OmniMapasService.calcularRotaRealComParadas(
      origem: OmniCoordenada(lat: origemCoordEfetiva.lat, lng: origemCoordEfetiva.lng, endereco: origemTexto),
      destino: OmniCoordenada(lat: destinoCoordEfetiva.lat, lng: destinoCoordEfetiva.lng, endereco: destinoTexto),
      paradas: paradasCoords,
    );
    if (!mounted || seq != _rotaSeq) return;
    setState(() => _estimativaReal = realEst);
  }

  Future<void> _confirmarSolicitacao() async {
    if (_destinoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o endereço de destino para solicitar a corrida.')),
      );
      return;
    }

    setState(() => _solicitando = true);
    final appState = context.read<OmniAppState>();
    final origemTexto = _origemController.text.trim();
    final destinoTexto = _destinoController.text.trim();
    final origemCoordEfetiva = _coordSeBate(_origemCoord, origemTexto);
    final destinoCoordEfetiva = _coordSeBate(_destinoCoord, destinoTexto);
    final paradas = _paradasControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    final paradasCoords = _coletarParadasCoords(appState, origemTexto, origemCoordEfetiva);

    OmniEstimativaRota estimativa = _estimativaReal ??
        appState.calcularEstimativaDinamica(
          origemTexto: origemTexto,
          destinoTexto: destinoTexto,
          paradasTextos: paradas,
          origemCoordenada: origemCoordEfetiva,
          destinoCoordenada: destinoCoordEfetiva,
          paradasCoordenadas: paradasCoords,
        );

    if (_estimativaReal == null && destinoCoordEfetiva != null) {
      final origemBase = origemCoordEfetiva ?? appState.posicaoAtual;
      estimativa = await OmniMapasService.calcularRotaRealComParadas(
        origem: origemBase,
        destino: destinoCoordEfetiva,
        paradas: paradasCoords,
      );
      if (!mounted) return;
    }

    final valor = _categoriaSelecionada.calcularValorEstimado(
      km: estimativa.distanciaKm,
      minutos: estimativa.duracaoMinutos,
      paradasCount: paradas.length,
    );

    final corrida = await appState.iniciarCorrida(
      origemEndereco: origemTexto,
      destinoEndereco: destinoTexto,
      paradas: paradas,
      origemCoordenada: origemCoordEfetiva,
      destinoCoordenada: destinoCoordEfetiva,
      paradasCoordenadas: paradasCoords,
      categoria: _categoriaSelecionada,
      valorFinal: valor,
      metodoPagamento: _metodoPagamento,
      perfilPagamento: 'pessoal',
      usarSaldoCarteira: false,
      preferencias: const OmniPreferenciasViagem(),
      distanciaKm: estimativa.distanciaKm,
      tempoMinutos: estimativa.duracaoMinutos,
      routeProvider: estimativa.routeProvider,
    );

    if (!mounted) return;
    setState(() => _solicitando = false);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => OmniCorridaAndamentoScreen(corridaInicial: corrida)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<OmniAppState>();
    final origemTexto = _origemController.text.trim();
    final destinoTexto = _destinoController.text.trim();
    final origemCoordEfetiva = _coordSeBate(_origemCoord, origemTexto);
    final destinoCoordEfetiva = _coordSeBate(_destinoCoord, destinoTexto);
    final paradas = _paradasControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();

    final estimativa = destinoTexto.isEmpty
        ? null
        : (_estimativaReal ??
            appState.calcularEstimativaDinamica(
              origemTexto: origemTexto,
              destinoTexto: destinoTexto,
              paradasTextos: paradas,
              origemCoordenada: origemCoordEfetiva,
              destinoCoordenada: destinoCoordEfetiva,
              paradasCoordenadas: _coletarParadasCoords(appState, origemTexto, origemCoordEfetiva),
            ));

    return Scaffold(
      backgroundColor: OmniConstants.darkBackground,
      appBar: AppBar(
        title: const Text('Confirmar Viagem', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 260,
                child: OmniMapCanvas(
                  origemEndereco: _origemController.text.isEmpty ? 'Localização atual' : _origemController.text,
                  destinoEndereco: _destinoController.text.isEmpty ? 'Defina o destino' : _destinoController.text,
                  paradas: _paradasControllers.map((c) => c.text).toList(),
                  motoristas: appState.motoristasOnline,
                  distanciaKm: estimativa?.distanciaKm ?? 0.0,
                  tempoMinutos: estimativa?.duracaoMinutos ?? 0,
                  onRecenterGps: () => appState.atualizarLocalizacaoGps(),
                ),
              ),
              const SizedBox(height: 16),
              OmniBookingPanel(
                categorias: OmniCategoriaModel.categoriasPadrao,
                categoriaSelecionada: _categoriaSelecionada,
                onSelectCategoria: (cat) => setState(() => _categoriaSelecionada = cat),
                metodoPagamento: _metodoPagamento,
                onSelectMetodoPagamento: (m) => setState(() => _metodoPagamento = m),
                origemController: _origemController,
                destinoController: _destinoController,
                paradasControllers: _paradasControllers,
                latReferencia: appState.posicaoAtual.lat,
                lngReferencia: appState.posicaoAtual.lng,
                gpsCarregando: appState.gpsCarregando,
                distanciaKm: estimativa?.distanciaKm,
                tempoMinutos: estimativa?.duracaoMinutos,
                onSelectOrigemCoord: (coord) {
                  setState(() {
                    _origemCoord = coord;
                    _estimativaReal = null;
                  });
                  unawaited(_recalcularRotaReal(appState));
                },
                onSelectDestinoCoord: (coord) {
                  setState(() {
                    _destinoCoord = coord;
                    _estimativaReal = null;
                  });
                  unawaited(_recalcularRotaReal(appState));
                },
                onSelectParadaCoord: (idx, coord) {
                  setState(() {
                    while (_paradasCoords.length <= idx) {
                      _paradasCoords.add(null);
                    }
                    _paradasCoords[idx] = coord;
                    _estimativaReal = null;
                  });
                  unawaited(_recalcularRotaReal(appState));
                },
                onTapGpsOrigem: () async {
                  await appState.atualizarLocalizacaoGps();
                  if (mounted && appState.posicaoAtual.endereco != null) {
                    setState(() {
                      _origemController.text = appState.posicaoAtual.endereco!;
                      _origemCoord = appState.posicaoAtual;
                      _estimativaReal = null;
                    });
                    unawaited(_recalcularRotaReal(appState));
                  }
                },
                onAddParada: () {
                  if (_paradasControllers.length < 3) {
                    setState(() {
                      _paradasControllers.add(TextEditingController());
                      _paradasCoords.add(null);
                      _estimativaReal = null;
                    });
                  }
                },
                onRemoveParada: (idx) {
                  setState(() {
                    final c = _paradasControllers.removeAt(idx);
                    c.dispose();
                    if (idx < _paradasCoords.length) {
                      _paradasCoords.removeAt(idx);
                    }
                    _estimativaReal = null;
                  });
                  unawaited(_recalcularRotaReal(appState));
                },
                onChangedTexto: () {
                  if (_estimativaReal != null) {
                    setState(() => _estimativaReal = null);
                  }
                },
                onConfirmar: _confirmarSolicitacao,
                solicitando: _solicitando,
                pixCopiaECola: OmniConstants.defaultPixCopiaECola,
                pixStatus: _pixStatus,
                onSimularPagamentoPix: () {
                  setState(() => _pixStatus = 'aprovado');
                  _confirmarSolicitacao();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
