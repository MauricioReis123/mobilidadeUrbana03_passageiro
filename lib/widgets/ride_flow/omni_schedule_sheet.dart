import 'package:flutter/material.dart';
import '../../constants/omni_constants.dart';
import '../../models/corrida_model.dart';

/// Modal "Escolha um horário" (Inspirado no fluxo Reserve / Agendar Corrida)
/// Mantém 100% a identidade visual OMNI Neon Luxuoso e proteção contra overflow.
Future<OmniAgendamentoCorrida?> showOmniScheduleSheet(
  BuildContext context, {
  OmniAgendamentoCorrida? initialSchedule,
  int duracaoEstimadaMinutos = 22,
}) {
  return showModalBottomSheet<OmniAgendamentoCorrida>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _OmniScheduleSheet(
      initialSchedule: initialSchedule,
      duracaoEstimadaMinutos: duracaoEstimadaMinutos,
    ),
  );
}

class _OmniScheduleSheet extends StatefulWidget {
  final OmniAgendamentoCorrida? initialSchedule;
  final int duracaoEstimadaMinutos;

  const _OmniScheduleSheet({
    this.initialSchedule,
    required this.duracaoEstimadaMinutos,
  });

  @override
  State<_OmniScheduleSheet> createState() => _OmniScheduleSheetState();
}

class _OmniScheduleSheetState extends State<_OmniScheduleSheet> {
  late bool _porHorarioChegada;
  late int _diaOffset; // 0 = Hoje, 1 = Amanhã, 2 = +2 dias, 3 = +3 dias
  late int _horaSelecionada;
  late int _minutoSelecionado;

