import 'package:flutter/material.dart';
import '../../constants/omni_constants.dart';
import '../../models/categoria_model.dart';
import '../../models/corrida_model.dart';
import '../../theme/omni_theme.dart';
import 'omni_payment_method_sheet.dart';

/// Painel de Escolha de Categoria (Telas 03, 03b, EscolherConfort e EscolherMoto)
/// Mantém 100% a paleta OMNI Neon Luxuoso, com lista vertical rica, banner de preços/promoção,
/// preferências de conforto (Conforto/Black/Particular), barra de pagamento e CTA + agendamento.
class OmniCategorySelectionPanel extends StatelessWidget {
  final List<OmniCategoriaModel> categorias;
  final OmniCategoriaModel categoriaSelecionada;
  final ValueChanged<OmniCategoriaModel> onSelectCategoria;
  final String origemEndereco;
  final String destinoEndereco;
  final double distanciaKm;
  final int tempoMinutos;
  final int paradasCount;
  final OmniPaymentSelection paymentSelection;
  final OmniPreferenciasViagem preferencias;
  final ValueChanged<OmniPreferenciasViagem> onUpdatePreferencias;
  final OmniAgendamentoCorrida? agendamento;
  final VoidCallback onEditarRota;
  final VoidCallback onAbrirPagamento;
  final VoidCallback onAbrirAgendamento;
  final VoidCallback onVoltarHome;
  final VoidCallback onEscolherCategoria;

  const OmniCategorySelectionPanel({
    super.key,
    required this.categorias,
    required this.categoriaSelecionada,
    required this.onSelectCategoria,
    required this.origemEndereco,
    required this.destinoEndereco,
    required this.distanciaKm,
    required this.tempoMinutos,
    this.paradasCount = 0,
    required this.paymentSelection,
    required this.preferencias,
    required this.onUpdatePreferencias,
    this.agendamento,
    required this.onEditarRota,
    required this.onAbrirPagamento,
    required this.onAbrirAgendamento,
    required this.onVoltarHome,
    required this.onEscolherCategoria,
  });

  double get _descontoEfetivo =>
      paymentSelection.descontoPercentual > 0
          ? paymentSelection.descontoPercentual
          : (paymentSelection.descontoValorFixo > 0 ? 0.0 : 10.0);

  double get _descontoValorFixo => paymentSelection.descontoValorFixo;

  String _horaChegadaFormatada(int etaEmbarque) {
    final base = agendamento?.dataHora ?? DateTime.now();
    final chegada = base.add(Duration(minutes: etaEmbarque + tempoMinutos));
    return '${chegada.hour.toString().padLeft(2, '0')}:${chegada.minute.toString().padLeft(2, '0')}';
  }

  IconData _iconeCategoria(String icone) {
    switch (icone) {
      case 'moto':
        return Icons.two_wheeler_rounded;
      case 'envios':
        return Icons.inventory_2_outlined;
      case 'car_black':
        return Icons.workspace_premium_rounded;
      case 'car_particular':
        return Icons.shield_outlined;
      case 'car_conforto':
        return Icons.directions_car_filled_rounded;
      default:
        return Icons.directions_car_outlined;
    }
  }

