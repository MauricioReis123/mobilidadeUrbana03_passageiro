import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/omni_constants.dart';
import '../../state/omni_app_state.dart';
import 'omni_pix_payment_screen.dart';

/// Resultado da seleção de pagamento, perfil, cartão real e cupom promocional
class OmniPaymentSelection {
  final String metodoPagamento; // 'pix' | 'cartao' | 'dinheiro'
  final String perfilPagamento; // 'pessoal' | 'corporativo'
  final bool usarSaldoCarteira;
  final String? cartaoId;
  final String? cartaoResumo;
  final String? cupomAplicado;
  final double descontoPercentual;

  const OmniPaymentSelection({
    required this.metodoPagamento,
    this.perfilPagamento = 'pessoal',
    this.usarSaldoCarteira = false,
    this.cartaoId,
    this.cartaoResumo,
    this.cupomAplicado,
    this.descontoPercentual = 0.0,
  });

  String get resumoCurto {
    switch (metodoPagamento) {
      case 'pix':
        return 'PIX';
      case 'cartao':
        return cartaoResumo ?? 'Cartão de Crédito';
      default:
        return 'Na hora (Dinheiro/Pix)';
    }
  }
}

/// Modal "Pague com" conectado ao OmniAppState (Saldo Real, Cartões Persistidos, Recarga Pix e Cupons)
Future<OmniPaymentSelection?> showOmniPaymentMethodSheet(
  BuildContext context, {
  required OmniPaymentSelection currentSelection,
}) {
  return showModalBottomSheet<OmniPaymentSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _OmniPaymentMethodSheet(initial: currentSelection),
  );
}

class _OmniPaymentMethodSheet extends StatefulWidget {
  final OmniPaymentSelection initial;

  const _OmniPaymentMethodSheet({required this.initial});

  @override
  State<_OmniPaymentMethodSheet> createState() => _OmniPaymentMethodSheetState();
}

class _OmniPaymentMethodSheetState extends State<_OmniPaymentMethodSheet> {
  late String _metodo;
  late String _perfil;
  late bool _usarSaldo;
  String? _cartaoSelecionadoId;
  String? _cartaoResumo;
  String? _cupomAplicado;
  double _descontoPercentual = 0.0;

  bool _mostrandoFormCartao = false;
  final TextEditingController _cupomController = TextEditingController();
  final TextEditingController _numeroCartaoController = TextEditingController();
  final TextEditingController _titularCartaoController = TextEditingController();
  String? _mensagemCupom;
  String? _erroCartao;

  static const Map<String, double> _cuponsValidos = {
    'OMNI10': 10.0,
    'OMNI15': 15.0,
    'PRIMEIRA20': 20.0,
  };

  @override
  void initState() {
    super.initState();
    _metodo = widget.initial.metodoPagamento;
    _perfil = widget.initial.perfilPagamento;
    _usarSaldo = widget.initial.usarSaldoCarteira;
    _cartaoSelecionadoId = widget.initial.cartaoId;
    _cartaoResumo = widget.initial.cartaoResumo;
    _cupomAplicado = widget.initial.cupomAplicado;
    _descontoPercentual = widget.initial.descontoPercentual;
  }

  @override
  void dispose() {
    _cupomController.dispose();
    _numeroCartaoController.dispose();
    _titularCartaoController.dispose();
    super.dispose();
  }

  void _aplicarCupom() {
    final code = _cupomController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    if (_cuponsValidos.containsKey(code)) {
      setState(() {
        _cupomAplicado = code;
        _descontoPercentual = _cuponsValidos[code]!;
        _mensagemCupom = 'Cupom $code aplicado (${_descontoPercentual.toStringAsFixed(0)}% OFF)!';
        _cupomController.clear();
      });
    } else {
      setState(() {
        _mensagemCupom = 'Cupom inválido. Códigos ativos: OMNI10, OMNI15 ou PRIMEIRA20.';
      });
    }
  }

  Future<void> _salvarNovoCartao(OmniAppState appState) async {
    final digitos = _numeroCartaoController.text.replaceAll(RegExp(r'\D'), '');
    if (digitos.length < 13) {
      setState(() => _erroCartao = 'Informe um número de cartão válido (mínimo 13 dígitos).');
      return;
    }
    final card = await appState.adicionarCartao(
      numeroCompleto: digitos,
      titular: _titularCartaoController.text,
    );
    if (!mounted) return;
    setState(() {
      _metodo = 'cartao';
      _cartaoSelecionadoId = card.id;
      _cartaoResumo = '${card.bandeira} •••• ${card.ultimos4}';
      _mostrandoFormCartao = false;
      _erroCartao = null;
      _numeroCartaoController.clear();
      _titularCartaoController.clear();
    });
  }

