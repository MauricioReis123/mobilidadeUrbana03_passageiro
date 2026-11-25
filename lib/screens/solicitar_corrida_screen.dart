import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/omni_constants.dart';
import '../models/categoria_model.dart';
import '../models/corrida_model.dart';
import '../state/omni_app_state.dart';
import '../tools/mapas_service.dart';
import '../tools/mercadopago_service.dart';
import '../widgets/omni_booking_panel.dart';
import '../widgets/omni_map_canvas.dart';
import '../widgets/ride_flow/omni_pix_payment_screen.dart';
import 'corrida_andamento_screen.dart';

/// Tela Dedicada de Solicitação de Viagem — Conectada ao OmniAppState, OSRM Driving e Mercado Pago Pix real
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
  String _pixIdTransacao = '';
  String _pixCopiaECola = OmniConstants.defaultPixCopiaECola;
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
        if (est.pontosPolilinha.isNotEmpty) {
          list.add(est.pontosPolilinha.last);
        }
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

  Future<void> _verificarOuGerarPix(OmniAppState appState) async {
    if (_pixIdTransacao.isNotEmpty) {
      final pago = await OmniMercadoPagoService.verificarLiquidacaoPix(_pixIdTransacao);
      if (!mounted) return;
      if (pago) {
        setState(() => _pixStatus = 'aprovado');
        await _confirmarSolicitacao();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pagamento Pix ainda aguardando liquidação no Mercado Pago.')),
      );
      return;
    }

    final est = _estimativaReal ??
        appState.calcularEstimativaDinamica(
          origemTexto: _origemController.text.trim(),
          destinoTexto: _destinoController.text.trim(),
          paradasTextos: _paradasControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList(),
          origemCoordenada: _coordSeBate(_origemCoord, _origemController.text.trim()),
          destinoCoordenada: _coordSeBate(_destinoCoord, _destinoController.text.trim()),
        );
    final valor = _categoriaSelecionada.calcularValorEstimado(
      km: est.distanciaKm,
      minutos: est.duracaoMinutos,
      paradasCount: _paradasControllers.where((c) => c.text.trim().isNotEmpty).length,
    );

    final cobranca = await OmniMercadoPagoService.gerarPixParaCorrida(
      rideId: 'trip_${DateTime.now().millisecondsSinceEpoch}',
      valor: valor,
      descricao: 'OMNI · ${_categoriaSelecionada.nome}',
      cpf: appState.passageiro.cpf.isNotEmpty ? appState.passageiro.cpf : '12345678909',
      email: appState.passageiro.email.isNotEmpty ? appState.passageiro.email : 'passageiro@omni.mobi',
      passengerId: appState.passageiro.id,
    );
    if (!mounted) return;
    if (cobranca != null && cobranca.copiaECola.isNotEmpty) {
      setState(() {
        _pixIdTransacao = cobranca.idTransacao;
        _pixCopiaECola = cobranca.copiaECola;
        _pixStatus = cobranca.status == 'approved' ? 'aprovado' : 'pendente';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cobrança Pix gerada via Mercado Pago!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível gerar o Pix no servidor neste momento.')),
      );
    }
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

    OmniCoordenada? origemCoordEfetiva = _coordSeBate(_origemCoord, origemTexto);
    if (origemCoordEfetiva == null && origemTexto.isNotEmpty) {
      origemCoordEfetiva = await OmniMapasService.geocodificarEnderecoPorTexto(
        query: origemTexto,
        latReferencia: appState.posicaoAtual.lat,
        lngReferencia: appState.posicaoAtual.lng,
      );
    }
    origemCoordEfetiva ??= appState.posicaoAtual;

    OmniCoordenada? destinoCoordEfetiva = _coordSeBate(_destinoCoord, destinoTexto);
    if (destinoCoordEfetiva == null) {
      destinoCoordEfetiva = await OmniMapasService.geocodificarEnderecoPorTexto(
        query: destinoTexto,
        latReferencia: origemCoordEfetiva.lat,
        lngReferencia: origemCoordEfetiva.lng,
      );
    }

    final paradas = _paradasControllers.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    final paradasCoords = <OmniCoordenada>[];
    for (int i = 0; i < _paradasControllers.length; i++) {
      final pText = _paradasControllers[i].text.trim();
      if (pText.isEmpty) continue;
      OmniCoordenada? pc = i < _paradasCoords.length ? _coordSeBate(_paradasCoords[i], pText) : null;
      pc ??= await OmniMapasService.geocodificarEnderecoPorTexto(
        query: pText,
        latReferencia: origemCoordEfetiva.lat,
        lngReferencia: origemCoordEfetiva.lng,
      );
      if (pc != null) paradasCoords.add(pc);
    }

    if (!mounted) return;

    OmniEstimativaRota estimativa;
    if (_estimativaReal != null) {
      estimativa = _estimativaReal!;
    } else if (destinoCoordEfetiva != null) {
      estimativa = await OmniMapasService.calcularRotaRealComParadas(
        origem: origemCoordEfetiva,
        destino: destinoCoordEfetiva,
        paradas: paradasCoords,
      );
      if (!mounted) return;
    } else {
      estimativa = appState.calcularEstimativaDinamica(
        origemTexto: origemTexto,
        destinoTexto: destinoTexto,
        paradasTextos: paradas,
        origemCoordenada: origemCoordEfetiva,
        destinoCoordenada: destinoCoordEfetiva,
        paradasCoordenadas: paradasCoords,
      );
    }

    final valor = _categoriaSelecionada.calcularValorEstimado(
      km: estimativa.distanciaKm,
      minutos: estimativa.duracaoMinutos,
      paradasCount: paradas.length,
    );

    OmniPixResumo? pixResumo;
    if (_metodoPagamento == 'pix' && _pixStatus != 'aprovado') {
      setState(() => _solicitando = false);
      final pago = await showOmniPixPaymentFlow(
        context,
        valorTotal: valor,
        categoriaNome: _categoriaSelecionada.nome,
        copiaECola: _pixCopiaECola,
      );
      if (!mounted || pago != true) return;
      setState(() {
        _pixStatus = 'aprovado';
        _solicitando = true;
      });
    }
    if (_metodoPagamento == 'pix') {
      pixResumo = OmniPixResumo(
        idTransacao: _pixIdTransacao.isNotEmpty
            ? _pixIdTransacao
            : 'pix_${DateTime.now().millisecondsSinceEpoch}',
        copiaECola: _pixCopiaECola,
        expiraEm: '03:00',
        status: _pixStatus,
      );
    }

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
      pixCobranca: pixResumo,
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
                  onRecenterGps: () async {
                    await appState.atualizarLocalizacaoGps(forceRefresh: true);
                    if (!mounted) return;
                    setState(() {
                      if (appState.posicaoAtual.endereco != null) {
                        _origemController.text = appState.posicaoAtual.endereco!;
                      }
                      _origemCoord = appState.posicaoAtual;
                      _estimativaReal = null;
                    });
                    unawaited(_recalcularRotaReal(appState));
                  },
                  precisaoMetros: appState.gpsPrecisaoMetros,
                  precisaoReduzidaAlerta: appState.precisaoReduzidaAlerta,
                  onAjustarPinoOrigem: (dLat, dLng) => appState.ajustarPinoOrigem(
                    dLat,
                    dLng,
                    onEnderecoResolvido: (pos) {
                      if (!mounted) return;
                      setState(() {
                        if (pos.endereco != null && pos.endereco!.isNotEmpty) {
                          _origemController.text = pos.endereco!;
                        }
                        _origemCoord = pos;
                        _estimativaReal = null;
                      });
                      unawaited(_recalcularRotaReal(appState));
                    },
                  ),
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
                  await appState.atualizarLocalizacaoGps(forceRefresh: true);
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
                pixCopiaECola: _pixCopiaECola,
                pixStatus: _pixStatus,
                onVerificarPix: () => _verificarOuGerarPix(appState),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
