import 'package:flutter/material.dart';
import '../constants/omni_constants.dart';
import 'omni_top_header.dart';

/// Barra de Navegação Horizontal Fluida para Mobile Touch (Android)
/// Garante que nenhum botão estoure ou quebre linha, com scroll horizontal ao toque.
class OmniTabBar extends StatelessWidget {
  final OmniMainTab activeTab;
  final ValueChanged<OmniMainTab> onSelectTab;

  const OmniTabBar({
    super.key,
    required this.activeTab,
    required this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: OmniConstants.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: OmniConstants.darkBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Em telas >= 340px distribui uniformemente; em telas menores ou texto ampliado permite scroll horizontal fluido
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _TabPill(
                    label: 'Corridas',
                    icon: Icons.directions_car_filled_outlined,
                    selected: activeTab == OmniMainTab.corridas,
                    onTap: () => onSelectTab(OmniMainTab.corridas),
                  ),
                  const SizedBox(width: 4),
                  _TabPill(
                    label: 'Fidelidade & Pacotes',
                    icon: Icons.workspace_premium_outlined,
                    selected: activeTab == OmniMainTab.fidelidade,
                    onTap: () => onSelectTab(OmniMainTab.fidelidade),
                  ),
                  const SizedBox(width: 4),
                  _TabPill(
                    label: 'Código Flutter',
                    icon: Icons.code_rounded,
                    selected: activeTab == OmniMainTab.codigo,
                    onTap: () => onSelectTab(OmniMainTab.codigo),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabPill({
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
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? OmniConstants.neonCyan : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: OmniConstants.neonCyan.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.black : OmniConstants.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.black : OmniConstants.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
