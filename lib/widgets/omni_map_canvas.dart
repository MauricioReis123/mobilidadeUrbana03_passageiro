import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../constants/omni_constants.dart';
import '../models/motorista_model.dart';
import '../theme/omni_theme.dart';

/// Mapa Vetorial Interativo Neon Luxuoso (Fidelidade 1:1 ao OmniMapCanvas.tsx)
/// Usa coordenadas proporcionais em LayoutBuilder para nunca cortar ou estourar em nenhum celular.
class OmniMapCanvas extends StatefulWidget {
  final String origemEndereco;
  final String destinoEndereco;
  final List<String> paradas;
  final List<OmniMotoristaModel> motoristas;
  final OmniMotoristaModel? motoristaAtivo;
  final bool emViagem;
  final double distanciaKm;
  final int tempoMinutos;
  final VoidCallback? onRecenterGps;
  final double? precisaoMetros;
  final bool precisaoReduzidaAlerta;
  final void Function(double deltaLat, double deltaLng)? onAjustarPinoOrigem;

  const OmniMapCanvas({
    super.key,
    required this.origemEndereco,
    required this.destinoEndereco,
    required this.paradas,
    required this.motoristas,
    this.motoristaAtivo,
    this.emViagem = false,
    this.distanciaKm = 9.8,
    this.tempoMinutos = 22,
    this.onRecenterGps,
    this.precisaoMetros,
    this.precisaoReduzidaAlerta = false,
    this.onAjustarPinoOrigem,
  });

  @override
  State<OmniMapCanvas> createState() => _OmniMapCanvasState();
}

