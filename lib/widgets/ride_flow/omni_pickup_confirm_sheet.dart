import 'package:flutter/material.dart';
import '../../constants/omni_constants.dart';

/// Resultado da confirmação do local de embarque (Telas 04 / EscolherEndereçoPartida / 05)
class OmniPickupConfirmation {
  final String enderecoPartida;
  final double valorFinalConfirmado;
  final bool precoAlterado;

  const OmniPickupConfirmation({
    required this.enderecoPartida,
    required this.valorFinalConfirmado,
    this.precoAlterado = false,
  });
}

/// Modal "Confirme o local de partida" + Pontos de encontro próximos (Telas 04 e EscolherEndereçoPartida)
/// Caso o passageiro altere o ponto de embarque e o preço mude, dispara automaticamente
/// o modal "Confirme o novo preço" (Tela 05).
Future<OmniPickupConfirmation?> showOmniPickupConfirmSheet(
  BuildContext context, {
  required String enderecoInicial,
  required double valorEstimadoAtual,
}) async {
  final viaPrincipal = enderecoInicial.split(' - ').first.trim();
  final pontosSugeridos = <Map<String, dynamic>>[
    {
      'titulo': enderecoInicial,
      'subtitulo': 'Localização exata do GPS · Embarque imediato',
      'deltaPreco': 0.0,
    },
    {
      'titulo': 'Esquina próxima · ${viaPrincipal.isNotEmpty ? viaPrincipal : enderecoInicial}',
      'subtitulo': 'A 60m a pé · Embarque mais rápido sem retorno',
      'deltaPreco': -1.20,
    },
    {
      'titulo': 'Ponto seguro iluminado · ${viaPrincipal.isNotEmpty ? viaPrincipal : enderecoInicial}',
      'subtitulo': 'Área visível de parada rápida para embarque',
      'deltaPreco': 0.0,
    },
  ];

  final selectedIndex = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      int escolhido = 0;
      return StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.82),
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
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: OmniConstants.neonCyan.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.my_location_rounded, color: OmniConstants.neonCyan, size: 19),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Confirme o local de partida',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            Text(
                              'Ajuste o ponto exato de encontro com o motorista',
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
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
                    itemCount: pontosSugeridos.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, idx) {
                      final ponto = pontosSugeridos[idx];
                      final active = escolhido == idx;
                      final delta = ponto['deltaPreco'] as double;
                      return Material(
                        color: active
                            ? OmniConstants.neonCyan.withValues(alpha: 0.10)
                            : OmniConstants.darkSurface,
                        borderRadius: BorderRadius.circular(15),
                        child: InkWell(
                          onTap: () => setModalState(() => escolhido = idx),
                          borderRadius: BorderRadius.circular(15),
                          child: Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: active ? OmniConstants.neonCyan : OmniConstants.darkBorderSubtle,
                                width: active ? 1.4 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  idx == 0 ? Icons.gps_fixed_rounded : Icons.pin_drop_rounded,
                                  size: 19,
                                  color: active ? OmniConstants.neonCyan : OmniConstants.textMuted,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        ponto['titulo'] as String,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        ponto['subtitulo'] as String,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11, color: OmniConstants.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                if (delta != 0)
                                  Text(
                                    '${delta > 0 ? '+' : '-'}R\$ ${delta.abs().toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: delta < 0 ? const Color(0xFF34D399) : OmniConstants.amberWarning,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                  decoration: const BoxDecoration(
                    color: OmniConstants.darkSurface,
                    border: Border(top: BorderSide(color: OmniConstants.darkBorder)),
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(escolhido),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OmniConstants.neonCyan,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'CONFIRMAR PARTIDA',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  if (selectedIndex == null || !context.mounted) return null;

  final escolhido = pontosSugeridos[selectedIndex];
  final delta = escolhido['deltaPreco'] as double;
  final novoValor = double.parse((valorEstimadoAtual + delta).clamp(5.0, 9999.0).toStringAsFixed(2));

  if (delta != 0) {
    final aceitouNovoPreco = await showOmniNewPriceConfirmSheet(
      context,
      valorAnterior: valorEstimadoAtual,
      novoValor: novoValor,
      motivo: 'O ponto de encontro selecionado ajustou a distância da rota.',
    );
    if (aceitouNovoPreco != true) return null;
  }

  return OmniPickupConfirmation(
    enderecoPartida: escolhido['titulo'] as String,
    valorFinalConfirmado: novoValor,
    precoAlterado: delta != 0,
  );
}

/// Modal "Confirme o novo preço" (Tela 05)
Future<bool?> showOmniNewPriceConfirmSheet(
  BuildContext context, {
  required double valorAnterior,
  required double novoValor,
  required String motivo,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
            const SizedBox(height: 16),
            const Text(
              'Confirme o novo preço',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              motivo,
              style: const TextStyle(fontSize: 12.5, color: OmniConstants.textMuted),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: OmniConstants.darkSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Preço anterior', style: TextStyle(fontSize: 11, color: OmniConstants.textMuted)),
                      Text(
                        'R\$ ${valorAnterior.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13.5,
                          color: OmniConstants.textDim,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                  const Icon(Icons.arrow_forward_rounded, color: OmniConstants.neonCyan, size: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Novo preço total', style: TextStyle(fontSize: 11, color: OmniConstants.neonCyan)),
                      Text(
                        'R\$ ${novoValor.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: OmniConstants.neonCyan,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: OmniConstants.neonCyan,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'ACEITAR E CONTINUAR',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(
                'Voltar e ajustar',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: OmniConstants.textMuted),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Modal Obrigatório de Segurança para OMNI Moto (Tela SolicitarViagem)
/// "O uso de capacete é obrigatório por lei!"
Future<bool?> showOmniMotoHelmetDialog(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: OmniConstants.amberWarning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: OmniConstants.amberWarning.withValues(alpha: 0.45)),
                  ),
                  child: const Icon(Icons.sports_motorsports_rounded, color: OmniConstants.amberWarning, size: 26),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'O uso de capacete é obrigatório por lei!',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Para sua segurança nas viagens OMNI Moto, o motorista parceiro levará um capacete reserva higienizado. Mantenha a viseira fechada e a cinta jugular afivelada durante todo o trajeto.',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: OmniConstants.textSecondary),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: OmniConstants.neonCyan,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'CONCORDO E SOLICITAR OMNI MOTO',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text(
                'Cancelar',
                style: TextStyle(fontSize: 12.5, color: OmniConstants.textMuted),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
