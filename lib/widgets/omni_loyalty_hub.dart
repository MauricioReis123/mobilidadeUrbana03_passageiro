import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/omni_integration_contracts.dart';
import '../constants/omni_constants.dart';
import '../models/fidelidade_model.dart';
import '../models/pacote_model.dart';
import '../state/omni_app_state.dart';
import '../theme/omni_theme.dart';
import '../tools/backends_service.dart';
import '../tools/firebase_service.dart';
import 'ride_flow/omni_pix_payment_screen.dart';

/// Hub Executivo de Fidelidade, Pacotes, Histórico Real, Indique & Ganhe e Viagens Particulares
/// 100% conectado ao OmniAppState e Firebase RTDB (sem pontos/códigos/estatísticas fictícias chumbadas).
class OmniLoyaltyHub extends StatefulWidget {
  const OmniLoyaltyHub({super.key});

  @override
  State<OmniLoyaltyHub> createState() => _OmniLoyaltyHubState();
}

class _OmniLoyaltyHubState extends State<OmniLoyaltyHub> {
  int _subTabIndex = 0; // 0: Níveis, 1: Pacotes, 2: Histórico, 3: Indique, 4: Particular
  bool _copiadoCodigo = false;
  String? _ofertaPrivadaAtivaId;
  String? _ofertaPrivadaResumo;

  Color _parseHexColor(String hex) {
    final clean = hex.replaceAll('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  }

  Future<void> _copiarCodigoIndicacao(String codigo) async {
    await Clipboard.setData(ClipboardData(text: codigo));
    if (!mounted) return;
    setState(() => _copiadoCodigo = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Código $codigo copiado! Compartilhe com seus amigos.')),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiadoCodigo = false);
    });
  }

  Future<void> _adquirirPacoteViaPix(OmniAppState appState, OmniPacoteModel pkg) async {
    if (appState.pacotesAtivosIds.contains(pkg.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${pkg.titulo} já está ativo na sua conta!')),
      );
      return;
    }

    final pago = await showOmniPixPaymentFlow(
      context,
      valorTotal: pkg.valorComDesconto,
      categoriaNome: pkg.titulo,
      rideId: 'pkg_${pkg.id}_${DateTime.now().millisecondsSinceEpoch}',
    );

    if (pago == true && mounted) {
      await appState.ativarPacote(pkg);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${pkg.titulo} ativado com sucesso na sua carteira OMNI!')),
      );
    }
  }