class _OmniMapCanvasState extends State<OmniMapCanvas> with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  String? _motoristaTooltipId;
  Offset _pinDragOffset = Offset.zero;
  bool _arrastandoPino = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String _curtoEndereco(String endereco) {
    final part = endereco.split('-').first.trim();
    return part.isEmpty ? endereco : part;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: OmniConstants.mapCanvasBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: OmniConstants.darkBorder),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double w = constraints.maxWidth;
            final double h = constraints.maxHeight;

            // Posições proporcionais seguras (nunca cortam nas bordas)
            final Offset origemPos = Offset(w * 0.17, h * 0.64);
            final Offset destinoPos = Offset(w * 0.83, h * 0.34);

            final List<Offset> driversOffsets = [
              Offset(w * 0.28, h * 0.42),
              Offset(w * 0.46, h * 0.66),
              Offset(w * 0.66, h * 0.36),
              Offset(w * 0.74, h * 0.62),
            ];

            return GestureDetector(
              onTap: () {
                if (_motoristaTooltipId != null) {
                  setState(() => _motoristaTooltipId = null);
                }
              },
              child: Stack(
                children: [
                  // Camada 1: Grade Viária Vetorial & Rota Neon Animada
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _animController,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _OmniVectorMapPainter(
                            origem: origemPos,
                            destino: destinoPos,
                            emViagem: widget.emViagem,
                            animProgress: _animController.value,
                          ),
                        );
                      },
                    ),
                  ),

                  // Camada 2: Motoristas no Radar (Firebase RTDB)
                  ...widget.motoristas.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final drv = entry.value;
                    final pos = driversOffsets[idx % driversOffsets.length];
                    final isAtivo = widget.motoristaAtivo?.id == drv.id;
                    final showTooltip = _motoristaTooltipId == drv.id;

                    return Positioned(
                      left: (pos.dx - 18).clamp(8.0, math.max(8.0, w - 44.0)),
                      top: (pos.dy - 18).clamp(48.0, math.max(48.0, h - 74.0)),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _motoristaTooltipId = showTooltip ? null : drv.id;
                          });
                        },
                        child: AnimatedScale(
                          scale: isAtivo ? 1.2 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isAtivo ? OmniConstants.neonCyan : OmniConstants.darkCard,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isAtivo
                                    ? OmniConstants.neonCyan
                                    : OmniConstants.neonCyan.withValues(alpha: 0.45),
                                width: isAtivo ? 2 : 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: OmniConstants.neonCyan.withValues(alpha: isAtivo ? 0.55 : 0.2),
                                  blurRadius: isAtivo ? 16 : 8,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Transform.rotate(
                                angle: math.pi / 4,
                                child: Icon(
                                  Icons.navigation_rounded,
                                  size: 16,
                                  color: isAtivo ? Colors.black : OmniConstants.neonCyan,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                  // Camada 3: Paradas Intermediárias (Ouro)
                  ...widget.paradas.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final double t = (idx + 1) / (widget.paradas.length + 1);
                    final double px = lerpDouble(origemPos.dx, destinoPos.dx, t) ?? w * 0.5;
                    final double py = lerpDouble(origemPos.dy, destinoPos.dy, t) ?? h * 0.5;

                    return Positioned(
                      left: (px - 32).clamp(8.0, math.max(8.0, w - 72.0)),
                      top: (py - 40).clamp(44.0, math.max(44.0, h - 68.0)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: OmniConstants.goldAccent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Parada ${idx + 1}',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: OmniConstants.goldAccent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                            child: Center(
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  // Camada 4: Pin de Origem (Ciano Neon Pulsante + Ajuste Fino por Arrasto)
                  Positioned(
                    left: (origemPos.dx + _pinDragOffset.dx - 32).clamp(8.0, math.max(8.0, w - 74.0)),
                    top: (origemPos.dy + _pinDragOffset.dy - 46).clamp(46.0, math.max(46.0, h - 74.0)),
                    child: GestureDetector(
                      onPanUpdate: widget.emViagem || widget.onAjustarPinoOrigem == null
                          ? null
                          : (details) {
                              setState(() {
                                _arrastandoPino = true;
                                _pinDragOffset = Offset(
                                  (_pinDragOffset.dx + details.delta.dx).clamp(-45.0, 45.0),
                                  (_pinDragOffset.dy + details.delta.dy).clamp(-45.0, 45.0),
                                );
                              });
                              const double degPerPixel = 0.000012;
                              widget.onAjustarPinoOrigem!(
                                -details.delta.dy * degPerPixel,
                                details.delta.dx * degPerPixel,
                              );
                            },
                      onPanEnd: widget.emViagem || widget.onAjustarPinoOrigem == null
                          ? null
                          : (_) => setState(() {
                                _arrastandoPino = false;
                                _pinDragOffset = Offset.zero;
                              }),
                      onPanCancel: () {
                        if (_arrastandoPino || _pinDragOffset != Offset.zero) {
                          setState(() {
                            _arrastandoPino = false;
                            _pinDragOffset = Offset.zero;
                          });
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: OmniConstants.neonCyan,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: OmniConstants.neonCyan.withValues(alpha: 0.45),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.my_location, size: 10, color: Colors.black),
                              const SizedBox(width: 3),
                              Text(
                                _arrastandoPino ? 'Ajustando ponto...' : 'Origem',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _animController,
                                builder: (context, _) {
                                  final scale = 0.7 + (_animController.value * 0.7);
                                  final opacity = (1.0 - _animController.value).clamp(0.0, 0.55);
                                  return Transform.scale(
                                    scale: scale,
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: OmniConstants.neonCyan.withValues(alpha: opacity),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: OmniConstants.neonCyan,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black, width: 2),
                                ),
                                child: Center(
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: const BoxDecoration(
                                      color: Colors.black,
                                      shape: BoxShape.circle,
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
                  ),

                  // Camada 5: Pin de Destino (Rosa-Rubi)
                  Positioned(
                    left: (destinoPos.dx - 34).clamp(8.0, math.max(8.0, w - 76.0)),
                    top: (destinoPos.dy - 46).clamp(46.0, math.max(46.0, h - 74.0)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: OmniConstants.rubyRedAlert,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: OmniConstants.rubyRedAlert.withValues(alpha: 0.45),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_on, size: 10, color: Colors.white),
                              SizedBox(width: 3),
                              Text(
                                'Destino',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: OmniConstants.rubyRedAlert,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Center(
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tooltip Flutuante ao Tocar em Motorista
                  if (_motoristaTooltipId != null)
                    Positioned(
                      top: 52,
                      left: 12,
                      right: 12,
                      child: Center(
                        child: _DriverTooltipBanner(
                          motorista: widget.motoristas.firstWhere(
                            (m) => m.id == _motoristaTooltipId,
                            orElse: () => widget.motoristas.first,
                          ),
                          onClose: () => setState(() => _motoristaTooltipId = null),
                        ),
                      ),
                    ),

                  // Camada 6: Barra Superior do Radar & Bússola (Protegida contra overflow)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: OmniConstants.darkSurface.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: OmniConstants.darkBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: OmniConstants.neonCyan,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    'Radar OMNI Ativo · ${widget.motoristas.length} motoristas ao redor',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: OmniConstants.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: OmniConstants.darkSurface.withValues(alpha: 0.92),
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: () {
                              widget.onRecenterGps?.call();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Atualizando sua posição atual via GPS...'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: OmniConstants.darkBorder),
                              ),
                              child: const Icon(
                                Icons.explore_outlined,
                                size: 17,
                                color: OmniConstants.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Badge de Precisão GPS / Alerta de Precisão Reduzida
                  if (widget.precisaoMetros != null || widget.precisaoReduzidaAlerta)
                    Positioned(
                      top: 48,
                      left: 10,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.precisaoMetros != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: OmniConstants.darkSurface.withValues(alpha: 0.90),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: widget.precisaoMetros! <= 15.0
                                      ? OmniConstants.emeraldSuccess.withValues(alpha: 0.55)
                                      : OmniConstants.amberWarning.withValues(alpha: 0.55),
                                ),
                              ),
                              child: Text(
                                'Precisão: ${widget.precisaoMetros!.round()}m',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: widget.precisaoMetros! <= 15.0
                                      ? const Color(0xFF34D399)
                                      : OmniConstants.amberWarning,
                                ),
                              ),
                            ),
                          if (widget.precisaoReduzidaAlerta) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () {
                                if (!kIsWeb) {
                                  Geolocator.openLocationSettings();
                                } else {
                                  widget.onRecenterGps?.call();
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: OmniConstants.amberWarning.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: OmniConstants.amberWarning),
                                ),
                                child: const Text(
                                  'Ative Localização Exata',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: OmniConstants.amberWarning,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                  // Camada 7: Rodapé de Trajeto (Protegido com Expanded + Ellipsis)
                  Positioned(
                    bottom: 10,
                    left: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: OmniConstants.darkSurface.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: OmniConstants.darkBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: RichText(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                style: const TextStyle(fontSize: 11),
                                children: [
                                  const TextSpan(
                                    text: 'Trajeto: ',
                                    style: TextStyle(
                                      color: OmniConstants.neonCyan,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(
                                    text:
                                        '${_curtoEndereco(widget.origemEndereco)} ➔ ${_curtoEndereco(widget.destinoEndereco)}',
                                    style: const TextStyle(color: OmniConstants.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${widget.distanciaKm.toStringAsFixed(1)} km · ~${widget.tempoMinutos} min',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
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
            );
          },
        ),
      ),
    );
  }
}

class _DriverTooltipBanner extends StatelessWidget {
  final OmniMotoristaModel motorista;
  final VoidCallback onClose;

  const _DriverTooltipBanner({required this.motorista, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: OmniTheme.neonBoxDecoration(
        borderColor: OmniConstants.neonCyan,
        borderRadius: 12,
        glowRadius: 12,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.directions_car_rounded, color: OmniConstants.neonCyan, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  motorista.nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: OmniConstants.neonCyan,
                  ),
                ),
                Text(
                  '${motorista.modeloVeiculo} · ⭐ ${motorista.avaliacao} · ${motorista.placaVeiculo}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: OmniConstants.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClose,
            child: const Icon(Icons.close, size: 14, color: OmniConstants.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Desenhador Vetorial da Malha Viária e Rota Neon
class _OmniVectorMapPainter extends CustomPainter {
  final Offset origem;
  final Offset destino;
  final bool emViagem;
  final double animProgress;

  _OmniVectorMapPainter({
    required this.origem,
    required this.destino,
    required this.emViagem,
    required this.animProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Grade Urbana Neon (48x48)
    final gridPaint = Paint()
      ..color = OmniConstants.neonCyan.withValues(alpha: 0.08)
      ..strokeWidth = 0.8;
    final dotPaint = Paint()
      ..color = OmniConstants.neonCyan.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;

    const double step = 44.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (double x = step / 2; x < size.width; x += step) {
      for (double y = step / 2; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }

    // 2. Avenidas e Vias Expressas de Fundo
    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final avenue1 = Path()
      ..moveTo(0, size.height * 0.25)
      ..quadraticBezierTo(size.width * 0.35, size.height * 0.45, size.width * 0.65, size.height * 0.35)
      ..quadraticBezierTo(size.width * 0.85, size.height * 0.28, size.width, size.height * 0.45);
    canvas.drawPath(avenue1, roadPaint);

    final avenue2 = Path()
      ..moveTo(size.width * 0.18, 0)
      ..quadraticBezierTo(size.width * 0.38, size.height * 0.42, size.width * 0.55, size.height * 0.72)
      ..quadraticBezierTo(size.width * 0.68, size.height * 0.9, size.width * 0.75, size.height);
    canvas.drawPath(avenue2, roadPaint);

    // 3. Curva da Rota Ativa
    final routePath = Path()
      ..moveTo(origem.dx, origem.dy)
      ..cubicTo(
        size.width * 0.32,
        size.height * 0.46,
        size.width * 0.50,
        size.height * 0.66,
        size.width * 0.62,
        size.height * 0.44,
      )
      ..quadraticBezierTo(
        size.width * 0.73,
        size.height * 0.30,
        destino.dx,
        destino.dy,
      );

    // Halo Neon Externo
    final glowPaint = Paint()
      ..color = OmniConstants.neonCyan.withValues(alpha: 0.22)
      ..strokeWidth = 10.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(routePath, glowPaint);

    // Traçado Gradiente Principal
    final gradientPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          OmniConstants.neonCyan,
          OmniConstants.neonCyanDark,
          OmniConstants.rubyRedAlert,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (!emViagem) {
      canvas.drawPath(routePath, gradientPaint);
    } else {
      // Efeito tracejado em movimento quando em viagem
      for (final metric in routePath.computeMetrics()) {
        double distance = (animProgress * 16.0);
        while (distance < metric.length) {
          final double end = math.min(distance + 8.0, metric.length);
          final segment = metric.extractPath(distance, end);
          canvas.drawPath(segment, gradientPaint);
          distance += 16.0;
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OmniVectorMapPainter oldDelegate) {
    return oldDelegate.origem != origem ||
        oldDelegate.destino != destino ||
        oldDelegate.emViagem != emViagem ||
        oldDelegate.animProgress != animProgress;
  }
}
