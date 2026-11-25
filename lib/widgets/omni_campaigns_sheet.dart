import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants/omni_constants.dart';
import '../models/campanha_model.dart';
import '../state/omni_app_state.dart';
import '../theme/omni_theme.dart';

/// Modal de Cupons & Campanhas Promocionais ao vivo via Firebase RTDB (`/campanhas_passageiro`)
Future<void> showOmniCampaignsSheet(
  BuildContext context, {
  String? highlightedCoupon,
  required ValueChanged<OmniCampanhaPassageiro> onApplyCoupon,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _OmniCampaignsSheet(
      highlightedCoupon: highlightedCoupon,
      onApplyCoupon: onApplyCoupon,
    ),
  );
}

class _OmniCampaignsSheet extends StatelessWidget {
  final String? highlightedCoupon;
  final ValueChanged<OmniCampanhaPassageiro> onApplyCoupon;

  const _OmniCampaignsSheet({
    this.highlightedCoupon,
    required this.onApplyCoupon,
  });

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<OmniAppState>();
    final campanhas = appState.campanhasAtivas;
    final normHighlight = (highlightedCoupon ?? '').trim().toUpperCase();

    final itens = campanhas.isNotEmpty
        ? campanhas
        : const [
            OmniCampanhaPassageiro(
              id: 'default_omni15',
              titulo: 'Desconto Especial OMNI15',
              mensagem: 'Aproveite 15% OFF na sua corrida hoje em qualquer categoria OMNI.',
              codigoCupom: 'OMNI15',
              tipoDesconto: 'percentual',
              percentualDesconto: 15.0,
              cidadeAlvo: 'todas',
              status: 'enviada',
            ),
          ];

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
              padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.local_offer_rounded, color: OmniConstants.neonCyan, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cupons & Campanhas OMNI',
                          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        Text(
                          appState.cidadeAtual.isNotEmpty
                              ? 'Ofertas ativas para ${appState.cidadeAtual}'
                              : 'Promoções em tempo real via Firebase RTDB',
                          style: const TextStyle(fontSize: 11, color: OmniConstants.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: OmniConstants.textMuted, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 22),
                itemCount: itens.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (ctx, idx) {
                  final camp = itens[idx];
                  final ehDestaque = normHighlight.isNotEmpty &&
                      camp.codigoCupom.toUpperCase() == normHighlight;

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: ehDestaque
                        ? OmniTheme.neonBoxDecoration(
                            borderColor: OmniConstants.neonCyan,
                            borderRadius: 18,
                            glowRadius: 14,
                          )
                        : BoxDecoration(
                            color: OmniConstants.darkSurface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: OmniConstants.darkBorder),
                          ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (camp.imagemUrl.isNotEmpty) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              camp.imagemUrl,
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                camp.titulo,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: OmniConstants.emeraldSuccess.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: OmniConstants.emeraldSuccess.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                camp.resumoDesconto,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF34D399),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          camp.mensagem,
                          style: const TextStyle(
                            fontSize: 12,
                            color: OmniConstants.textSecondary,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: OmniConstants.darkBorder),
                              ),
                              child: Text(
                                camp.cidadeAlvo.toLowerCase() == 'todas'
                                    ? 'Todas as cidades'
                                    : camp.cidadeAlvo,
                                style: const TextStyle(fontSize: 10.5, color: OmniConstants.textMuted),
                              ),
                            ),
                            if (camp.codigoCupom.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: camp.codigoCupom));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Cupom ${camp.codigoCupom} copiado!')),
                                  );
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: OmniConstants.neonCyan.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: OmniConstants.neonCyan.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        camp.codigoCupom,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: OmniConstants.neonCyan,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.copy_rounded, size: 12, color: OmniConstants.neonCyan),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () {
                            onApplyCoupon(camp);
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: OmniConstants.neonCyan,
                            foregroundColor: Colors.black,
                            minimumSize: const Size(double.infinity, 42),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            camp.codigoCupom.isNotEmpty
                                ? 'APLICAR CUPOM ${camp.codigoCupom}'
                                : 'ATIVAR OFERTA AGORA',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
