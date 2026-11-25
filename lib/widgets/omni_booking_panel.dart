import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../constants/omni_constants.dart';
import '../models/categoria_model.dart';
import '../theme/omni_theme.dart';
import '../tools/mapas_service.dart';
import 'omni_address_autocomplete_field.dart';

/// Painel de Solicitação e Checkout Pix — Fidelidade 1:1 ao OmniBookingPanel.tsx
/// Totalmente protegido contra overflow em qualquer largura ou escala de fonte Android.
class OmniBookingPanel extends StatefulWidget {
  final List<OmniCategoriaModel> categorias;
  final OmniCategoriaModel categoriaSelecionada;
  final ValueChanged<OmniCategoriaModel> onSelectCategoria;
  final String metodoPagamento; // 'pix' | 'cartao' | 'dinheiro'
  final ValueChanged<String> onSelectMetodoPagamento;
  final TextEditingController origemController;
  final TextEditingController destinoController;
  final List<TextEditingController> paradasControllers;
  final VoidCallback onAddParada;
  final ValueChanged<int> onRemoveParada;
  final VoidCallback onChangedTexto;
  final VoidCallback onConfirmar;
  final bool solicitando;
  final String pixCopiaECola;
  final String pixStatus; // 'pendente' | 'aprovado'
  final VoidCallback onVerificarPix;
  final double latReferencia;
  final double lngReferencia;
  final ValueChanged<OmniCoordenada>? onSelectOrigemCoord;
  final ValueChanged<OmniCoordenada>? onSelectDestinoCoord;
  final void Function(int index, OmniCoordenada coord)? onSelectParadaCoord;
  final VoidCallback? onTapGpsOrigem;
  final bool gpsCarregando;
  final double? distanciaKm;
  final int? tempoMinutos;

  const OmniBookingPanel({
    super.key,
    required this.categorias,
    required this.categoriaSelecionada,
    required this.onSelectCategoria,
    required this.metodoPagamento,
    required this.onSelectMetodoPagamento,
    required this.origemController,
    required this.destinoController,
    required this.paradasControllers,
    required this.onAddParada,
    required this.onRemoveParada,
    required this.onChangedTexto,
    required this.onConfirmar,
    required this.solicitando,
    required this.pixCopiaECola,
    required this.pixStatus,
    required this.onVerificarPix,
    this.latReferencia = -23.5614,
    this.lngReferencia = -46.6559,
    this.onSelectOrigemCoord,
    this.onSelectDestinoCoord,
    this.onSelectParadaCoord,
    this.onTapGpsOrigem,
    this.gpsCarregando = false,
    this.distanciaKm,
    this.tempoMinutos,
  });

  @override
  State<OmniBookingPanel> createState() => _OmniBookingPanelState();
}

class _OmniBookingPanelState extends State<OmniBookingPanel> {
  bool _copiado = false;

