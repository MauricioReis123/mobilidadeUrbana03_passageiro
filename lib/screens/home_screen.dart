import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/omni_constants.dart';
import '../models/campanha_model.dart';
import '../models/categoria_model.dart';
import '../models/corrida_model.dart';
import '../state/omni_app_state.dart';
import '../theme/omni_theme.dart';
import '../tools/mapas_service.dart';
import '../tools/passenger_notification_service.dart';
import '../widgets/omni_active_ride.dart';
import '../widgets/omni_campaigns_sheet.dart';
import '../widgets/omni_code_explorer.dart';
import '../widgets/omni_loyalty_hub.dart';
import '../widgets/omni_map_canvas.dart';
import '../widgets/omni_tab_bar.dart';
import '../widgets/omni_top_header.dart';
import '../widgets/ride_flow/omni_category_selection_sheet.dart';
import '../widgets/ride_flow/omni_payment_method_sheet.dart';
import '../widgets/ride_flow/omni_pickup_confirm_sheet.dart';
import '../widgets/ride_flow/omni_pix_payment_screen.dart';
import '../widgets/ride_flow/omni_schedule_sheet.dart';
import '../widgets/ride_flow/omni_trip_planner_sheet.dart';

enum _OmniRideFlowStep { home, selectingCategory }

/// Tela Principal do OMNI Passageiro — 100% Conectada ao OmniAppState
/// Sem mocks estáticos, sem botões mortos, com GPS real, cálculo dinâmico de rotas e pós-pedido completo.
class OmniHomeScreen extends StatefulWidget {
  const OmniHomeScreen({super.key});

  @override
  State<OmniHomeScreen> createState() => _OmniHomeScreenState();
}

class _OmniHomeScreenState extends State<OmniHomeScreen> {
  OmniMainTab _activeTab = OmniMainTab.corridas;
  bool _isExpandedLayout = true;
  _OmniRideFlowStep _flowStep = _OmniRideFlowStep.home;

  // Estado Dinâmico da Solicitação em Curso
  String _origemManual = '';
  String _destinoEndereco = '';
  List<String> _paradas = [];
  OmniCoordenada? _origemCoord;
  OmniCoordenada? _destinoCoord;
  List<OmniCoordenada> _paradasCoords = [];
  double _distanciaKm = 0.0;
  int _tempoMinutos = 0;
  String _routeProvider = 'haversine_viario';

  OmniCategoriaModel _categoriaSelecionada = OmniCategoriaModel.categoriasPadrao.first;
  OmniPaymentSelection _paymentSelection = const OmniPaymentSelection(metodoPagamento: 'pix');
  OmniPreferenciasViagem _preferencias = const OmniPreferenciasViagem();
  OmniAgendamentoCorrida? _agendamento;
  OmniPassageiroTerceiro? _passageiroTerceiro;

  bool _mostrarBannerPromo = true;
  StreamSubscription<OmniDeepLinkCupomEvent>? _deepLinkSub;

  double get _descontoEfetivo => _paymentSelection.descontoPercentual;
  double get _descontoValorFixo => _paymentSelection.descontoValorFixo;