  static const List<int> _minutosDisponiveis = [0, 10, 20, 30, 40, 50];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    if (widget.initialSchedule != null) {
      final dt = widget.initialSchedule!.dataHora;
      _porHorarioChegada = widget.initialSchedule!.porHorarioChegada;
      _diaOffset = dt.difference(DateTime(now.year, now.month, now.day)).inDays.clamp(0, 3);
      _horaSelecionada = dt.hour;
      _minutoSelecionado = _minutosDisponiveis.firstWhere(
        (m) => m >= dt.minute,
        orElse: () => 0,
      );
    } else {
      final base = now.add(const Duration(minutes: 40));
      _porHorarioChegada = false;
      _diaOffset = base.day != now.day ? 1 : 0;
      _horaSelecionada = base.hour;
      _minutoSelecionado = _minutosDisponiveis.firstWhere(
        (m) => m >= base.minute,
        orElse: () => 0,
      );
    }
  }

  DateTime get _dataHoraSelecionada {
    final now = DateTime.now();
    final baseDay = DateTime(now.year, now.month, now.day).add(Duration(days: _diaOffset));
    return DateTime(baseDay.year, baseDay.month, baseDay.day, _horaSelecionada, _minutoSelecionado);
  }

  String _labelDia(int offset) {
    final d = DateTime.now().add(Duration(days: offset));
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    if (offset == 0) return 'Hoje · $dd/$mm';
    if (offset == 1) return 'Amanhã · $dd/$mm';
    const diasSemana = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    return '${diasSemana[d.weekday - 1]} · $dd/$mm';
  }

  String _formatarHora(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final dt = _dataHoraSelecionada;
    final chegadaEstimada = _porHorarioChegada
        ? dt
        : dt.add(Duration(minutes: widget.duracaoEstimadaMinutos));
    final partidaEstimada = _porHorarioChegada
        ? dt.subtract(Duration(minutes: widget.duracaoEstimadaMinutos))
        : dt;

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
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            // Cabeçalho
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: OmniConstants.neonCyan.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.schedule_rounded, color: OmniConstants.neonCyan, size: 19),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Escolha um horário',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                        Text(
                          'Agendamento garantido com motorista OMNI',
                          style: TextStyle(fontSize: 11.5, color: OmniConstants.textMuted),
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

            // Corpo Rolável
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Segmented Toggle: Horário da partida | Horário de chegada
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: OmniConstants.darkSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: OmniConstants.darkBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SegmentButton(
                              label: 'Horário da partida',
                              selected: !_porHorarioChegada,
                              onTap: () => setState(() => _porHorarioChegada = false),
                            ),
                          ),
                          Expanded(
                            child: _SegmentButton(
                              label: 'Horário de chegada',
                              selected: _porHorarioChegada,
                              onTap: () => setState(() => _porHorarioChegada = true),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Seleção de Dia
                    const Text(
                      'DATA DA VIAGEM',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: OmniConstants.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: List.generate(4, (i) {
                          final active = _diaOffset == i;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(_labelDia(i)),
                              selected: active,
                              onSelected: (_) => setState(() => _diaOffset = i),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Seleção de Hora
                    const Text(
                      'HORA',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: OmniConstants.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: 24,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, h) {
                          final active = _horaSelecionada == h;
                          return Material(
                            color: active ? OmniConstants.neonCyan : OmniConstants.darkSurface,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () => setState(() => _horaSelecionada = h),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 52,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: active ? OmniConstants.neonCyan : OmniConstants.darkBorder,
                                  ),
                                ),
                                child: Text(
                                  '${h.toString().padLeft(2, '0')}h',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: active ? Colors.black : OmniConstants.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Seleção de Minuto
                    const Text(
                      'MINUTO',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: OmniConstants.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: _minutosDisponiveis.map((m) {
                        final active = _minutoSelecionado == m;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Material(
                              color: active ? OmniConstants.neonCyan : OmniConstants.darkSurface,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                onTap: () => setState(() => _minutoSelecionado = m),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: active ? OmniConstants.neonCyan : OmniConstants.darkBorder,
                                    ),
                                  ),
                                  child: Text(
                                    ':${m.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: active ? Colors.black : OmniConstants.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Card Resumo de Previsão
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: OmniConstants.neonCyan.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Embarque estimado',
                                style: TextStyle(fontSize: 12, color: OmniConstants.textSecondary),
                              ),
                              Text(
                                '${_labelDia(_diaOffset)} às ${_formatarHora(partidaEstimada)}',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: OmniConstants.neonCyan,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Previsão de chegada',
                                style: TextStyle(fontSize: 12, color: OmniConstants.textSecondary),
                              ),
                              Text(
                                '~${_formatarHora(chegadaEstimada)} (${widget.duracaoEstimadaMinutos} min)',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Política de Cancelamento OMNI
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: OmniConstants.darkSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: OmniConstants.darkBorderSubtle),
                      ),
                      child: const Column(
                        children: [
                          _PolicyItem(
                            icon: Icons.verified_user_outlined,
                            text: 'Motorista alocado com antecedência e tempo extra de espera incluso.',
                          ),
                          SizedBox(height: 8),
                          _PolicyItem(
                            icon: Icons.event_available_rounded,
                            text: 'Cancelamento gratuito até 1 hora antes do embarque ou antes da confirmação do motorista.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Rodapé Fixo com CTA
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              decoration: const BoxDecoration(
                color: OmniConstants.darkSurface,
                border: Border(top: BorderSide(color: OmniConstants.darkBorder)),
              ),
              child: Row(
                children: [
                  if (widget.initialSchedule != null) ...[
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: OmniConstants.textSecondary,
                        side: const BorderSide(color: OmniConstants.darkBorder),
                        minimumSize: const Size(0, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Ir agora', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop(
                          OmniAgendamentoCorrida(
                            dataHora: _dataHoraSelecionada,
                            porHorarioChegada: _porHorarioChegada,
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OmniConstants.neonCyan,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'CONTINUAR',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? OmniConstants.neonCyan : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.black : OmniConstants.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _PolicyItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PolicyItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: OmniConstants.neonCyan),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 11.5, height: 1.4, color: OmniConstants.textMuted),
          ),
        ),
      ],
    );
  }
}
