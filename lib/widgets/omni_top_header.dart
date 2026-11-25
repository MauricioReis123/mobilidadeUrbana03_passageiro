import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/omni_integration_contracts.dart';
import '../constants/omni_constants.dart';
import '../screens/admin_campanhas_passageiro_screen.dart';
import '../state/omni_app_state.dart';
import '../tools/backends_service.dart';

/// Abas principais do aplicativo OMNI Passageiro
enum OmniMainTab { corridas, fidelidade, codigo }

/// Barra Superior Fixa — 100% Interativa (Wordmark clicável, Perfil editável, Status RTDB e Barra de Teste Híbrido HTTP+HTTPS)
class OmniTopHeader extends StatefulWidget {
  final OmniMainTab activeTab;
  final ValueChanged<OmniMainTab> onSelectTab;
  final bool isExpandedLayout;
  final VoidCallback? onToggleLayout;
  final bool rtdbConnected;

  const OmniTopHeader({
    super.key,
    required this.activeTab,
    required this.onSelectTab,
    this.isExpandedLayout = false,
    this.onToggleLayout,
    this.rtdbConnected = true,
  });

  @override
  State<OmniTopHeader> createState() => _OmniTopHeaderState();
}

class _OmniTopHeaderState extends State<OmniTopHeader> {
  bool _testandoComunicacao = false;
  bool _salvandoDominio = false;
  bool _dominioSalvoRecente = false;
  late final TextEditingController _dominioController;

  @override
  void initState() {
    super.initState();
    _dominioController = TextEditingController(text: OmniRouterConfig.configuredInput);
    _sincronizarDominioDoCache();
  }

  Future<void> _sincronizarDominioDoCache() async {
    final cached = await OmniBackendUniversal.carregarDominioDoCache();
    if (mounted && _dominioController.text.trim() != cached) {
      _dominioController.text = cached;
    }
  }

  @override
  void dispose() {
    _dominioController.dispose();
    super.dispose();
  }