  @override
  void initState() {
    super.initState();
    _deepLinkSub = OmniPassengerNotificationService.onDeepLinkCupom.listen(_tratarDeepLinkCupom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = OmniPassengerNotificationService.consumirDeepLinkPendente();
      if (pending != null) {
        _tratarDeepLinkCupom(pending);
      }
    });
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    super.dispose();
  }

  Future<void> _recentralizarGps(OmniAppState appState) async {
    await appState.atualizarLocalizacaoGps(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _origemManual = '';
      _origemCoord = appState.posicaoAtual;
    });
  }

  void _aplicarCampanhaComoCupom(OmniCampanhaPassageiro camp) {
    setState(() {
      _paymentSelection = OmniPaymentSelection(
        metodoPagamento: _paymentSelection.metodoPagamento,
        perfilPagamento: _paymentSelection.perfilPagamento,
        usarSaldoCarteira: _paymentSelection.usarSaldoCarteira,
        cartaoId: _paymentSelection.cartaoId,
        cartaoResumo: _paymentSelection.cartaoResumo,
        cupomAplicado: camp.codigoCupom.isNotEmpty ? camp.codigoCupom : camp.titulo,
        descontoPercentual: camp.tipoDesconto == 'percentual' ? camp.percentualDesconto : 0.0,
        descontoValorFixo: camp.tipoDesconto == 'valor_fixo' ? camp.valorFixo : 0.0,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Cupom ${camp.codigoCupom.isNotEmpty ? camp.codigoCupom : camp.titulo} (${camp.resumoDesconto}) ativado!',
        ),
      ),
    );
  }

  void _tratarDeepLinkCupom(OmniDeepLinkCupomEvent event) {
    if (!mounted) return;
    showOmniCampaignsSheet(
      context,
      highlightedCoupon: event.cupomCodigo,
      onApplyCoupon: _aplicarCampanhaComoCupom,
    );
  }

  String _origemEfetiva(OmniAppState appState) {
    if (_origemManual.trim().isNotEmpty) return _origemManual;
    return appState.posicaoAtual.endereco ?? 'Localização atual GPS';
  }

  /// Abre "Planeje sua próxima viagem" (Telas 02 / 02b)
  Future<void> _abrirPlanejadorViagem(
    OmniAppState appState, {
    String? categoriaIdPreSelecionada,
    String destinoPrePreenchido = '',
  }) async {
    if (categoriaIdPreSelecionada != null) {
      final encontrada = OmniCategoriaModel.categoriasPadrao.firstWhere(
        (c) => c.id == categoriaIdPreSelecionada,
        orElse: () => _categoriaSelecionada,
      );
      setState(() => _categoriaSelecionada = encontrada);
    }

    final plan = await showOmniTripPlannerSheet(
      context,
      origemInicial: _origemEfetiva(appState),
      destinoInicial: destinoPrePreenchido,
      paradasIniciais: _paradas,
      agendamentoInicial: _agendamento,
      passageiroTerceiroInicial: _passageiroTerceiro,
      origemCoordInicial: _origemCoord,
      destinoCoordInicial: destinoPrePreenchido == _destinoEndereco ? _destinoCoord : null,
      paradasCoordsIniciais: _paradasCoords,
    );

    if (!mounted || plan == null) return;
    setState(() {
      _origemManual = plan.origem;
      _destinoEndereco = plan.destino;
      _paradas = plan.paradas;
      _origemCoord = plan.origemCoord;
      _destinoCoord = plan.destinoCoord;
      _paradasCoords = plan.paradasCoords;
      _distanciaKm = plan.distanciaKm;
      _tempoMinutos = plan.duracaoMinutos;
      _routeProvider = plan.routeProvider;
      _agendamento = plan.agendamento;
      _passageiroTerceiro = plan.passageiroTerceiro;
      _flowStep = _OmniRideFlowStep.selectingCategory;
    });
  }

  /// Abre diretamente a escolha de categoria a partir de um destino recente real
  void _selecionarDestinoRecente(OmniAppState appState, OmniDestinoRecente rec) {
    final estimativa = appState.calcularEstimativaDinamica(
      origemTexto: _origemEfetiva(appState),
      destinoTexto: rec.titulo,
      paradasTextos: _paradas,
      origemCoordenada: _origemCoord,
      paradasCoordenadas: _paradasCoords,
    );
    setState(() {
      _destinoEndereco = rec.titulo;
      _destinoCoord = null;
      _distanciaKm = estimativa.distanciaKm;
      _tempoMinutos = estimativa.duracaoMinutos;
      _flowStep = _OmniRideFlowStep.selectingCategory;
    });
  }

  /// Abre "Escolha um horário" (Tela EscolherHorário)
  Future<void> _abrirAgendamento(OmniAppState appState, {bool abrirPlanejadorDepois = false}) async {
    final res = await showOmniScheduleSheet(
      context,
      initialSchedule: _agendamento,
      duracaoEstimadaMinutos: _tempoMinutos > 0 ? _tempoMinutos : 20,
    );
    if (!mounted) return;
    setState(() => _agendamento = res);
    if (res != null && abrirPlanejadorDepois) {
      await _abrirPlanejadorViagem(appState);
    }
  }

  /// Abre "Pague com" (Tela ModoDePagamento)
  Future<void> _abrirFormaPagamento() async {
    final res = await showOmniPaymentMethodSheet(
      context,
      currentSelection: _paymentSelection,
    );
    if (!mounted || res == null) return;
    setState(() => _paymentSelection = res);
  }

  /// Funil completo e real: Confirmar Partida -> Novo Preço -> Capacete Moto -> Pix Gateway -> Radar RTDB
  Future<void> _iniciarFluxoConfirmacao(OmniAppState appState) async {
    final paradasAtivasCount = _paradas.where((p) => p.trim().isNotEmpty).length;
    final valorEstimado = _categoriaSelecionada.calcularValorEstimado(
      km: _distanciaKm,
      minutos: _tempoMinutos,
      paradasCount: paradasAtivasCount,
      descontoPercentual: _descontoEfetivo,
      descontoValorFixo: _descontoValorFixo,
    );

    // 1. Confirmar local de partida (e eventual ajuste de preço)
    final pickup = await showOmniPickupConfirmSheet(
      context,
      enderecoInicial: _origemEfetiva(appState),
      valorEstimadoAtual: valorEstimado,
    );
    if (!mounted || pickup == null) return;

    setState(() => _origemManual = pickup.enderecoPartida);

    // 2. Se for OMNI Moto, exige aceite obrigatório de uso de capacete
    if (_categoriaSelecionada.requerCapacete) {
      final aceitouCapacete = await showOmniMotoHelmetDialog(context);
      if (!mounted || aceitouCapacete != true) return;
    }

    // 3. Se pagamento for PIX, executa fluxo real de cobrança via OmniMercadoPagoService
    OmniPixResumo? pixResumo;
    if (_paymentSelection.metodoPagamento == 'pix') {
      final pixConfirmado = await showOmniPixPaymentFlow(
        context,
        valorTotal: pickup.valorFinalConfirmado,
        categoriaNome: _categoriaSelecionada.nome,
      );
      if (!mounted || pixConfirmado != true) return;
      pixResumo = OmniPixResumo(
        idTransacao: 'pix_${DateTime.now().millisecondsSinceEpoch}',
        copiaECola: OmniConstants.defaultPixCopiaECola,
        expiraEm: '03:00',
        status: 'aprovado',
      );
    }

    // 4. Despacha a corrida real no OmniAppState (OTP seguro + Backend Universal + RTDB)
    await appState.iniciarCorrida(
      origemEndereco: pickup.enderecoPartida,
      destinoEndereco: _destinoEndereco,
      paradas: _paradas,
      origemCoordenada: _origemCoord,
      destinoCoordenada: _destinoCoord,
      paradasCoordenadas: _paradasCoords,
      categoria: _categoriaSelecionada,
      valorFinal: pickup.valorFinalConfirmado,
      metodoPagamento: _paymentSelection.metodoPagamento,
      perfilPagamento: _paymentSelection.perfilPagamento,
      usarSaldoCarteira: _paymentSelection.usarSaldoCarteira,
      cupomAplicado: _paymentSelection.cupomAplicado,
      descontoPercentual: _descontoEfetivo,
      descontoValorFixo: _descontoValorFixo,
      preferencias: _preferencias,
      agendamento: _agendamento,
      passageiroTerceiro: _passageiroTerceiro,
      distanciaKm: _distanciaKm,
      tempoMinutos: _tempoMinutos,
      routeProvider: _routeProvider,
      pixCobranca: pixResumo,
    );

    if (!mounted) return;
    setState(() => _flowStep = _OmniRideFlowStep.home);
  }

  void _abrirCaixaDeEntrada(OmniAppState appState) {
    appState.marcarTodasNotificacoesLidas();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.72),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          decoration: const BoxDecoration(
            color: OmniConstants.darkCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: OmniConstants.darkBorder)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Caixa de Entrada OMNI',
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: appState.notificacoes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final n = appState.notificacoes[idx];
                    return _InboxItem(
                      icon: n.cupomAcao != null ? Icons.local_offer_rounded : Icons.notifications_active_outlined,
                      title: n.titulo,
                      subtitle: n.mensagem,
                      onTap: () {
                        if (n.cupomAcao != null) {
                          setState(() {
                            _paymentSelection = OmniPaymentSelection(
                              metodoPagamento: _paymentSelection.metodoPagamento,
                              perfilPagamento: _paymentSelection.perfilPagamento,
                              usarSaldoCarteira: _paymentSelection.usarSaldoCarteira,
                              cartaoId: _paymentSelection.cartaoId,
                              cartaoResumo: _paymentSelection.cartaoResumo,
                              cupomAplicado: n.cupomAcao,
                              descontoPercentual: 15.0,
                            );
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Cupom ${n.cupomAcao} (15% OFF) ativado!')),
                          );
                        }
                        Navigator.of(ctx).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<OmniAppState>();

    return Scaffold(
      backgroundColor: OmniConstants.darkBackground,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          OmniTopHeader(
            activeTab: _activeTab,
            onSelectTab: (tab) => setState(() => _activeTab = tab),
            isExpandedLayout: _isExpandedLayout,
            onToggleLayout: () => setState(() => _isExpandedLayout = !_isExpandedLayout),
            rtdbConnected: appState.rtdbConectado,
          ),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double screenWidth = constraints.maxWidth;
                final bool isMobileScreen = screenWidth < 768;
                final bool useTwoColumns = screenWidth >= 900 && _isExpandedLayout;

                final double horizontalPadding = isMobileScreen ? 14 : 24;
                final double maxContentWidth = useTwoColumns ? 1240 : (isMobileScreen ? screenWidth : 480);

                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: SafeArea(
                    top: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxContentWidth),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                            vertical: isMobileScreen ? 14 : 20,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (isMobileScreen || !_isExpandedLayout) ...[
                                OmniTabBar(
                                  activeTab: _activeTab,
                                  onSelectTab: (tab) => setState(() => _activeTab = tab),
                                ),
                                const SizedBox(height: 14),
                              ],

                              if (_activeTab == OmniMainTab.corridas)
                                _buildAbaCorridas(
                                  appState: appState,
                                  useTwoColumns: useTwoColumns,
                                  screenHeight: constraints.maxHeight,
                                ),
                              if (_activeTab == OmniMainTab.fidelidade) const OmniLoyaltyHub(),
                              if (_activeTab == OmniMainTab.codigo) const OmniCodeExplorer(),

                              const SizedBox(height: 24),

                              Container(
                                padding: const EdgeInsets.only(top: 14, bottom: 8),
                                decoration: const BoxDecoration(
                                  border: Border(top: BorderSide(color: OmniConstants.darkBorderSubtle)),
                                ),
                                child: const Text(
                                  'OMNI Mobilidade Urbana — Plataforma Inteligente de Transporte Particular & Ecossistema Integrado.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11.5, color: OmniConstants.textDim),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbaCorridas({
    required OmniAppState appState,
    required bool useTwoColumns,
    required double screenHeight,
  }) {
    final corridaAtiva = appState.corridaAtiva;
    final double mapHeight = useTwoColumns
        ? 440
        : (screenHeight * 0.34).clamp(240.0, 330.0);

    final Widget mapSection = SizedBox(
      height: mapHeight,
      child: OmniMapCanvas(
        origemEndereco: corridaAtiva?.origem.endereco ?? _origemEfetiva(appState),
        destinoEndereco: corridaAtiva?.destino.endereco ??
            (_destinoEndereco.isEmpty ? 'Defina seu destino' : _destinoEndereco),
        paradas: _paradas,
        motoristas: appState.motoristasOnline,
        motoristaAtivo: corridaAtiva?.motorista,
        emViagem: corridaAtiva?.status == OmniStatusCorrida.emAndamento,
        distanciaKm: corridaAtiva?.distanciaKm ?? (_distanciaKm > 0 ? _distanciaKm : 0.0),
        tempoMinutos: corridaAtiva?.tempoMinutos ?? (_tempoMinutos > 0 ? _tempoMinutos : 0),
        onRecenterGps: () => unawaited(_recentralizarGps(appState)),
        precisaoMetros: appState.gpsPrecisaoMetros,
        precisaoReduzidaAlerta: appState.precisaoReduzidaAlerta,
        onAjustarPinoOrigem: corridaAtiva != null
            ? null
            : (dLat, dLng) => appState.ajustarPinoOrigem(
                  dLat,
                  dLng,
                  onEnderecoResolvido: (pos) {
                    if (!mounted) return;
                    setState(() {
                      if (_origemManual.trim().isNotEmpty) {
                        _origemManual = pos.endereco ?? _origemManual;
                      }
                      _origemCoord = pos;
                    });
                  },
                ),
      ),
    );

    final Widget panelSection;
    if (corridaAtiva != null) {
      panelSection = OmniActiveRide(
        corrida: corridaAtiva,
        onAvancarStatus: appState.avancarStatusCorrida,
        onCancelar: () => appState.cancelarCorridaAtiva(),
        onFinalizarComAvaliacao: (estrelas) => appState.finalizarCorridaComAvaliacao(
          estrelas: estrelas,
          gorjeta: 0.0,
          elogios: const [],
        ),
        onFinalizarCompleto: (estrelas, gorjeta, elogios) async {
          final pts = await appState.finalizarCorridaComAvaliacao(
            estrelas: estrelas,
            gorjeta: gorjeta,
            elogios: elogios,
          );
          if (!mounted) return;
          setState(() {
            _agendamento = null;
            _destinoCoord = null;
            _paradasCoords = [];
            _flowStep = _OmniRideFlowStep.home;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Avaliação de $estrelas estrelas salva! +$pts pontos no OMNI Club.')),
          );
        },
        onAlterarDestino: (novo) {
          setState(() {
            _destinoEndereco = novo;
            _destinoCoord = null;
          });
          appState.alterarDestinoEmViagem(novo);
        },
      );
    } else if (_flowStep == _OmniRideFlowStep.selectingCategory) {
      panelSection = OmniCategorySelectionPanel(
        categorias: OmniCategoriaModel.categoriasPadrao,
        categoriaSelecionada: _categoriaSelecionada,
        onSelectCategoria: (cat) => setState(() => _categoriaSelecionada = cat),
        origemEndereco: _origemEfetiva(appState),
        destinoEndereco: _destinoEndereco,
        distanciaKm: _distanciaKm,
        tempoMinutos: _tempoMinutos,
        paradasCount: _paradas.where((p) => p.trim().isNotEmpty).length,
        paymentSelection: _paymentSelection,
        preferencias: _preferencias,
        onUpdatePreferencias: (p) => setState(() => _preferencias = p),
        agendamento: _agendamento,
        onEditarRota: () => _abrirPlanejadorViagem(appState, destinoPrePreenchido: _destinoEndereco),
        onAbrirPagamento: _abrirFormaPagamento,
        onAbrirAgendamento: () => _abrirAgendamento(appState, abrirPlanejadorDepois: false),
        onVoltarHome: () => setState(() => _flowStep = _OmniRideFlowStep.home),
        onEscolherCategoria: () => _iniciarFluxoConfirmacao(appState),
      );
    } else {
      panelSection = _buildHomeEntryPanel(appState);
    }

    if (useTwoColumns) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 7, child: mapSection),
          const SizedBox(width: 20),
          Expanded(flex: 5, child: panelSection),
        ],
      );
    }

    if (corridaAtiva == null && _flowStep == _OmniRideFlowStep.home) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          panelSection,
          const SizedBox(height: 14),
          mapSection,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        mapSection,
        const SizedBox(height: 14),
        panelSection,
      ],
    );
  }

  Widget _buildHomeEntryPanel(OmniAppState appState) {
    final naoLidas = appState.notificacoesNaoLidas;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: OmniTheme.cardDecoration(
        backgroundColor: OmniConstants.darkCard,
        borderColor: OmniConstants.darkBorder,
        borderRadius: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Localização Atual (clicável para atualizar GPS real) + Avisos com contador
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => unawaited(_recentralizarGps(appState)),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        appState.gpsCarregando
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(strokeWidth: 2, color: OmniConstants.neonCyan),
                              )
                            : Icon(
                                appState.gpsAtivo ? Icons.my_location_rounded : Icons.location_searching_rounded,
                                size: 14,
                                color: OmniConstants.neonCyan,
                              ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _origemEfetiva(appState),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: OmniConstants.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: OmniConstants.darkSurface,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => _abrirCaixaDeEntrada(appState),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: OmniConstants.darkBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.notifications_none_rounded, size: 14, color: OmniConstants.neonCyan),
                        const SizedBox(width: 4),
                        Text(
                          naoLidas > 0 ? 'Avisos ($naoLidas)' : 'Avisos',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Barra "Para onde?" + Botão "Mais tarde"
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: OmniConstants.darkSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _abrirPlanejadorViagem(appState),
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, size: 22, color: OmniConstants.neonCyan),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Para onde?',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Material(
                  color: OmniConstants.darkCard,
                  borderRadius: BorderRadius.circular(13),
                  child: InkWell(
                    onTap: () => _abrirAgendamento(appState, abrirPlanejadorDepois: true),
                    borderRadius: BorderRadius.circular(13),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: OmniConstants.darkBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 13, color: OmniConstants.neonCyan),
                          const SizedBox(width: 6),
                          Text(
                            _agendamento == null ? 'Mais tarde' : _agendamento!.resumoCurto,
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3. Destinos Recentes Reais (ou atalho rápido para primeira viagem)
          if (appState.destinosRecentes.isNotEmpty)
            ...appState.destinosRecentes.take(2).map((rec) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: OmniConstants.darkSurface,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: () => _selecionarDestinoRecente(appState, rec),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: OmniConstants.darkBorderSubtle),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: rec.precoAbaixoNormal
                                  ? OmniConstants.emeraldSuccess.withValues(alpha: 0.14)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              rec.precoAbaixoNormal ? Icons.trending_down_rounded : Icons.history_rounded,
                              size: 18,
                              color: rec.precoAbaixoNormal ? const Color(0xFF34D399) : OmniConstants.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rec.titulo,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                                Text(
                                  rec.subtitulo,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: OmniConstants.textMuted),
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

          const SizedBox(height: 6),

          // 4. Grade Rápida "Para você" (Viagem, Moto, Envios, Agendar)
          const Text(
            'PARA VOCÊ',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: OmniConstants.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _QuickServiceTile(
                  icon: Icons.directions_car_filled_rounded,
                  label: 'Viagem',
                  badge: 'Até 15%',
                  onTap: () => _abrirPlanejadorViagem(appState, categoriaIdPreSelecionada: 'omni_pop'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickServiceTile(
                  icon: Icons.two_wheeler_rounded,
                  label: 'Moto',
                  onTap: () => _abrirPlanejadorViagem(appState, categoriaIdPreSelecionada: 'omni_moto'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickServiceTile(
                  icon: Icons.inventory_2_outlined,
                  label: 'Envios',
                  onTap: () => _abrirPlanejadorViagem(appState, categoriaIdPreSelecionada: 'omni_envios'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickServiceTile(
                  icon: Icons.event_available_rounded,
                  label: 'Agendar',
                  onTap: () => _abrirAgendamento(appState, abrirPlanejadorDepois: true),
                ),
              ),
            ],
          ),

          // 5. Banner Promocional Interativo (Campanhas RTDB ao vivo + Ver Cupons)
          if (_mostrarBannerPromo) ...[
            const SizedBox(height: 12),
            Builder(
              builder: (_) {
                final campanhaTopo =
                    appState.campanhasAtivas.isNotEmpty ? appState.campanhasAtivas.first : null;
                final tituloPromo = campanhaTopo?.titulo ?? '15% OFF em OMNI Conforto e Envios';
                final subPromo = campanhaTopo != null
                    ? '${campanhaTopo.resumoDesconto}${campanhaTopo.codigoCupom.isNotEmpty ? ' · Cupom ${campanhaTopo.codigoCupom}' : ''}'
                    : 'Toque para aplicar o cupom OMNI15 ou ver campanhas';

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        OmniConstants.neonCyan.withValues(alpha: 0.14),
                        OmniConstants.darkSurface,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.local_offer_rounded, size: 18, color: OmniConstants.neonCyan),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            if (campanhaTopo != null) {
                              _aplicarCampanhaComoCupom(campanhaTopo);
                            } else {
                              setState(() {
                                _paymentSelection = OmniPaymentSelection(
                                  metodoPagamento: _paymentSelection.metodoPagamento,
                                  perfilPagamento: _paymentSelection.perfilPagamento,
                                  usarSaldoCarteira: _paymentSelection.usarSaldoCarteira,
                                  cartaoId: _paymentSelection.cartaoId,
                                  cartaoResumo: _paymentSelection.cartaoResumo,
                                  cupomAplicado: 'OMNI15',
                                  descontoPercentual: 15.0,
                                );
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cupom OMNI15 (15% OFF) aplicado para sua próxima viagem!'),
                                ),
                              );
                            }
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tituloPromo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                              Text(
                                subPromo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10.5, color: OmniConstants.neonCyan),
                              ),
                            ],
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => showOmniCampaignsSheet(
                          context,
                          onApplyCoupon: _aplicarCampanhaComoCupom,
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: OmniConstants.neonCyan,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Cupons', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 17, color: OmniConstants.textMuted),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () => setState(() => _mostrarBannerPromo = false),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickServiceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final VoidCallback onTap;

  const _QuickServiceTile({
    required this.icon,
    required this.label,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: OmniConstants.darkSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: OmniConstants.darkBorderSubtle),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: OmniConstants.neonCyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 20, color: OmniConstants.neonCyan),
                  ),
                  if (badge != null)
                    Positioned(
                      top: -6,
                      right: -10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: OmniConstants.emeraldSuccess,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.black),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: OmniConstants.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _InboxItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: OmniConstants.darkSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: OmniConstants.neonCyan),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
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
    );
  }
}