  void _copiarChavePix() async {
    await Clipboard.setData(ClipboardData(text: widget.pixCopiaECola));
    if (!mounted) return;
    setState(() => _copiado = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiado = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Agrupa categorias em linhas de 2 para evitar height fixo do GridView
    final List<List<OmniCategoriaModel>> linhasCategorias = [];
    for (int i = 0; i < widget.categorias.length; i += 2) {
      linhasCategorias.add(
        widget.categorias.sublist(
          i,
          (i + 2 <= widget.categorias.length) ? i + 2 : widget.categorias.length,
        ),
      );
    }

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
          // 1. Card de Origem, Paradas Intermediárias e Destino com Autocomplete por Proximidade
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: OmniConstants.darkSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: OmniConstants.darkBorderSubtle),
            ),
            child: Column(
              children: [
                // Origem
                OmniAddressAutocompleteField(
                  key: const ValueKey('omni_booking_origem'),
                  controller: widget.origemController,
                  hint: 'Ponto de partida',
                  latReferencia: widget.latReferencia,
                  lngReferencia: widget.lngReferencia,
                  dotColor: OmniConstants.neonCyan,
                  onChangedTexto: widget.onChangedTexto,
                  onSelectCoordenada: (coord) => widget.onSelectOrigemCoord?.call(coord),
                  trailing: widget.onTapGpsOrigem != null
                      ? IconButton(
                          icon: Icon(
                            widget.gpsCarregando ? Icons.sync_rounded : Icons.my_location_rounded,
                            size: 16,
                            color: OmniConstants.neonCyan,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: widget.onTapGpsOrigem,
                        )
                      : null,
                ),

                // Paradas Intermediárias
                ...widget.paradasControllers.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final ctrl = entry.value;
                  return Container(
                    key: ObjectKey(ctrl),
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.only(top: 8),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: OmniConstants.darkBorderSubtle)),
                    ),
                    child: OmniAddressAutocompleteField(
                      key: ValueKey('omni_booking_parada_${identityHashCode(ctrl)}'),
                      controller: ctrl,
                      hint: 'Parada ${idx + 1}',
                      latReferencia: widget.latReferencia,
                      lngReferencia: widget.lngReferencia,
                      dotColor: OmniConstants.goldAccent,
                      onChangedTexto: widget.onChangedTexto,
                      onSelectCoordenada: (coord) => widget.onSelectParadaCoord?.call(idx, coord),
                      trailing: InkWell(
                        onTap: () => widget.onRemoveParada(idx),
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.close_rounded, size: 17, color: OmniConstants.rubyRedAlert),
                        ),
                      ),
                    ),
                  );
                }),

                // Destino + Botão "+ Parada"
                Container(
                  key: const ValueKey('omni_booking_destino_wrap'),
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: OmniConstants.darkBorderSubtle)),
                  ),
                  child: OmniAddressAutocompleteField(
                    key: const ValueKey('omni_booking_destino'),
                    controller: widget.destinoController,
                    hint: 'Para onde vamos?',
                    latReferencia: widget.latReferencia,
                    lngReferencia: widget.lngReferencia,
                    dotColor: OmniConstants.rubyRedAlert,
                    isSquare: true,
                    onChangedTexto: widget.onChangedTexto,
                    onSelectCoordenada: (coord) => widget.onSelectDestinoCoord?.call(coord),
                    trailing: widget.paradasControllers.length < 3
                        ? Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Material(
                              color: OmniConstants.neonCyan.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                onTap: widget.onAddParada,
                                borderRadius: BorderRadius.circular(10),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_rounded, size: 14, color: OmniConstants.neonCyan),
                                      SizedBox(width: 3),
                                      Text(
                                        'Parada',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: OmniConstants.neonCyan,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 2. Cabeçalho Categorias OMNI
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CATEGORIAS OMNI',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: OmniConstants.textMuted,
                ),
              ),
              Text(
                (widget.distanciaKm != null && widget.distanciaKm! > 0)
                    ? '${widget.distanciaKm!.toStringAsFixed(1)} km · ~${widget.tempoMinutos ?? 0} min'
                    : 'Chegada em ~3 a 6 min',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: OmniConstants.neonCyan,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Grid 2x2 Responsivo sem estourar altura
          ...linhasCategorias.asMap().entries.map((rowEntry) {
            final rowIdx = rowEntry.key;
            final pair = rowEntry.value;
            final paradasCount =
                widget.paradasControllers.where((c) => c.text.trim().isNotEmpty).length;
            return Padding(
              padding: EdgeInsets.only(bottom: rowIdx < linhasCategorias.length - 1 ? 10 : 0),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _CategoriaCard(
                        categoria: pair[0],
                        selected: widget.categoriaSelecionada.id == pair[0].id,
                        distanciaKm: widget.distanciaKm,
                        tempoMinutos: widget.tempoMinutos,
                        paradasCount: paradasCount,
                        onTap: () => widget.onSelectCategoria(pair[0]),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (pair.length > 1)
                      Expanded(
                        child: _CategoriaCard(
                          categoria: pair[1],
                          selected: widget.categoriaSelecionada.id == pair[1].id,
                          distanciaKm: widget.distanciaKm,
                          tempoMinutos: widget.tempoMinutos,
                          paradasCount: paradasCount,
                          onTap: () => widget.onSelectCategoria(pair[1]),
                        ),
                      )
                    else
                      const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 18),

          // 3. Forma de Pagamento (3 botões equilibrados)
          const Text(
            'FORMA DE PAGAMENTO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: OmniConstants.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PaymentChip(
                  label: 'Pix Instantâneo',
                  icon: Icons.qr_code_2_rounded,
                  selected: widget.metodoPagamento == 'pix',
                  onTap: () => widget.onSelectMetodoPagamento('pix'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PaymentChip(
                  label: 'Cartão',
                  icon: Icons.credit_card_rounded,
                  selected: widget.metodoPagamento == 'cartao',
                  onTap: () => widget.onSelectMetodoPagamento('cartao'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PaymentChip(
                  label: 'Dinheiro',
                  icon: Icons.payments_outlined,
                  selected: widget.metodoPagamento == 'dinheiro',
                  onTap: () => widget.onSelectMetodoPagamento('dinheiro'),
                ),
              ),
            ],
          ),

          // 4. Painel QR Code Pix Mercado Pago (quando Pix selecionado)
          if (widget.metodoPagamento == 'pix') ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: OmniConstants.darkSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.qr_code_2_rounded, size: 17, color: OmniConstants.neonCyan),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'QR Code Pix Mercado Pago',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (widget.pixStatus == 'aprovado'
                                  ? OmniConstants.emeraldSuccess
                                  : OmniConstants.amberWarning)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: (widget.pixStatus == 'aprovado'
                                    ? OmniConstants.emeraldSuccess
                                    : OmniConstants.amberWarning)
                                .withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          widget.pixStatus == 'aprovado' ? 'Pix Aprovado' : 'Aguardando Liquidação',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: widget.pixStatus == 'aprovado'
                                ? OmniConstants.emeraldSuccess
                                : const Color(0xFFFBBF24),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 78,
                          height: 78,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: QrImageView(
                            data: widget.pixCopiaECola,
                            version: QrVersions.auto,
                            size: 70,
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pague com qualquer banco via Pix.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: OmniConstants.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Material(
                                color: OmniConstants.neonCyan.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  onTap: _copiarChavePix,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _copiado ? Icons.check_circle_outline : Icons.copy_rounded,
                                          size: 14,
                                          color: OmniConstants.neonCyan,
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            _copiado ? 'Chave Copiada!' : 'Copiar Chave Pix',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: OmniConstants.neonCyan,
                                            ),
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.only(top: 10),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: OmniConstants.darkBorderSubtle)),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        const Text(
                          'Gateway Mercado Pago · Validação em tempo real.',
                          style: TextStyle(fontSize: 11, color: OmniConstants.textMuted),
                        ),
                        Material(
                          color: OmniConstants.emeraldSuccess.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: widget.onVerificarPix,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              child: Text(
                                widget.pixStatus == 'aprovado'
                                    ? 'Pix Liquidado'
                                    : 'Verificar Liquidação Pix',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF6EE7B7),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 18),

          // 5. Botão Principal Neon Glow
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: OmniConstants.neonCyan.withValues(alpha: 0.42),
                  blurRadius: 22,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: widget.solicitando ? null : widget.onConfirmar,
              style: ElevatedButton.styleFrom(
                backgroundColor: OmniConstants.neonCyan,
                foregroundColor: Colors.black,
                disabledBackgroundColor: OmniConstants.neonCyan.withValues(alpha: 0.6),
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: widget.solicitando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.auto_awesome, size: 18, color: Colors.black),
                          const SizedBox(width: 8),
                          Text(
                            'CONFIRMAR E CHAMAR ${widget.categoriaSelecionada.nome.toUpperCase()}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                              color: Colors.black,
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
  }
}

class _CategoriaCard extends StatelessWidget {
  final OmniCategoriaModel categoria;
  final bool selected;
  final double? distanciaKm;
  final int? tempoMinutos;
  final int paradasCount;
  final VoidCallback onTap;

  const _CategoriaCard({
    required this.categoria,
    required this.selected,
    this.distanciaKm,
    this.tempoMinutos,
    this.paradasCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final preco = categoria.calcularValorEstimado(
      km: distanciaKm ?? 0.0,
      minutos: tempoMinutos ?? 0,
      paradasCount: paradasCount,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? OmniConstants.neonCyan.withValues(alpha: 0.1)
                : OmniConstants.darkSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? OmniConstants.neonCyan : OmniConstants.darkBorderSubtle,
              width: selected ? 1.5 : 1.0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: OmniConstants.neonCyan.withValues(alpha: 0.25),
                      blurRadius: 14,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          categoria.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: OmniConstants.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.directions_car_filled_rounded,
                        size: 16,
                        color: selected ? OmniConstants.neonCyan : OmniConstants.textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    categoria.descricao,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: OmniConstants.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'R\$ ${preco.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: OmniConstants.neonCyan,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${categoria.tempoEstimadoMinutos} min',
                    style: const TextStyle(
                      fontSize: 10,
                      color: OmniConstants.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? OmniConstants.neonCyan : OmniConstants.darkSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? OmniConstants.neonCyan : OmniConstants.darkBorder,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: OmniConstants.neonCyan.withValues(alpha: 0.35),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: selected ? Colors.black : OmniConstants.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.black : OmniConstants.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