  Future<void> _recarregarSaldoViaPix(OmniAppState appState) async {
    const double valorRecarga = 50.00;
    final ok = await showOmniPixPaymentFlow(
      context,
      valorTotal: valorRecarga,
      categoriaNome: 'Recarga OMNI Cash',
    );
    if (ok == true && mounted) {
      await appState.creditarSaldoCarteira(valorRecarga);
      setState(() => _usarSaldo = true);
    }
  }

  void _confirmarESair() {
    Navigator.of(context).pop(
      OmniPaymentSelection(
        metodoPagamento: _metodo,
        perfilPagamento: _perfil,
        usarSaldoCarteira: _usarSaldo,
        cartaoId: _cartaoSelecionadoId,
        cartaoResumo: _cartaoResumo,
        cupomAplicado: _cupomAplicado,
        descontoPercentual: _descontoPercentual,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<OmniAppState>();
    final saldoDisponivel = appState.passageiro.saldoCarteira;
    final cartoes = appState.cartoesSalvos;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        padding: EdgeInsets.only(bottom: bottomInset),
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
                  const Expanded(
                    child: Text(
                      'Pague com',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Perfil Pessoal | Corporativo
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
                            child: _ProfileChip(
                              icon: Icons.person_outline_rounded,
                              label: 'Pessoal',
                              selected: _perfil == 'pessoal',
                              onTap: () => setState(() => _perfil = 'pessoal'),
                            ),
                          ),
                          Expanded(
                            child: _ProfileChip(
                              icon: Icons.business_center_outlined,
                              label: 'Corporativo',
                              selected: _perfil == 'corporativo',
                              onTap: () => setState(() => _perfil = 'corporativo'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 2. Saldo OMNI Cash Real + Botão Recarregar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: OmniConstants.darkSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _usarSaldo
                              ? OmniConstants.neonCyan.withValues(alpha: 0.45)
                              : OmniConstants.darkBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: OmniConstants.goldAccent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet_outlined,
                              color: OmniConstants.goldAccent,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Saldo OMNI Cash',
                                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                                Text(
                                  'Disponível: R\$ ${saldoDisponivel.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 11.5, color: OmniConstants.neonCyan),
                                ),
                              ],
                            ),
                          ),
                          if (saldoDisponivel <= 0)
                            TextButton(
                              onPressed: () => _recarregarSaldoViaPix(appState),
                              style: TextButton.styleFrom(
                                foregroundColor: OmniConstants.neonCyan,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              child: const Text('+ R\$ 50', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                            )
                          else
                            Switch(
                              value: _usarSaldo,
                              onChanged: (v) => setState(() => _usarSaldo = v),
                              activeThumbColor: OmniConstants.neonCyan,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. Formas de Pagamento Reais
                    const Text(
                      'FORMAS DE PAGAMENTO',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: OmniConstants.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),

                    _PaymentOptionTile(
                      icon: Icons.qr_code_2_rounded,
                      title: 'PIX Instantâneo',
                      subtitle: 'Aprovação imediata · Mercado Pago OMNI',
                      badge: 'Recomendado',
                      selected: _metodo == 'pix',
                      onTap: () => setState(() {
                        _metodo = 'pix';
                        _cartaoSelecionadoId = null;
                      }),
                    ),
                    const SizedBox(height: 8),

                    // Cartões reais salvos pelo usuário
                    ...cartoes.map((card) {
                      final active = _metodo == 'cartao' && _cartaoSelecionadoId == card.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PaymentOptionTile(
                          icon: Icons.credit_card_rounded,
                          title: '${card.bandeira} •••• ${card.ultimos4}',
                          subtitle: 'Titular: ${card.titular}',
                          selected: active,
                          onTap: () => setState(() {
                            _metodo = 'cartao';
                            _cartaoSelecionadoId = card.id;
                            _cartaoResumo = '${card.bandeira} •••• ${card.ultimos4}';
                          }),
                          onDelete: () async {
                            await appState.removerCartao(card.id);
                            if (active && mounted) {
                              setState(() {
                                _metodo = 'pix';
                                _cartaoSelecionadoId = null;
                                _cartaoResumo = null;
                              });
                            }
                          },
                        ),
                      );
                    }),

                    _PaymentOptionTile(
                      icon: Icons.payments_outlined,
                      title: 'Pagamento na hora',
                      subtitle: 'Dinheiro ou QR Code Pix direto com o motorista',
                      selected: _metodo == 'dinheiro',
                      onTap: () => setState(() {
                        _metodo = 'dinheiro';
                        _cartaoSelecionadoId = null;
                      }),
                    ),
                    const SizedBox(height: 10),

                    // Adicionar cartão real
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() => _mostrandoFormCartao = !_mostrandoFormCartao),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.add_circle_outline_rounded, color: OmniConstants.neonCyan, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _mostrandoFormCartao
                                    ? 'Ocultar cadastro de cartão'
                                    : 'Adicionar cartão de crédito/débito',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: OmniConstants.neonCyan,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    if (_mostrandoFormCartao) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: OmniConstants.darkSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: OmniConstants.darkBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _numeroCartaoController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(fontSize: 12.5, color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Número do cartão (somente dígitos)',
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _titularCartaoController,
                              textCapitalization: TextCapitalization.words,
                              style: const TextStyle(fontSize: 12.5, color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Nome impresso no cartão',
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                            ),
                            if (_erroCartao != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                _erroCartao!,
                                style: const TextStyle(fontSize: 11, color: OmniConstants.rubyRedAlert),
                              ),
                            ],
                            const SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: () => _salvarNovoCartao(appState),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: OmniConstants.neonCyan,
                                foregroundColor: Colors.black,
                                minimumSize: const Size(double.infinity, 42),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('SALVAR CARTÃO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // 4. Vouchers e Cupons Promocionais
                    const Text(
                      'VOUCHERS & CUPONS',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: OmniConstants.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: OmniConstants.darkSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: OmniConstants.darkBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _cupomController,
                                  textCapitalization: TextCapitalization.characters,
                                  style: const TextStyle(fontSize: 12.5, color: Colors.white),
                                  decoration: const InputDecoration(
                                    hintText: 'Digite o cupom (ex: OMNI10)',
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _aplicarCupom,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: OmniConstants.neonCyan.withValues(alpha: 0.16),
                                  foregroundColor: OmniConstants.neonCyan,
                                  elevation: 0,
                                  minimumSize: const Size(0, 42),
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(color: OmniConstants.neonCyan.withValues(alpha: 0.45)),
                                  ),
                                ),
                                child: const Text('Aplicar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                          if (_cupomAplicado != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: OmniConstants.emeraldSuccess.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: OmniConstants.emeraldSuccess.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.local_offer_rounded, size: 14, color: Color(0xFF34D399)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '$_cupomAplicado ativo (${_descontoPercentual.toStringAsFixed(0)}% OFF)',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF34D399),
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => setState(() {
                                      _cupomAplicado = null;
                                      _descontoPercentual = 0.0;
                                      _mensagemCupom = null;
                                    }),
                                    child: const Icon(Icons.close, size: 15, color: OmniConstants.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (_mensagemCupom != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _mensagemCupom!,
                              style: const TextStyle(fontSize: 11, color: OmniConstants.amberWarning),
                            ),
                          ],
                        ],
                      ),
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
              child: ElevatedButton(
                onPressed: _confirmarESair,
                style: ElevatedButton.styleFrom(
                  backgroundColor: OmniConstants.neonCyan,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'CONFIRMAR FORMA DE PAGAMENTO',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileChip({
    required this.icon,
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
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.black : OmniConstants.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
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

class _PaymentOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _PaymentOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? OmniConstants.neonCyan.withValues(alpha: 0.1) : OmniConstants.darkSurface,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? OmniConstants.neonCyan : OmniConstants.darkBorder,
              width: selected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: selected ? OmniConstants.neonCyan : OmniConstants.textSecondary,
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
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: OmniConstants.neonCyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge!,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: OmniConstants.neonCyan,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: OmniConstants.textMuted),
                    ),
                  ],
                ),
              ),
              if (onDelete != null) ...[
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: OmniConstants.textMuted),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? OmniConstants.neonCyan : OmniConstants.textDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