  void _abrirModalOrcamentoParticular({String modalidadeInicial = 'Translado Aeroporto Executivo'}) {
    final TextEditingController trajetoCtrl = TextEditingController();
    final TextEditingController dataCtrl = TextEditingController();
    String modalidade = modalidadeInicial;
    bool enviando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          return SafeArea(
            child: Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.84),
              padding: EdgeInsets.only(bottom: bottomInset),
              decoration: const BoxDecoration(
                color: OmniConstants.darkCard,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: OmniConstants.darkBorder)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'SOLICITAR ORÇAMENTO PARTICULAR',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              color: OmniConstants.neonCyan,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Concierge Executivo OMNI',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              'Translado Aeroporto Executivo',
                              'Motorista por Diária (8 horas)',
                              'Viagens Intermunicipais',
                            ].map((m) {
                              final sel = modalidade == m;
                              return InkWell(
                                onTap: () => setModalState(() => modalidade = m),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: sel ? OmniConstants.neonCyan : OmniConstants.darkSurface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: sel ? OmniConstants.neonCyan : OmniConstants.darkBorder,
                                    ),
                                  ),
                                  child: Text(
                                    m,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: sel ? Colors.black : OmniConstants.textSecondary,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: dataCtrl,
                            style: const TextStyle(fontSize: 13, color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Data e horário desejado',
                              hintText: 'Ex: 25/11 às 08:30',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: trajetoCtrl,
                            maxLines: 2,
                            style: const TextStyle(fontSize: 13, color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Origem, destino ou roteiro',
                              hintText: 'Informe endereço de partida e destino',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                    decoration: const BoxDecoration(
                      color: OmniConstants.darkSurface,
                      border: Border(top: BorderSide(color: OmniConstants.darkBorder)),
                    ),
                    child: ElevatedButton(
                      onPressed: enviando
                          ? null
                          : () async {
                              if (trajetoCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Informe o roteiro desejado para enviar ao Concierge.')),
                                );
                                return;
                              }
                              setModalState(() => enviando = true);
                              final passengerId = context.read<OmniAppState>().passageiro.id;
                              final roteiroTxt = trajetoCtrl.text.trim();
                              final dataTxt = dataCtrl.text.trim();
                              final res = await OmniBackendUniversal.executar(
                                OmniBackendMethods.privateOfferCreate,
                                args: {
                                  'modalidade': modalidade,
                                  'data_horario': dataTxt,
                                  'roteiro': roteiroTxt,
                                  'passenger_id': passengerId,
                                },
                              );
                              String offerId = '';
                              if (res.sucesso && res.dados is Map) {
                                offerId = ((res.dados as Map)['offer_id'] ?? '').toString();
                              }
                              if (offerId.isEmpty) {
                                offerId = 'offer_${DateTime.now().millisecondsSinceEpoch}';
                                await OmniFirebaseService.publicarOfertaPrivada(offerId, {
                                  'offer_id': offerId,
                                  'passenger_id': passengerId,
                                  'modality': modalidade,
                                  'scheduled_for': dataTxt,
                                  'itinerary': roteiroTxt,
                                  'status': 'OPEN',
                                  'created_at': DateTime.now().toUtc().toIso8601String(),
                                });
                              }
                              if (!ctx.mounted) return;
                              Navigator.of(ctx).pop();
                              if (!mounted) return;
                              setState(() {
                                _ofertaPrivadaAtivaId = offerId;
                                _ofertaPrivadaResumo = '$modalidade · $roteiroTxt';
                              });
                              await context.read<OmniAppState>().registrarProtocoloSuporte(
                                'Concierge · $modalidade',
                                roteiroTxt,
                              );
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Oferta "$offerId" publicada! Aguardando lances em tempo real.')),
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OmniConstants.neonCyan,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: enviando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Text(
                              'ENVIAR SOLICITAÇÃO AO CONCIERGE',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      trajetoCtrl.dispose();
      dataCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<OmniAppState>();
    const List<String> subTabs = [
      'Níveis de Fidelidade',
      'Pacotes de Viagens',
      'Histórico',
      'Indique & Ganhe',
      'Viagens Particulares',
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: OmniTheme.cardDecoration(
        backgroundColor: OmniConstants.darkCard,
        borderColor: OmniConstants.darkBorder,
        borderRadius: 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: OmniConstants.darkSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OmniConstants.darkBorderSubtle),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: subTabs.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final label = entry.value;
                  final active = _subTabIndex == idx;

                  return Padding(
                    padding: EdgeInsets.only(right: idx < subTabs.length - 1 ? 6 : 0),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() => _subTabIndex = idx),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          constraints: const BoxConstraints(minHeight: 38),
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                          decoration: BoxDecoration(
                            color: active ? OmniConstants.neonCyan : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              label,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: active ? Colors.black : OmniConstants.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 18),

          if (_subTabIndex == 0) _buildAbaNiveis(appState),
          if (_subTabIndex == 1) _buildAbaPacotes(appState),
          if (_subTabIndex == 2) _buildAbaHistorico(appState),
          if (_subTabIndex == 3) _buildAbaIndique(appState),
          if (_subTabIndex == 4) _buildAbaParticular(),
        ],
      ),
    );
  }

  Widget _buildAbaNiveis(OmniAppState appState) {
    final nivelAtual = appState.nivelFidelidadeAtual;
    final pontos = appState.passageiro.saldoPontos;
    final corNivel = _parseHexColor(nivelAtual.badgeCorHex);
    final pctCashback = (nivelAtual.cashbackPorCorrida * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                corNivel.withValues(alpha: 0.16),
                OmniConstants.darkSurface,
                OmniConstants.darkSurface,
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: corNivel.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SEU NÍVEL ATUAL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        color: corNivel,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            nivelAtual.nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.workspace_premium_rounded, color: corNivel, size: 22),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$pctCashback% de pontos gerados em cada viagem',
                      style: const TextStyle(fontSize: 12, color: OmniConstants.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Saldo real', style: TextStyle(fontSize: 11.5, color: OmniConstants.textMuted)),
                  const SizedBox(height: 2),
                  Text(
                    '$pontos pts',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: OmniConstants.neonCyan,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        ...OmniNivelFidelidade.niveis.map((niv) {
          final bool ativo = niv.id == nivelAtual.id;
          final Color badgeColor = _parseHexColor(niv.badgeCorHex);
          final int cashbackPct = (niv.cashbackPorCorrida * 100).round();

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ativo ? OmniConstants.darkSurface : OmniConstants.darkSurface.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: ativo ? badgeColor.withValues(alpha: 0.55) : OmniConstants.darkBorderSubtle,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${niv.nome} (${niv.pontosNecessarios}+ pts)',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ],
                    ),
                    Text(
                      '$cashbackPct% de volta',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: badgeColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...niv.vantagensExclusivas.map(
                  (v) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.check_rounded, size: 14, color: OmniConstants.neonCyan),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(v, style: const TextStyle(fontSize: 12, color: OmniConstants.textSecondary)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAbaPacotes(OmniAppState appState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: OmniConstants.darkSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: OmniConstants.darkBorderSubtle),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 17, color: OmniConstants.neonCyan),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Compre viagens com desconto garantido',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 4),
              Text(
                'Trave o preço das suas viagens, fuja da dinâmica e utilize ao longo do mês.',
                style: TextStyle(fontSize: 12, color: OmniConstants.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...OmniPacoteModel.pacotesDisponiveis.map((pkg) {
          final bool adquirido = appState.pacotesAtivosIds.contains(pkg.id);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: OmniConstants.darkSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: OmniConstants.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                pkg.titulo,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: OmniConstants.neonCyan.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.35)),
                                ),
                                child: Text(
                                  '${pkg.porcentagemDesconto}% OFF',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: OmniConstants.neonCyan,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(pkg.subtitulo, style: const TextStyle(fontSize: 12, color: OmniConstants.textMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'R\$ ${pkg.valorCheio.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: OmniConstants.textDim,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        Text(
                          'R\$ ${pkg.valorComDesconto.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                            color: OmniConstants.neonCyan,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Validade: ${pkg.validadeDias} dias',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: OmniConstants.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Categoria: ${pkg.categoriaPermitida}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: OmniConstants.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Material(
                  color: adquirido
                      ? OmniConstants.emeraldSuccess.withValues(alpha: 0.2)
                      : OmniConstants.neonCyan,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => _adquirirPacoteViaPix(appState, pkg),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: adquirido
                            ? Border.all(color: OmniConstants.emeraldSuccess.withValues(alpha: 0.35))
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            adquirido ? Icons.check_circle_outline : Icons.qr_code_2_rounded,
                            size: 16,
                            color: adquirido ? const Color(0xFF6EE7B7) : Colors.black,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            adquirido ? 'Pacote Ativo na Carteira' : 'Adquirir Pacote via Pix',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: adquirido ? const Color(0xFF6EE7B7) : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAbaHistorico(OmniAppState appState) {
    final historico = appState.historicoCorridas;
    if (historico.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: OmniConstants.darkSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: OmniConstants.darkBorderSubtle),
        ),
        child: const Column(
          children: [
            Icon(Icons.receipt_long_outlined, size: 36, color: OmniConstants.textMuted),
            SizedBox(height: 10),
            Text(
              'Nenhuma viagem concluída ainda',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            SizedBox(height: 4),
            Text(
              'Seus recibos, pontos acumulados e histórico de trajetos aparecerão automaticamente aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: OmniConstants.textMuted),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: historico.map((item) {
        final dd = item.concluidaEm.day.toString().padLeft(2, '0');
        final mm = item.concluidaEm.month.toString().padLeft(2, '0');
        final hh = item.concluidaEm.hour.toString().padLeft(2, '0');
        final min = item.concluidaEm.minute.toString().padLeft(2, '0');
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: OmniConstants.darkSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: OmniConstants.darkBorderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${item.categoriaNome} · $dd/$mm às $hh:$min',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: OmniConstants.neonCyan),
                  ),
                  Text(
                    'R\$ ${item.valorTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                item.destino,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 3),
              Text(
                '${item.distanciaKm.toStringAsFixed(1)} km · ⭐ ${item.avaliacao} · +${item.pontosGanhos} pts',
                style: const TextStyle(fontSize: 11, color: OmniConstants.textMuted),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAbaIndique(OmniAppState appState) {
    final codigo = appState.passageiro.codigoIndicacao;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: OmniConstants.darkSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OmniConstants.darkBorderSubtle),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: OmniConstants.neonCyan.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.35)),
            ),
            child: const Icon(Icons.card_giftcard_rounded, size: 28, color: OmniConstants.neonCyan),
          ),
          const SizedBox(height: 14),
          const Text(
            'Indique Amigos e Ganhe R\$ 15',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            'Quando seu amigo realizar a primeira corrida no OMNI, vocês dois recebem R\$ 15 em créditos OMNI Cash.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.45, color: OmniConstants.textMuted),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OmniConstants.darkBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    codigo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: OmniConstants.neonCyan,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Material(
                  color: OmniConstants.neonCyan.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => _copiarCodigoIndicacao(codigo),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copiadoCodigo ? Icons.check_circle_outline : Icons.copy_rounded,
                            size: 14,
                            color: OmniConstants.neonCyan,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _copiadoCodigo ? 'Copiado!' : 'Copiar',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: OmniConstants.neonCyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: OmniConstants.darkBorderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AMIGOS INDICADOS',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: OmniConstants.textMuted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${appState.amigosIndicados}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: OmniConstants.darkBorderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BÔNUS RECEBIDOS',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: OmniConstants.textMuted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'R\$ ${appState.bonusIndicacoes.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: OmniConstants.neonCyan,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAbaParticular() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: OmniConstants.darkSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OmniConstants.darkBorderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'SERVIÇO EXCLUSIVO OMNI',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              color: OmniConstants.neonCyan,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Corridas Particulares & Translados',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            'Toque em uma modalidade para solicitar orçamento com motorista executivo exclusivo.',
            style: TextStyle(fontSize: 12, height: 1.45, color: OmniConstants.textMuted),
          ),
          const SizedBox(height: 16),
          _ParticularRow(
            titulo: 'Translado Aeroporto Executivo',
            subtitulo: 'Recepção com placa no desembarque',
            valor: 'A partir de R\$ 90',
            onTap: () => _abrirModalOrcamentoParticular(modalidadeInicial: 'Translado Aeroporto Executivo'),
          ),
          const SizedBox(height: 10),
          _ParticularRow(
            titulo: 'Motorista por Diária (8 horas)',
            subtitulo: 'Disponibilidade integral em sua agenda',
            valor: 'R\$ 480 / dia',
            onTap: () => _abrirModalOrcamentoParticular(modalidadeInicial: 'Motorista por Diária (8 horas)'),
          ),
          const SizedBox(height: 10),
          _ParticularRow(
            titulo: 'Viagens Intermunicipais',
            subtitulo: 'Trajetos personalizados entre cidades',
            valor: 'Sob Consulta',
            onTap: () => _abrirModalOrcamentoParticular(modalidadeInicial: 'Viagens Intermunicipais'),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: () => _abrirModalOrcamentoParticular(),
            style: ElevatedButton.styleFrom(
              backgroundColor: OmniConstants.neonCyan,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text(
              'SOLICITAR ORÇAMENTO PARTICULAR',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, letterSpacing: 0.4),
            ),
          ),
          if (_ofertaPrivadaAtivaId != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'OFERTA ATIVA · $_ofertaPrivadaAtivaId',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                      color: OmniConstants.neonCyan,
                    ),
                  ),
                  if (_ofertaPrivadaResumo != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _ofertaPrivadaResumo!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ],
                  const SizedBox(height: 10),
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: OmniFirebaseService.escutarLancesPrivados(_ofertaPrivadaAtivaId!),
                    builder: (context, snapshot) {
                      final lances = snapshot.data ?? [];
                      if (lances.isEmpty) {
                        return const Text(
                          'Aguardando propostas de motoristas executivos em tempo real (/private_bids)...',
                          style: TextStyle(fontSize: 11.5, color: OmniConstants.textMuted),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: lances.map((bid) {
                          final valor = (bid[OmniRtdbFields.bidAmount] as num?)?.toDouble() ?? 0.0;
                          final motoristaNome = (bid['driver_name'] ?? bid['nome'] ?? bid[OmniRtdbFields.driverId] ?? 'Motorista OMNI').toString();
                          final msg = (bid[OmniRtdbFields.message] ?? '').toString();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: OmniConstants.darkCard,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: OmniConstants.darkBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        motoristaNome,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (msg.isNotEmpty)
                                        Text(
                                          msg,
                                          style: const TextStyle(fontSize: 11, color: OmniConstants.textMuted),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'R\$ ${valor.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w900,
                                    color: OmniConstants.neonCyan,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ParticularRow extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final String valor;
  final VoidCallback onTap;

  const _ParticularRow({
    required this.titulo,
    required this.subtitulo,
    required this.valor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: OmniConstants.darkBorderSubtle),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitulo, style: const TextStyle(fontSize: 11, color: OmniConstants.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                valor,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: OmniConstants.neonCyan,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 16, color: OmniConstants.textDim),
            ],
          ),
        ),
      ),
    );
  }
}
