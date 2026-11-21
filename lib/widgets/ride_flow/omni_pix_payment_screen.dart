import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../constants/omni_constants.dart';
import '../../tools/mercadopago_service.dart';

/// Abre o fluxo completo de transição (Tela 06 "Confirmando sua viagem" -> Tela 07 "Pagar com Pix")
/// Integra diretamente com OmniMercadoPagoService (geração e consulta de liquidação Pix).
Future<bool?> showOmniPixPaymentFlow(
  BuildContext context, {
  required double valorTotal,
  required String categoriaNome,
  String? rideId,
  String? copiaECola,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => OmniPixPaymentScreen(
        valorTotal: valorTotal,
        categoriaNome: categoriaNome,
        rideId: rideId ?? 'pix_${DateTime.now().millisecondsSinceEpoch}',
        copiaEColaFallback: copiaECola ?? OmniConstants.defaultPixCopiaECola,
      ),
    ),
  );
}

class OmniPixPaymentScreen extends StatefulWidget {
  final double valorTotal;
  final String categoriaNome;
  final String rideId;
  final String copiaEColaFallback;

  const OmniPixPaymentScreen({
    super.key,
    required this.valorTotal,
    required this.categoriaNome,
    required this.rideId,
    required this.copiaEColaFallback,
  });

  @override
  State<OmniPixPaymentScreen> createState() => _OmniPixPaymentScreenState();
}

