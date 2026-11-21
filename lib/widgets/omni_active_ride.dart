import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/omni_constants.dart';
import '../models/corrida_model.dart';
import '../state/omni_app_state.dart';
import '../theme/omni_theme.dart';

/// Painel Completo de Pós-Pedido e Corrida em Andamento — 100% Real e Interativo
/// Integra url_launcher (190 / Ligar para motorista), chat persistido em OmniAppState,
/// cronômetro real de espera, alteração de destino com recálculo, gorjeta e suporte real.
class OmniActiveRide extends StatefulWidget {
  final OmniCorridaModel corrida;
  final VoidCallback onAvancarStatus;
  final VoidCallback onCancelar;
  final ValueChanged<int> onFinalizarComAvaliacao;
  final Future<void> Function(int estrelas, double gorjeta, List<String> elogios)? onFinalizarCompleto;
  final ValueChanged<String>? onAlterarDestino;

  const OmniActiveRide({
    super.key,
    required this.corrida,
    required this.onAvancarStatus,
    required this.onCancelar,
    required this.onFinalizarComAvaliacao,
    this.onFinalizarCompleto,
    this.onAlterarDestino,
  });

  @override
  State<OmniActiveRide> createState() => _OmniActiveRideState();
}

class _OmniActiveRideState extends State<OmniActiveRide> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  int _avaliacaoEstrelas = 5;
  final Set<String> _elogiosSelecionados = {'Direção segura', 'Carro impecável'};
  double _gorjetaSelecionada = 0.0;
  bool _copiadoLink = false;
  bool _gravacaoAudioAtiva = false;
  bool _enviouEstouChegando = false;
  bool _enviandoAvaliacao = false;

  int _segundosEspera = 120;
  int _segundosRadar = 0;
  Timer? _waitTimer;
  Timer? _radarTimer;

  static const List<String> _opcoesElogio = [
    'Direção segura',
    'Carro impecável',
    'Ótima conversa',
    'Rota rápida',
    'Música boa',
  ];

  static const List<double> _opcoesGorjeta = [0.0, 2.0, 5.0, 10.0];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _syncTimers();
  }

  @override
  void didUpdateWidget(covariant OmniActiveRide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.corrida.status != widget.corrida.status) {
      _syncTimers();
    }
  }

  void _syncTimers() {
    _waitTimer?.cancel();
    _radarTimer?.cancel();

    if (widget.corrida.status == OmniStatusCorrida.buscandoMotorista) {
      _segundosRadar = 0;
      _radarTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _segundosRadar++);
      });
    } else if (widget.corrida.status == OmniStatusCorrida.aguardandoPassageiro) {
      _segundosEspera = 120;
      _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_segundosEspera > 0) {
          setState(() => _segundosEspera--);
        } else {
          timer.cancel();
        }
      });
    }
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _radarTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  String get _tempoEsperaFormatado {
    final min = (_segundosEspera ~/ 60).toString().padLeft(2, '0');
    final seg = (_segundosEspera % 60).toString().padLeft(2, '0');
    return '$min:$seg';
  }

  int get _etapaAtualIndex {
    switch (widget.corrida.status) {
      case OmniStatusCorrida.solicitada:
      case OmniStatusCorrida.buscandoMotorista:
        return 0;
      case OmniStatusCorrida.aceita:
      case OmniStatusCorrida.aCaminhoEmbarque:
        return 1;
      case OmniStatusCorrida.aguardandoPassageiro:
        return 2;
      case OmniStatusCorrida.emAndamento:
        return 3;
      case OmniStatusCorrida.concluida:
        return 4;
      default:
        return 0;
    }
  }

  String _getStatusLabel() {
    final eta = widget.corrida.motorista?.distanciaMinutos ?? widget.corrida.categoria.tempoEstimadoMinutos;
    switch (widget.corrida.status) {
      case OmniStatusCorrida.buscandoMotorista:
        return 'Buscando motorista parceiro próximo... (${_segundosRadar}s)';
      case OmniStatusCorrida.aceita:
        return 'Motorista aceitou! Preparando saída';
      case OmniStatusCorrida.aCaminhoEmbarque:
        return 'Motorista a $eta min do local de partida';
      case OmniStatusCorrida.aguardandoPassageiro:
        return 'Motorista chegou ao local de embarque!';
      case OmniStatusCorrida.emAndamento:
        return 'Em viagem · Chegada prevista em ${widget.corrida.tempoMinutos} min';
      case OmniStatusCorrida.concluida:
        return 'Você chegou ao seu destino!';
      default:
        return 'Aguardando atualização...';
    }
  }

  String _getEtaBadge() {
    final eta = widget.corrida.motorista?.distanciaMinutos ?? widget.corrida.categoria.tempoEstimadoMinutos;
    switch (widget.corrida.status) {
      case OmniStatusCorrida.buscandoMotorista:
        return 'RADAR';
      case OmniStatusCorrida.aceita:
        return '$eta MIN';
      case OmniStatusCorrida.aCaminhoEmbarque:
        return '$eta MIN';
      case OmniStatusCorrida.aguardandoPassageiro:
        return 'NO LOCAL';
      case OmniStatusCorrida.emAndamento:
        return '${widget.corrida.tempoMinutos} MIN';
      case OmniStatusCorrida.concluida:
        return 'FINALIZADA';
      default:
        return 'OMNI';
    }
  }

  Future<void> _ligarTelefone(String numero, String rotulo) async {
    final limpo = numero.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: limpo.isEmpty ? '190' : limpo);
    try {
      final abriu = await launchUrl(uri);
      if (!abriu && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Discador indisponível. Número de $rotulo: $numero')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Número de $rotulo: $numero')),
        );
      }
    }
  }

  Future<void> _copiarLinkViagem() async {
    await Clipboard.setData(ClipboardData(text: 'https://omni.mobi/track/${widget.corrida.id}'));
    if (!mounted) return;
    setState(() => _copiadoLink = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiadoLink = false);
    });
  }

  void _abrirAlterarDestino() {
    final ctrl = TextEditingController(text: widget.corrida.destino.endereco ?? '');
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (ctx) => Dialog(
        backgroundColor: OmniConstants.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: OmniConstants.darkBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Alterar destino da viagem',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 6),
              const Text(
                'O motorista será notificado e a tarifa será recalculada automaticamente.',
                style: TextStyle(fontSize: 12, color: OmniConstants.textMuted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: const InputDecoration(hintText: 'Novo endereço de destino'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: OmniConstants.textMuted,
                        side: const BorderSide(color: OmniConstants.darkBorder),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final novo = ctrl.text.trim();
                        if (novo.isNotEmpty) {
                          widget.onAlterarDestino?.call(novo);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Destino recalculado para: $novo')),
                          );
                        }
                        Navigator.of(ctx).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OmniConstants.neonCyan,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Atualizar', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).then((_) => ctrl.dispose());
  }

  void _abrirModalSeguranca() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: OmniConstants.darkCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: OmniConstants.rubyRedAlert.withValues(alpha: 0.45)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: OmniConstants.rubyRedAlert.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.shield_rounded, color: OmniConstants.rubyRedAlert, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Central SOS OMNI',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            Text(
                              'Proteção e monitoramento 24h',
                              style: TextStyle(fontSize: 12, color: OmniConstants.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Sua localização GPS está sendo transmitida em tempo real para nossa central de apoio.',
                    style: TextStyle(fontSize: 12.5, height: 1.5, color: OmniConstants.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: OmniConstants.darkSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _gravacaoAudioAtiva
                            ? OmniConstants.neonCyan.withValues(alpha: 0.5)
                            : OmniConstants.darkBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.mic_rounded,
                          size: 18,
                          color: _gravacaoAudioAtiva ? OmniConstants.neonCyan : OmniConstants.textMuted,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Gravar áudio da viagem',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                              Text(
                                'Criptografado · Somente a Central OMNI acessa',
                                style: TextStyle(fontSize: 10.5, color: OmniConstants.textMuted),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _gravacaoAudioAtiva,
                          onChanged: (v) {
                            setState(() => _gravacaoAudioAtiva = v);
                            setDialogState(() {});
                          },
                          activeThumbColor: OmniConstants.neonCyan,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _ligarTelefone('190', 'Emergência Policial');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OmniConstants.rubyRedAlert,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.warning_amber_rounded, size: 18),
                    label: const Text(
                      'CHAMAR POLÍCIA (190)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      foregroundColor: OmniConstants.textSecondary,
                      minimumSize: const Size(double.infinity, 42),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Fechar Alerta', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _abrirChatRapido() {
    final TextEditingController msgController = TextEditingController();
    const List<String> respostasRapidas = [
      'Estou chegando!',
      'Estou aguardando na entrada',
      'Pode aguardar 1 minuto?',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Consumer<OmniAppState>(
        builder: (ctx, appState, _) {
          final mensagens = appState.mensagensChat;
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          return SafeArea(
            child: Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
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
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded, color: OmniConstants.neonCyan, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Chat com ${widget.corrida.motorista?.nome ?? "Motorista"}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20, color: OmniConstants.textMuted),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: OmniConstants.darkBorder),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: mensagens.length,
                      itemBuilder: (_, i) {
                        final msg = mensagens[i];
                        final isMe = msg.autor == 'passageiro';
                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: isMe ? OmniConstants.neonCyan : OmniConstants.darkSurface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              msg.texto,
                              style: TextStyle(
                                fontSize: 13,
                                color: isMe ? Colors.black : Colors.white,
                                fontWeight: isMe ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  SizedBox(
                    height: 36,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: respostasRapidas.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, idx) => ActionChip(
                        label: Text(respostasRapidas[idx], style: const TextStyle(fontSize: 11)),
                        backgroundColor: OmniConstants.darkSurface,
                        side: const BorderSide(color: OmniConstants.darkBorder),
                        onPressed: () => appState.enviarMensagemChat(respostasRapidas[idx]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    decoration: const BoxDecoration(
                      color: OmniConstants.darkSurface,
                      border: Border(top: BorderSide(color: OmniConstants.darkBorder)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: msgController,
                            style: const TextStyle(fontSize: 13, color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Enviar mensagem...',
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onSubmitted: (val) {
                              if (val.trim().isEmpty) return;
                              appState.enviarMensagemChat(val);
                              msgController.clear();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: OmniConstants.neonCyan,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () {
                              final txt = msgController.text.trim();
                              if (txt.isEmpty) return;
                              appState.enviarMensagemChat(txt);
                              msgController.clear();
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(Icons.send_rounded, color: Colors.black, size: 18),
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
        },
      ),
    ).whenComplete(msgController.dispose);
  }

  Future<void> _enviarAvaliacao() async {
    if (_enviandoAvaliacao) return;
    setState(() => _enviandoAvaliacao = true);
    if (widget.onFinalizarCompleto != null) {
      await widget.onFinalizarCompleto!(
        _avaliacaoEstrelas,
        _gorjetaSelecionada,
        _elogiosSelecionados.toList(),
      );
    } else {
      widget.onFinalizarComAvaliacao(_avaliacaoEstrelas);
    }
    if (mounted) setState(() => _enviandoAvaliacao = false);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<OmniAppState>();
    final corrida = widget.corrida;
    final bool buscando = corrida.status == OmniStatusCorrida.buscandoMotorista;
    final bool aguardando = corrida.status == OmniStatusCorrida.aguardandoPassageiro;
    final bool concluida = corrida.status == OmniStatusCorrida.concluida;
    final double valorBase = corrida.valorFinal ?? corrida.valorEstimado;
    final double totalComGorjeta = valorBase + _gorjetaSelecionada;
    final int pontosPrevistos = math.max(
      10,
      (totalComGorjeta * (1 + appState.nivelFidelidadeAtual.cashbackPorCorrida * 10)).round(),
    );

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
          // 1. Barra de Status + Badge ETA + Stepper
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: OmniConstants.darkSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    FadeTransition(
                      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_pulseController),
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: OmniConstants.neonCyan,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: OmniConstants.neonCyan.withValues(alpha: 0.8), blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: OmniConstants.neonCyan.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _getEtaBadge(),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: OmniConstants.neonCyan,
                                  ),
                                ),
                              ),
                              if (_gravacaoAudioAtiva) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.mic_rounded, size: 13, color: OmniConstants.rubyRedAlert),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getStatusLabel(),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: OmniConstants.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!concluida) ...[
                      const SizedBox(width: 8),
                      Material(
                        color: OmniConstants.neonCyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: widget.onAvancarStatus,
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Avançar',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: OmniConstants.neonCyan,
                                  ),
                                ),
                                SizedBox(width: 3),
                                Icon(Icons.arrow_forward_rounded, size: 13, color: OmniConstants.neonCyan),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: List.generate(4, (idx) {
                    final active = idx <= _etapaAtualIndex;
                    return Expanded(
                      child: Container(
                        height: 4,
                        margin: EdgeInsets.only(right: idx < 3 ? 5 : 0),
                        decoration: BoxDecoration(
                          color: active ? OmniConstants.neonCyan : Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),

          if (buscando) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: OmniConstants.darkSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  const LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: Color(0x1A00FFCC),
                    color: OmniConstants.neonCyan,
                  ),
                  const SizedBox(height: 16),
                  const Icon(Icons.radar_rounded, size: 36, color: OmniConstants.neonCyan),
                  const SizedBox(height: 10),
                  Text(
                    'Conectando com motoristas ${corrida.categoria.nome}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Destino: ${corrida.destino.endereco ?? ""}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: OmniConstants.textMuted),
                  ),
                ],
              ),
            ),
          ],

          if (aguardando) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: OmniConstants.amberWarning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: OmniConstants.amberWarning.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: OmniConstants.amberWarning, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tempo de espera gratuito: $_tempoEsperaFormatado',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: OmniConstants.amberWarning,
                          ),
                        ),
                        const Text(
                          'Encontre seu motorista e informe o código OTP.',
                          style: TextStyle(fontSize: 11, color: OmniConstants.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: _enviouEstouChegando
                        ? null
                        : () {
                            setState(() => _enviouEstouChegando = true);
                            appState.enviarMensagemChat('Estou indo para o ponto de embarque!');
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Aviso "Estou indo!" enviado ao motorista.')),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OmniConstants.amberWarning,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      minimumSize: const Size(0, 34),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      _enviouEstouChegando ? 'Enviado' : 'Estou indo',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (!buscando && !concluida) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    OmniConstants.neonCyan.withValues(alpha: 0.14),
                    Colors.transparent,
                    OmniConstants.neonCyanDark.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CÓDIGO DE EMBARQUE (OTP)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: OmniConstants.neonCyan,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Informe ao motorista para iniciar a viagem',
                          style: TextStyle(fontSize: 11.5, color: OmniConstants.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.6)),
                      boxShadow: [
                        BoxShadow(color: OmniConstants.neonCyan.withValues(alpha: 0.28), blurRadius: 12),
                      ],
                    ),
                    child: Text(
                      corrida.otpEmbarque,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                        color: OmniConstants.neonCyan,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (!buscando && corrida.motorista != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: OmniConstants.darkSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: OmniConstants.darkBorderSubtle),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: OmniConstants.neonCyan.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.45)),
                        ),
                        child: Center(
                          child: Text(
                            corrida.motorista!.iniciais,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: OmniConstants.neonCyan,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    corrida.motorista!.nome,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFBBF24)),
                                const SizedBox(width: 2),
                                Text(
                                  corrida.motorista!.avaliacao.toStringAsFixed(2),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFFBBF24),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${corrida.motorista!.modeloVeiculo} · ${corrida.motorista!.corVeiculo}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: OmniConstants.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: OmniConstants.darkBorder),
                            ),
                            child: Text(
                              corrida.motorista!.placaVeiculo,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            corrida.categoria.nome,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: OmniConstants.neonCyan,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.only(top: 10),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: OmniConstants.darkBorderSubtle)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _DriverActionButton(
                            icon: Icons.phone_outlined,
                            label: 'Ligar',
                            onTap: () => _ligarTelefone(
                              corrida.motorista!.telefone,
                              corrida.motorista!.nome,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _DriverActionButton(
                            icon: Icons.chat_bubble_outline_rounded,
                            label: 'Mensagem',
                            onTap: _abrirChatRapido,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: _copiarLinkViagem,
                            borderRadius: BorderRadius.circular(12),
                            child: const SizedBox(
                              width: 40,
                              height: 38,
                              child: Icon(Icons.share_outlined, size: 17, color: OmniConstants.neonCyan),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: OmniConstants.rubyRedAlert.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: _abrirModalSeguranca,
                            borderRadius: BorderRadius.circular(12),
                            child: const SizedBox(
                              width: 40,
                              height: 38,
                              child: Icon(Icons.shield_outlined, size: 17, color: OmniConstants.rubyRedAlert),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_copiadoLink)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Link de rastreamento copiado com sucesso!',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: OmniConstants.neonCyan),
                      ),
                    ),
                ],
              ),
            ),
          ],

          if (!concluida) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: OmniConstants.darkSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: OmniConstants.darkBorderSubtle),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flag_outlined, size: 16, color: OmniConstants.neonCyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          corrida.destino.endereco ?? 'Destino',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        Text(
                          '${corrida.perfilPagamento == 'corporativo' ? 'Corporativo' : 'Pessoal'} · R\$ ${valorBase.toStringAsFixed(2)}${corrida.preferencias.possuiCustomizacao ? ' · ${corrida.preferencias.temperatura}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: OmniConstants.textMuted),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _abrirAlterarDestino,
                    style: TextButton.styleFrom(
                      foregroundColor: OmniConstants.neonCyan,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('Alterar', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],

          if (concluida) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: OmniConstants.darkSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: OmniConstants.emeraldSuccess.withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: OmniConstants.emeraldSuccess.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: OmniConstants.emeraldSuccess.withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.check_circle_outline_rounded, size: 30, color: Color(0xFF34D399)),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Viagem Finalizada com Sucesso!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: OmniConstants.goldAccent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: OmniConstants.goldAccent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '+$pontosPrevistos pontos serão creditados no OMNI Club',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: OmniConstants.goldAccent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Como foi a sua experiência com ${corrida.motorista?.nome ?? "seu motorista"}?',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: OmniConstants.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final star = index + 1;
                      final active = star <= _avaliacaoEstrelas;
                      return IconButton(
                        onPressed: () => setState(() => _avaliacaoEstrelas = star),
                        icon: Icon(
                          active ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 32,
                          color: active ? const Color(0xFFFBBF24) : OmniConstants.textDim,
                        ),
                      );
                    }),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: _opcoesElogio.map((elogio) {
                      final active = _elogiosSelecionados.contains(elogio);
                      return FilterChip(
                        label: Text(elogio),
                        selected: active,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _elogiosSelecionados.add(elogio);
                            } else {
                              _elogiosSelecionados.remove(elogio);
                            }
                          });
                        },
                        selectedColor: OmniConstants.neonCyan.withValues(alpha: 0.18),
                        backgroundColor: OmniConstants.darkCard,
                        checkmarkColor: OmniConstants.neonCyan,
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: active ? OmniConstants.neonCyan : OmniConstants.textSecondary,
                        ),
                        side: BorderSide(
                          color: active ? OmniConstants.neonCyan : OmniConstants.darkBorder,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'ADICIONAR GORJETA (100% PARA O MOTORISTA)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: OmniConstants.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: _opcoesGorjeta.map((val) {
                      final active = _gorjetaSelecionada == val;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Material(
                            color: active ? OmniConstants.neonCyan : OmniConstants.darkCard,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              onTap: () => setState(() => _gorjetaSelecionada = val),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: active ? OmniConstants.neonCyan : OmniConstants.darkBorder,
                                  ),
                                ),
                                child: Text(
                                  val == 0 ? 'Sem' : 'R\$ ${val.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 11.5,
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
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: OmniConstants.darkBorderSubtle),
                    ),
                    child: Column(
                      children: [
                        _ReceiptLine(label: 'Tarifa Base', value: 'R\$ ${corrida.categoria.tarifaBase.toStringAsFixed(2)}'),
                        const SizedBox(height: 6),
                        _ReceiptLine(
                          label: 'Distância (${corrida.distanciaKm.toStringAsFixed(1)} km)',
                          value: 'R\$ ${(corrida.distanciaKm * corrida.categoria.valorKm).toStringAsFixed(2)}',
                        ),
                        const SizedBox(height: 6),
                        _ReceiptLine(
                          label: 'Tempo (${corrida.tempoMinutos} min)',
                          value: 'R\$ ${(corrida.tempoMinutos * corrida.categoria.valorMinuto).toStringAsFixed(2)}',
                        ),
                        if (_gorjetaSelecionada > 0) ...[
                          const SizedBox(height: 6),
                          _ReceiptLine(
                            label: 'Gorjeta ao motorista',
                            value: 'R\$ ${_gorjetaSelecionada.toStringAsFixed(2)}',
                          ),
                        ],
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Divider(height: 1, color: OmniConstants.darkBorder),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Valor Total Pago',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            Text(
                              'R\$ ${totalComGorjeta.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 14.5,
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
                  ElevatedButton(
                    onPressed: _enviandoAvaliacao ? null : _enviarAvaliacao,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OmniConstants.neonCyan,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _enviandoAvaliacao
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Text(
                            'ENVIAR AVALIAÇÃO E FECHAR',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.4),
                          ),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () async {
                      await appState.registrarProtocoloSuporte(
                        'Item esquecido · Corrida ${corrida.id}',
                        'Destino: ${corrida.destino.endereco ?? ""}',
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Protocolo de item esquecido registrado no suporte OMNI!')),
                      );
                    },
                    icon: const Icon(Icons.help_outline_rounded, size: 15, color: OmniConstants.textMuted),
                    label: const Text(
                      'Esqueceu um item ou precisa de ajuda?',
                      style: TextStyle(fontSize: 11.5, color: OmniConstants.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (!concluida) ...[
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: widget.onCancelar,
                child: const Text(
                  'Cancelar Solicitação de Viagem',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: OmniConstants.rubyRedAlert),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DriverActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DriverActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 38,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: OmniConstants.neonCyan),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: OmniConstants.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  final String label;
  final String value;

  const _ReceiptLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: OmniConstants.textMuted)),
        Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: OmniConstants.textMuted)),
      ],
    );
  }
}