  void _abrirPreferenciasConforto(BuildContext context) {
    String temp = preferencias.temperatura;
    String conv = preferencias.conversa;
    bool mala = preferencias.precisaPortaMalas;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.78),
            decoration: const BoxDecoration(
              color: OmniConstants.darkCard,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              border: Border(top: BorderSide(color: OmniConstants.darkBorder)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.tune_rounded, color: OmniConstants.neonCyan, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Preferências · ${categoriaSelecionada.nome}',
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            const Text(
                              'Personalize sua experiência a bordo',
                              style: TextStyle(fontSize: 11.5, color: OmniConstants.textMuted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: OmniConstants.textMuted, size: 20),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AR-CONDICIONADO / TEMPERATURA',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: OmniConstants.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ['Frio', 'Ameno', 'Sem preferência'].map((opt) {
                            final active = temp == opt;
                            return ChoiceChip(
                              label: Text(opt),
                              selected: active,
                              onSelected: (_) => setModalState(() => temp = opt),
                              selectedColor: OmniConstants.neonCyan,
                              backgroundColor: OmniConstants.darkSurface,
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: active ? Colors.black : OmniConstants.textSecondary,
                              ),
                              side: BorderSide(
                                color: active ? OmniConstants.neonCyan : OmniConstants.darkBorder,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'CONVERSA DURANTE A VIAGEM',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: OmniConstants.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ['Prefiro silêncio', 'Gosto de conversar', 'Sem preferência'].map((opt) {
                            final active = conv == opt;
                            return ChoiceChip(
                              label: Text(opt),
                              selected: active,
                              onSelected: (_) => setModalState(() => conv = opt),
                              selectedColor: OmniConstants.neonCyan,
                              backgroundColor: OmniConstants.darkSurface,
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: active ? Colors.black : OmniConstants.textSecondary,
                              ),
                              side: BorderSide(
                                color: active ? OmniConstants.neonCyan : OmniConstants.darkBorder,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: OmniConstants.darkSurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: OmniConstants.darkBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.luggage_rounded, color: OmniConstants.neonCyan, size: 19),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Preciso de espaço no porta-malas',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                              ),
                              Switch(
                                value: mala,
                                onChanged: (v) => setModalState(() => mala = v),
                                activeThumbColor: OmniConstants.neonCyan,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                  decoration: const BoxDecoration(
                    color: OmniConstants.darkSurface,
                    border: Border(top: BorderSide(color: OmniConstants.darkBorder)),
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      onUpdatePreferencias(
                        OmniPreferenciasViagem(
                          temperatura: temp,
                          conversa: conv,
                          precisaPortaMalas: mala,
                        ),
                      );
                      Navigator.of(ctx).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OmniConstants.neonCyan,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'SALVAR PREFERÊNCIAS',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          // 1. Cabeçalho + Voltar + Resumo clicável da rota
          Row(
            children: [
              Material(
                color: OmniConstants.darkSurface,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: onVoltarHome,
                  borderRadius: BorderRadius.circular(10),
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(Icons.arrow_back_rounded, size: 18, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: onEditarRota,
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Escolha uma viagem',
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      Text(
                        '${distanciaKm.toStringAsFixed(1)} km · ~$tempoMinutos min${paradasCount > 0 ? ' · $paradasCount parada(s)' : ''} · $destinoEndereco',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: OmniConstants.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: onEditarRota,
                style: TextButton.styleFrom(
                  foregroundColor: OmniConstants.neonCyan,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                child: const Text('Editar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 2. Banner de tendência de preços / promoção aplicada (Telas 03 / 03b)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: OmniConstants.emeraldSuccess.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: OmniConstants.emeraldSuccess.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.trending_down_rounded, size: 16, color: Color(0xFF34D399)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    paymentSelection.cupomAplicado != null
                        ? (_descontoValorFixo > 0
                            ? 'Cupom ${paymentSelection.cupomAplicado} aplicado (R\$ ${_descontoValorFixo.toStringAsFixed(2)} OFF)'
                            : 'Cupom ${paymentSelection.cupomAplicado} aplicado (${_descontoEfetivo.toStringAsFixed(0)}% OFF)')
                        : 'Preços menores do que o normal · Promoção de 10% aplicada',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF34D399),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3. Lista Vertical de Categorias
          ...categorias.map((cat) {
            final isSelected = cat.id == categoriaSelecionada.id;
            final precoOriginal = cat.calcularValorEstimado(
              km: distanciaKm,
              minutos: tempoMinutos,
              paradasCount: paradasCount,
            );
            final precoFinal = cat.calcularValorEstimado(
              km: distanciaKm,
              minutos: tempoMinutos,
              paradasCount: paradasCount,
              descontoPercentual: _descontoEfetivo,
              descontoValorFixo: _descontoValorFixo,
            );

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isSelected
                    ? OmniConstants.neonCyan.withValues(alpha: 0.10)
                    : OmniConstants.darkSurface,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () {
                    if (isSelected && cat.suportaPreferenciasConforto) {
                      _abrirPreferenciasConforto(context);
                    } else {
                      onSelectCategoria(cat);
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? OmniConstants.neonCyan : OmniConstants.darkBorderSubtle,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // Ícone da Modalidade
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? OmniConstants.neonCyan.withValues(alpha: 0.18)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: isSelected
                                      ? OmniConstants.neonCyan.withValues(alpha: 0.5)
                                      : OmniConstants.darkBorderSubtle,
                                ),
                              ),
                              child: Icon(
                                _iconeCategoria(cat.icone),
                                size: 22,
                                color: isSelected ? OmniConstants.neonCyan : OmniConstants.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Nome + Capacidade + Horário + Tag
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          cat.nome,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      if (cat.capacidadePassageiros > 0) ...[
                                        const SizedBox(width: 6),
                                        const Icon(Icons.person_rounded, size: 13, color: OmniConstants.textMuted),
                                        Text(
                                          '${cat.capacidadePassageiros}',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: OmniConstants.textMuted,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_horaChegadaFormatada(cat.tempoEstimadoMinutos)} · ${cat.tempoEstimadoMinutos} min',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11.5, color: OmniConstants.textMuted),
                                  ),
                                  if (cat.destaqueTag != null) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: OmniConstants.neonCyan.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        cat.destaqueTag!,
                                        style: const TextStyle(
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
                            const SizedBox(width: 8),
                            // Preço com desconto + preço original riscado
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'R\$ ${precoFinal.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w900,
                                    color: isSelected ? OmniConstants.neonCyan : Colors.white,
                                  ),
                                ),
                                Text(
                                  'R\$ ${precoOriginal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: OmniConstants.textDim,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        // Faixa de Preferências de Conforto (Telas EscolherConfort)
                        if (isSelected && cat.suportaPreferenciasConforto) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: OmniConstants.darkBorder),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.tune_rounded, size: 14, color: OmniConstants.neonCyan),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    preferencias.possuiCustomizacao
                                        ? '${preferencias.temperatura} · ${preferencias.conversa}${preferencias.precisaPortaMalas ? ' · Porta-malas' : ''}'
                                        : 'Definir preferências de ar-condicionado e conversa',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: OmniConstants.textSecondary,
                                    ),
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, size: 16, color: OmniConstants.neonCyan),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 6),

          // 4. Barra clicável de Pagamento (abre ModoDePagamento)
          Material(
            color: OmniConstants.darkSurface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onAbrirPagamento,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: OmniConstants.darkBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      paymentSelection.metodoPagamento == 'pix'
                          ? Icons.qr_code_2_rounded
                          : paymentSelection.metodoPagamento == 'cartao'
                              ? Icons.credit_card_rounded
                              : Icons.payments_outlined,
                      size: 18,
                      color: OmniConstants.neonCyan,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${paymentSelection.resumoCurto} · ${paymentSelection.perfilPagamento == 'corporativo' ? 'Corporativo' : 'Pessoal'}${paymentSelection.usarSaldoCarteira ? ' + Saldo' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 20, color: OmniConstants.textMuted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 5. Rodapé de Ação: Escolher [Categoria] + Botão Agendar (Calendário)
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onEscolherCategoria,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OmniConstants.neonCyan,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(
                    agendamento != null
                        ? 'AGENDAR ${categoriaSelecionada.nome.toUpperCase()}'
                        : 'ESCOLHER ${categoriaSelecionada.nome.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.4),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: agendamento != null
                    ? OmniConstants.neonCyan.withValues(alpha: 0.16)
                    : OmniConstants.darkSurface,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: onAbrirAgendamento,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: agendamento != null ? OmniConstants.neonCyan : OmniConstants.darkBorder,
                      ),
                    ),
                    child: Icon(
                      Icons.calendar_month_rounded,
                      size: 22,
                      color: agendamento != null ? OmniConstants.neonCyan : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