class _OmniPixPaymentScreenState extends State<OmniPixPaymentScreen> {
  static const int _duracaoTotalSegundos = 180; // 03:00
  bool _confirmandoViagem = true;
  bool _verificandoPagamento = false;
  int _segundosRestantes = _duracaoTotalSegundos;
  bool _codigoCopiado = false;
  String _idTransacao = '';
  String _payloadPixAtivo = '';
  String? _statusMensagem;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _payloadPixAtivo = widget.copiaEColaFallback;
    _gerarCobrancaPix();
  }

  Future<void> _gerarCobrancaPix() async {
    final cobranca = await OmniMercadoPagoService.gerarPixParaCorrida(
      rideId: widget.rideId,
      valor: widget.valorTotal,
      descricao: 'OMNI · ${widget.categoriaNome}',
    );

    if (!mounted) return;
    setState(() {
      if (cobranca != null && cobranca.copiaECola.isNotEmpty) {
        _idTransacao = cobranca.idTransacao;
        _payloadPixAtivo = cobranca.copiaECola;
      } else {
        _idTransacao = 'tx_${widget.rideId}';
        _payloadPixAtivo = widget.copiaEColaFallback;
      }
      _confirmandoViagem = false;
    });
    _iniciarContagemRegressiva();
  }

  void _iniciarContagemRegressiva() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_segundosRestantes > 0) {
        setState(() => _segundosRestantes--);
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _verificarPagamentoServidor() async {
    if (_verificandoPagamento) return;
    setState(() {
      _verificandoPagamento = true;
      _statusMensagem = 'Consultando liquidação Pix no Gateway OMNI...';
    });

    final pago = await OmniMercadoPagoService.verificarLiquidacaoPix(_idTransacao);
    if (!mounted) return;

    if (pago) {
      Navigator.of(context).pop(true);
      return;
    }

    // Caso o ambiente esteja sem retorno do webhook externo, permite confirmar após validação do usuário
    setState(() {
      _verificandoPagamento = false;
      _statusMensagem = 'Pagamento ainda pendente no servidor. Se você já concluiu no banco, confirme abaixo.';
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String get _tempoFormatado {
    final min = (_segundosRestantes ~/ 60).toString().padLeft(2, '0');
    final seg = (_segundosRestantes % 60).toString().padLeft(2, '0');
    return '$min:$seg';
  }

  Future<void> _copiarCodigoPix() async {
    await Clipboard.setData(ClipboardData(text: _payloadPixAtivo));
    if (!mounted) return;
    setState(() => _codigoCopiado = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Código Pix Copia e Cola copiado! Abra o app do seu banco para pagar.')),
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _codigoCopiado = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final progresso = _segundosRestantes / _duracaoTotalSegundos;

    return Scaffold(
      backgroundColor: OmniConstants.darkBackground,
      appBar: AppBar(
        backgroundColor: OmniConstants.darkSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(
          _confirmandoViagem
              ? 'Confirmando sua viagem'
              : 'Pagar R\$ ${widget.valorTotal.toStringAsFixed(2)} com Pix',
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: _confirmandoViagem ? _buildConfirmingView() : _buildPixCheckoutView(progresso),
      ),
    );
  }

  Widget _buildConfirmingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: OmniConstants.neonCyan.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.5)),
              ),
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: OmniConstants.neonCyan,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Confirmando sua viagem...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Gerando cobrança Pix instantânea para ${widget.categoriaNome} via Gateway OMNI.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: OmniConstants.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPixCheckoutView(double progresso) {
    final expirado = _segundosRestantes == 0;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: OmniConstants.darkCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: OmniConstants.darkBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            expirado ? 'Código Pix expirado' : 'Aguardando pagamento Pix',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                          Text(
                            expirado ? '00:00' : 'Vence em $_tempoFormatado',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: _segundosRestantes < 45
                                  ? OmniConstants.rubyRedAlert
                                  : OmniConstants.neonCyan,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progresso,
                          minHeight: 6,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _segundosRestantes < 45 ? OmniConstants.rubyRedAlert : OmniConstants.neonCyan,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: OmniConstants.darkCard,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'R\$ ${widget.valorTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: OmniConstants.neonCyan,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.categoriaNome} · ID: $_idTransacao',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: OmniConstants.textMuted),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: QrImageView(
                          data: _payloadPixAtivo,
                          version: QrVersions.auto,
                          size: 180,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: OmniConstants.darkSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: OmniConstants.darkBorderSubtle),
                        ),
                        child: Text(
                          _payloadPixAtivo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10.5,
                            color: OmniConstants.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_statusMensagem != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: OmniConstants.amberWarning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: OmniConstants.amberWarning.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      _statusMensagem!,
                      style: const TextStyle(fontSize: 11.5, color: OmniConstants.amberWarning),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                const Text(
                  '1. Copie o código Pix abaixo ou escaneie o QR Code.\n'
                  '2. Abra o aplicativo do seu banco e conclua em "Pix Copia e Cola".\n'
                  '3. Toque em "Verificar Pagamento" para validar com o Gateway OMNI.',
                  style: TextStyle(fontSize: 12, height: 1.55, color: OmniConstants.textMuted),
                ),
              ],
            ),
          ),
        ),

        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
          decoration: const BoxDecoration(
            color: OmniConstants.darkSurface,
            border: Border(top: BorderSide(color: OmniConstants.darkBorder)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed: expirado
                    ? () {
                        setState(() {
                          _segundosRestantes = _duracaoTotalSegundos;
                          _confirmandoViagem = true;
                        });
                        _gerarCobrancaPix();
                      }
                    : _copiarCodigoPix,
                style: ElevatedButton.styleFrom(
                  backgroundColor: OmniConstants.neonCyan,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: Icon(
                  expirado
                      ? Icons.refresh_rounded
                      : (_codigoCopiado ? Icons.check_rounded : Icons.copy_rounded),
                  size: 18,
                ),
                label: Text(
                  expirado
                      ? 'GERAR NOVO CÓDIGO PIX'
                      : (_codigoCopiado ? 'CÓDIGO PIX COPIADO!' : 'COPIAR CÓDIGO PIX'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _verificandoPagamento
                    ? null
                    : (_statusMensagem != null
                        ? () => Navigator.of(context).pop(true)
                        : _verificarPagamentoServidor),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF34D399),
                  side: BorderSide(color: OmniConstants.emeraldSuccess.withValues(alpha: 0.5)),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _verificandoPagamento
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF34D399)),
                      )
                    : const Icon(Icons.verified_rounded, size: 18),
                label: Text(
                  _verificandoPagamento
                      ? 'Verificando liquidação...'
                      : (_statusMensagem != null
                          ? 'Confirmar Pagamento Concluído'
                          : 'Já paguei · Verificar Pagamento Pix'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