  Future<void> _salvarDominio() async {
    if (_salvandoDominio) return;
    setState(() => _salvandoDominio = true);
    try {
      final raw = _dominioController.text;
      final appState = context.read<OmniAppState>();
      final saved = await appState.salvarBackendDominio(raw);
      if (!mounted) return;
      _dominioController.text = saved;
      setState(() => _dominioSalvoRecente = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Domínio "$saved" salvo em cache!\nURL: ${OmniRouterConfig.baseUrl}'),
          duration: const Duration(seconds: 3),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _dominioSalvoRecente = false);
      });
    } finally {
      if (mounted) setState(() => _salvandoDominio = false);
    }
  }

  Future<void> _executarTesteComunicacao() async {
    if (_testandoComunicacao) return;
    final digitado = _dominioController.text.trim();
    if (digitado.isNotEmpty && digitado != OmniRouterConfig.configuredInput) {
      await context.read<OmniAppState>().salvarBackendDominio(digitado);
    }
    if (!mounted) return;
    setState(() => _testandoComunicacao = true);

    final sw = Stopwatch()..start();
    OmniBackendResponse resposta;
    try {
      resposta = await OmniBackendUniversal.testarComunicacaoHibrida(
        targetMethod: OmniBackendMethods.systemPing,
        args: {
          'origem': 'app_passageiro_flutter',
          'modo': 'hibrido_http_https',
          'dominio_configurado': OmniRouterConfig.configuredInput,
          'app_version': OmniConstants.appVersion,
        },
      );
    } catch (e) {
      resposta = OmniBackendResponse.erro(
        'Erro inesperado ao executar teste: ${e.toString()}',
        statusCode: 0,
      );
    } finally {
      sw.stop();
      if (mounted) {
        setState(() => _testandoComunicacao = false);
      }
    }

    if (!mounted) return;
    final Color corStatus = resposta.sucesso ? OmniConstants.emeraldSuccess : OmniConstants.rubyRedAlert;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (ctx) => Dialog(
        backgroundColor: OmniConstants.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: corStatus.withValues(alpha: 0.55)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      resposta.sucesso ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      color: corStatus,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            resposta.sucesso ? 'Comunicação OK!' : 'Falha em HTTP e HTTPS',
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          Text(
                            'Tempo: ${sw.elapsedMilliseconds} ms · ${OmniBackendMethods.systemPing}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10.5,
                              color: OmniConstants.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...resposta.tentativas.map((t) {
                  final corTentativa = t.sucesso ? OmniConstants.emeraldSuccess : OmniConstants.rubyRedAlert;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: OmniConstants.darkSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: corTentativa.withValues(alpha: 0.45)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: corTentativa.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${t.protocolo} · ${t.sucesso ? "SUCESSO" : "FALHOU"}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: corTentativa,
                                ),
                              ),
                            ),
                            Text(
                              'HTTP ${t.statusCode} · ${t.latenciaMs} ms',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10.5,
                                color: OmniConstants.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.url,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.mensagem,
                          style: const TextStyle(fontSize: 11.5, color: OmniConstants.textSecondary),
                        ),
                        if (t.dados != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              t.dados.toString(),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10.5,
                                color: OmniConstants.neonCyan,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _executarTesteComunicacao();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: OmniConstants.neonCyan,
                          side: BorderSide(color: OmniConstants.neonCyan.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Testar de novo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: OmniConstants.neonCyan,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Fechar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _abrirModalPerfil(BuildContext context) {
    final appState = context.read<OmniAppState>();
    final p = appState.passageiro;
    final nomeCtrl = TextEditingController(text: p.nome);
    final emailCtrl = TextEditingController(text: p.email);
    final foneCtrl = TextEditingController(text: p.telefone);
    final cpfCtrl = TextEditingController(text: p.cpf);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
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
                      const Icon(Icons.person_rounded, color: OmniConstants.neonCyan, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Minha Conta OMNI',
                          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Colors.white),
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: OmniConstants.darkSurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: OmniConstants.darkBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    appState.nivelFidelidadeAtual.nome,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: OmniConstants.goldAccent,
                                    ),
                                  ),
                                  Text(
                                    '${p.saldoPontos} pontos · ${appState.historicoCorridas.length} viagens',
                                    style: const TextStyle(fontSize: 11, color: OmniConstants.textMuted),
                                  ),
                                ],
                              ),
                              Text(
                                'R\$ ${p.saldoCarteira.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: OmniConstants.neonCyan,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: nomeCtrl,
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                          decoration: const InputDecoration(labelText: 'Nome completo'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                          decoration: const InputDecoration(labelText: 'E-mail'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: foneCtrl,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                          decoration: const InputDecoration(labelText: 'WhatsApp / Telefone'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: cpfCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 13, color: Colors.white),
                          decoration: const InputDecoration(labelText: 'CPF (para nota fiscal e Pix)'),
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: emailCtrl,
                          builder: (_, val, __) {
                            final ehDono = val.text.trim().toLowerCase() == OmniRtdbConfig.ownerEmail ||
                                appState.ehProprietarioAutorizado;
                            if (!ehDono) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  final typedEmail = emailCtrl.text.trim();
                                  Navigator.of(ctx).pop();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AdminCampanhasPassageiroScreen(
                                        initialEmail: typedEmail,
                                      ),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: OmniConstants.goldAccent,
                                  side: const BorderSide(color: OmniConstants.goldAccent),
                                  minimumSize: const Size(double.infinity, 44),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: const Icon(Icons.campaign_rounded, size: 18),
                                label: const Text(
                                  'MOTOR DE CAMPANHAS & PUSH (DONO)',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                                ),
                              ),
                            );
                          },
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
                    onPressed: () async {
                      await appState.atualizarPerfil(
                        nome: nomeCtrl.text,
                        email: emailCtrl.text,
                        telefone: foneCtrl.text,
                        cpf: cpfCtrl.text,
                      );
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Perfil atualizado e salvo com sucesso!')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: OmniConstants.neonCyan,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'SALVAR DADOS DO PERFIL',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      nomeCtrl.dispose();
      emailCtrl.dispose();
      foneCtrl.dispose();
      cpfCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<OmniAppState>();
    final bool conectado = appState.rtdbConectado || widget.rtdbConnected;

    return Container(
      decoration: BoxDecoration(
        color: OmniConstants.darkSurface.withValues(alpha: 0.94),
        border: const Border(
          bottom: BorderSide(color: OmniConstants.darkBorder, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isTabletOrWide = constraints.maxWidth >= 768;
            final bool isVeryWide = constraints.maxWidth >= 1024;

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isTabletOrWide ? 24 : 16,
                vertical: 10,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                  // Zona 1: Wordmark OMNI PASSAGEIRO (clicável para voltar à Home)
                  Flexible(
                    child: InkWell(
                      onTap: () => widget.onSelectTab(OmniMainTab.corridas),
                      borderRadius: BorderRadius.circular(10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: OmniConstants.neonCyan,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: OmniConstants.neonCyan.withValues(alpha: 0.4),
                                  blurRadius: 15,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.bolt_rounded, color: Colors.black, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: RichText(
                                maxLines: 1,
                                text: const TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'OMNI ',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'PASSAGEIRO',
                                      style: TextStyle(
                                        color: OmniConstants.neonCyan,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w300,
                                        letterSpacing: 2.2,
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
                  ),

                  // Zona 2: Links inline em tablets/telas largas
                  if (isTabletOrWide) ...[
                    const SizedBox(width: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DesktopNavLink(
                          icon: Icons.location_on_outlined,
                          label: 'Mapa & Corridas',
                          active: widget.activeTab == OmniMainTab.corridas,
                          onTap: () => widget.onSelectTab(OmniMainTab.corridas),
                        ),
                        const SizedBox(width: 24),
                        _DesktopNavLink(
                          icon: Icons.workspace_premium_outlined,
                          label: 'Fidelidade & Pacotes',
                          active: widget.activeTab == OmniMainTab.fidelidade,
                          onTap: () => widget.onSelectTab(OmniMainTab.fidelidade),
                        ),
                        const SizedBox(width: 24),
                        _DesktopNavLink(
                          icon: Icons.code_rounded,
                          label: 'Contrato & Código Dart',
                          active: widget.activeTab == OmniMainTab.codigo,
                          onTap: () => widget.onSelectTab(OmniMainTab.codigo),
                        ),
                      ],
                    ),
                  ],

                  // Zona 3: Status RTDB + Perfil Editável + Layout Toggle
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => _abrirModalPerfil(context),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: OmniConstants.darkBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_outline_rounded, size: 15, color: OmniConstants.neonCyan),
                              const SizedBox(width: 5),
                              Text(
                                appState.passageiro.nome.split(' ').first,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isVeryWide) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: OmniConstants.darkBorderSubtle),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _PulsingDot(color: conectado ? OmniConstants.neonCyan : OmniConstants.amberWarning),
                              const SizedBox(width: 6),
                              Text(
                                conectado ? 'RTDB Online' : 'Modo Local',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: OmniConstants.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (isTabletOrWide && widget.onToggleLayout != null) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: widget.onToggleLayout,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: OmniConstants.darkBorderSubtle),
                            ),
                            child: Icon(
                              widget.isExpandedLayout ? Icons.smartphone_rounded : Icons.laptop_mac_rounded,
                              size: 16,
                              color: OmniConstants.neonCyan,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
                  const SizedBox(height: 10),
                  // Campo flexível de Domínio / IP + Botão Salvar em Cache (padrão 192.168.12.10)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dominioController,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          enableSuggestions: false,
                          onSubmitted: (_) => _salvarDominio(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: OmniConstants.darkBackground,
                            hintText: 'Ex: 192.168.12.10 ou dominio.com.br',
                            hintStyle: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: OmniConstants.textDim,
                            ),
                            prefixIcon: const Icon(
                              Icons.dns_rounded,
                              size: 16,
                              color: OmniConstants.neonCyan,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: OmniConstants.neonCyan.withValues(alpha: 0.35)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: OmniConstants.neonCyan.withValues(alpha: 0.35)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: OmniConstants.neonCyan, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _salvandoDominio ? null : _salvarDominio,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _dominioSalvoRecente
                              ? OmniConstants.emeraldSuccess
                              : OmniConstants.darkCard,
                          foregroundColor: _dominioSalvoRecente ? Colors.black : OmniConstants.neonCyan,
                          minimumSize: const Size(86, 42),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: _dominioSalvoRecente
                                  ? OmniConstants.emeraldSuccess
                                  : OmniConstants.neonCyan.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        icon: Icon(
                          _dominioSalvoRecente ? Icons.check_rounded : Icons.save_rounded,
                          size: 16,
                        ),
                        label: Text(
                          _dominioSalvoRecente ? 'Salvo' : 'Salvar',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: OmniConstants.neonCyan.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _testandoComunicacao ? null : _executarTesteComunicacao,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OmniConstants.neonCyan,
                        disabledBackgroundColor: OmniConstants.neonCyan.withValues(alpha: 0.65),
                        foregroundColor: Colors.black,
                        disabledForegroundColor: Colors.black87,
                        minimumSize: const Size(double.infinity, 44),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _testandoComunicacao
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                              ),
                            )
                          : const Icon(Icons.wifi_tethering_rounded, size: 17, color: Colors.black),
                      label: Text(
                        _testandoComunicacao
                            ? 'TESTANDO HTTP E HTTPS...'
                            : 'TESTAR COMUNICAÇÃO (HTTP + HTTPS · ${appState.backendDominio})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
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

class _DesktopNavLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _DesktopNavLink({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? OmniConstants.neonCyan : OmniConstants.textMuted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_controller),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: widget.color.withValues(alpha: 0.7), blurRadius: 6),
          ],
        ),
      ),
    );
  }
}
