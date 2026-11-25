import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import '../config/omni_integration_contracts.dart';
import '../constants/omni_constants.dart';
import '../models/campanha_model.dart';
import '../theme/omni_theme.dart';
import '../tools/backends_service.dart';

/// Painel Administrativo Exclusivo do Dono (`ianzinhogb@gmail.com` + Chave Hash SHA-256)
/// Gerencia criação, agendamento, duplicação, cancelamento e disparo imediato FCM HTTP v1 + RTDB.
class AdminCampanhasPassageiroScreen extends StatefulWidget {
  final String? initialEmail;

  const AdminCampanhasPassageiroScreen({super.key, this.initialEmail});

  @override
  State<AdminCampanhasPassageiroScreen> createState() =>
      _AdminCampanhasPassageiroScreenState();
}

class _AdminCampanhasPassageiroScreenState
    extends State<AdminCampanhasPassageiroScreen> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _keyCtrl = TextEditingController();

  // Formulário de campanha
  final TextEditingController _tituloCtrl = TextEditingController();
  final TextEditingController _mensagemCtrl = TextEditingController();
  final TextEditingController _imagemUrlCtrl = TextEditingController();
  final TextEditingController _cupomCtrl = TextEditingController();
  final TextEditingController _descontoValorCtrl = TextEditingController(text: '15');
  final TextEditingController _cidadeCustomCtrl = TextEditingController();
  final TextEditingController _dataDisparoCtrl = TextEditingController();
  final TextEditingController _dataExpiracaoCtrl = TextEditingController();

  String _tipoDesconto = 'percentual';
  String _cidadeAlvo = 'todas';
  String _filtroStatus = '';
  bool _autenticado = false;
  bool _precisaVincularChave = false;
  bool _carregandoAuth = false;
  bool _salvando = false;
  bool _carregandoLista = false;
  String? _erroAuth;
  String _hashSessao = '';
  List<OmniCampanhaPassageiro> _campanhas = [];
  Map<String, dynamic>? _pushStatus;
  bool _disparandoTeste = false;

  @override
  void initState() {
    super.initState();
    final emailInit = (widget.initialEmail ?? '').trim();
    _emailCtrl.text =
        emailInit.isNotEmpty ? emailInit : OmniRtdbConfig.ownerEmail;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _keyCtrl.dispose();
    _tituloCtrl.dispose();
    _mensagemCtrl.dispose();
    _imagemUrlCtrl.dispose();
    _cupomCtrl.dispose();
    _descontoValorCtrl.dispose();
    _cidadeCustomCtrl.dispose();
    _dataDisparoCtrl.dispose();
    _dataExpiracaoCtrl.dispose();
    super.dispose();
  }

  String _computarHash(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(trimmed)) {
      return trimmed.toLowerCase();
    }
    return sha256.convert(utf8.encode(trimmed)).toString().toLowerCase();
  }

  Future<void> _autenticarDono({bool vincularInicial = false}) async {
    final email = _emailCtrl.text.trim().toLowerCase();
    final keyHash = _computarHash(_keyCtrl.text);

    if (email != OmniRtdbConfig.ownerEmail) {
      setState(() {
        _erroAuth = 'Acesso permitido exclusivamente para ${OmniRtdbConfig.ownerEmail}.';
      });
      return;
    }
    if (keyHash.isEmpty) {
      setState(() {
        _erroAuth = 'Informe sua chave secreta ou hash SHA-256 de proprietário.';
      });
      return;
    }

    setState(() {
      _carregandoAuth = true;
      _erroAuth = null;
    });

    try {
      final resp = await OmniBackendUniversal.executar(
        vincularInicial
            ? OmniBackendMethods.adminClaimOwnerKey
            : OmniBackendMethods.adminVerifyOwner,
        args: vincularInicial
            ? {'admin_email': email, 'new_key_hash': keyHash}
            : {'admin_email': email, 'admin_key_hash': keyHash},
      );

      if (!mounted) return;
      if (resp.sucesso) {
        setState(() {
          _autenticado = true;
          _precisaVincularChave = false;
          _hashSessao = keyHash;
        });
        await _carregarCampanhas();
      } else {
        final needsClaim = resp.codigoErro == 'OWNER_KEY_NOT_CONFIGURED' ||
            (resp.dados is Map && resp.dados['needs_initial_claim'] == true);
        setState(() {
          _precisaVincularChave = needsClaim;
          _erroAuth = resp.mensagem.isNotEmpty
              ? resp.mensagem
              : 'Falha na autenticação do proprietário.';
        });
      }
    } finally {
      if (mounted) setState(() => _carregandoAuth = false);
    }
  }

  Future<void> _carregarCampanhas() async {
    if (!_autenticado) return;
    setState(() => _carregandoLista = true);
    try {
      final emailNorm = _emailCtrl.text.trim().toLowerCase();
      final results = await Future.wait([
        OmniBackendUniversal.executar(
          OmniBackendMethods.adminCampaignList,
          args: {
            'admin_email': emailNorm,
            'admin_key_hash': _hashSessao,
            'status': _filtroStatus,
          },
        ),
        OmniBackendUniversal.executar(
          OmniBackendMethods.adminPushStatus,
          args: {
            'admin_email': emailNorm,
            'admin_key_hash': _hashSessao,
          },
        ),
      ]);
      final resp = results[0];
      final statusResp = results[1];
      if (!mounted) return;
      setState(() {
        if (resp.sucesso && resp.dados is List) {
          _campanhas = (resp.dados as List)
              .whereType<Map>()
              .map((m) => OmniCampanhaPassageiro.fromMap(
                    (m['campaign_id'] ?? m['id'] ?? '').toString(),
                    m,
                  ))
              .toList();
        }
        if (statusResp.sucesso && statusResp.dados is Map) {
          _pushStatus = Map<String, dynamic>.from(statusResp.dados as Map);
        }
      });
    } finally {
      if (mounted) setState(() => _carregandoLista = false);
    }
  }

  Future<void> _dispararPushTeste() async {
    if (!_autenticado || _disparandoTeste) return;
    setState(() => _disparandoTeste = true);
    try {
      final resp = await OmniBackendUniversal.executar(
        OmniBackendMethods.adminCampaignSave,
        args: {
          'admin_email': _emailCtrl.text.trim().toLowerCase(),
          'admin_key_hash': _hashSessao,
          'campaign': {
            'titulo': 'Teste Push OMNI ao Vivo',
            'mensagem': 'Notificação Heads-Up funcionando no topo da tela! Cupom TESTE10.',
            'codigo_cupom': 'TESTE10',
            'tipo_desconto': 'percentual',
            'percentual_desconto': 10.0,
            'cidade_alvo': 'todas',
            'disparar_agora': true,
          },
        },
      );
      if (!mounted) return;
      final warn = resp.dados is Map ? (resp.dados['fcm_warning'] ?? '').toString() : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resp.sucesso
                ? 'Push teste disparado!${warn.isNotEmpty ? ' (FCM: $warn)' : ''}'
                : 'Erro no teste: ${resp.mensagem}',
          ),
        ),
      );
      await _carregarCampanhas();
    } finally {
      if (mounted) setState(() => _disparandoTeste = false);
    }
  }

  void _aplicarPreset(String preset) {
    if (preset == 'pais') {
      _tituloCtrl.text = 'Feliz Dia dos Pais com a OMNI!';
      _mensagemCtrl.text =
          'Presente especial: use o cupom PAIS20 e ganhe 20% OFF na sua viagem hoje.';
      _cupomCtrl.text = 'PAIS20';
      _tipoDesconto = 'percentual';
      _descontoValorCtrl.text = '20';
    } else if (preset == 'festa') {
      _tituloCtrl.text = 'Festa Turística na Cidade!';
      _mensagemCtrl.text =
          'Chegue com conforto e segurança usando FESTA15 para 15% de desconto.';
      _cupomCtrl.text = 'FESTA15';
      _tipoDesconto = 'percentual';
      _descontoValorCtrl.text = '15';
    } else if (preset == 'fixo10') {
      _tituloCtrl.text = 'R\$ 10 OFF na sua próxima corrida!';
      _mensagemCtrl.text =
          'Ative o cupom OMNI10R e garanta R\$ 10,00 de abatimento imediato.';
      _cupomCtrl.text = 'OMNI10R';
      _tipoDesconto = 'valor_fixo';
      _descontoValorCtrl.text = '10';
    }
    setState(() {});
  }

  Future<void> _selecionarDataHora(TextEditingController target) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    target.text = dt.toUtc().toIso8601String();
  }

  Future<void> _salvarOuDispararCampanha({required bool dispararAgora}) async {
    final titulo = _tituloCtrl.text.trim();
    final mensagem = _mensagemCtrl.text.trim();
    if (titulo.isEmpty || mensagem.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha título e mensagem da campanha.')),
      );
      return;
    }

    final valorNum = double.tryParse(_descontoValorCtrl.text.replaceAll(',', '.')) ?? 0.0;
    final cidadeFinal = _cidadeAlvo == 'custom'
        ? (_cidadeCustomCtrl.text.trim().isEmpty ? 'todas' : _cidadeCustomCtrl.text.trim())
        : _cidadeAlvo;

    setState(() => _salvando = true);
    try {
      final resp = await OmniBackendUniversal.executar(
        OmniBackendMethods.adminCampaignSave,
        args: {
          'admin_email': _emailCtrl.text.trim().toLowerCase(),
          'admin_key_hash': _hashSessao,
          'campaign': {
            'titulo': titulo,
            'mensagem': mensagem,
            'imagem_url': _imagemUrlCtrl.text.trim(),
            'codigo_cupom': _cupomCtrl.text.trim().toUpperCase(),
            'tipo_desconto': _tipoDesconto,
            'percentual_desconto': _tipoDesconto == 'percentual' ? valorNum : 0.0,
            'valor_fixo': _tipoDesconto == 'valor_fixo' ? valorNum : 0.0,
            'cidade_alvo': cidadeFinal,
            'data_hora_disparo': _dataDisparoCtrl.text.trim(),
            'data_hora_expiracao': _dataExpiracaoCtrl.text.trim(),
            'disparar_agora': dispararAgora,
          },
        },
      );

      if (!mounted) return;
      if (resp.sucesso) {
        String msg = resp.mensagem.isNotEmpty
            ? resp.mensagem
            : (dispararAgora ? 'Campanha disparada!' : 'Campanha agendada!');
        if (resp.dados is Map && (resp.dados['fcm_warning'] ?? '').toString().isNotEmpty) {
          msg = '$msg (Aviso FCM: ${resp.dados['fcm_warning']})';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        _tituloCtrl.clear();
        _mensagemCtrl.clear();
        _imagemUrlCtrl.clear();
        _cupomCtrl.clear();
        await _carregarCampanhas();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: ${resp.mensagem}')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _acaoCampanha(String method, String campaignId) async {
    final resp = await OmniBackendUniversal.executar(
      method,
      args: {
        'admin_email': _emailCtrl.text.trim().toLowerCase(),
        'admin_key_hash': _hashSessao,
        'campaign_id': campaignId,
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resp.mensagem.isNotEmpty ? resp.mensagem : 'Ação executada.')),
    );
    await _carregarCampanhas();
  }

  Future<void> _processarFilaAgendada() async {
    final resp = await OmniBackendUniversal.executar(
      OmniBackendMethods.campaignsProcessScheduled,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(resp.mensagem.isNotEmpty ? resp.mensagem : 'Fila processada.')),
    );
    await _carregarCampanhas();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OmniConstants.darkBackground,
      appBar: AppBar(
        title: const Text(
          'Campanhas & Push (Dono)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_autenticado)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: OmniConstants.neonCyan),
              onPressed: _carregarCampanhas,
              tooltip: 'Recarregar campanhas',
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _autenticado ? _buildPainelAdmin() : _buildGateAutenticacao(),
        ),
      ),
    );
  }

  Widget _buildGateAutenticacao() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: OmniTheme.cardDecoration(
        backgroundColor: OmniConstants.darkCard,
        borderColor: OmniConstants.darkBorder,
        borderRadius: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: OmniConstants.neonCyan.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.admin_panel_settings_rounded, color: OmniConstants.neonCyan),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Acesso Exclusivo do Dono',
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    Text(
                      'Validado via e-mail oficial + chave hash SHA-256 no PHP.',
                      style: TextStyle(fontSize: 11.5, color: OmniConstants.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'E-mail do Proprietário',
              hintText: OmniRtdbConfig.ownerEmail,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            obscureText: true,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Chave Secreta ou Hash SHA-256',
              hintText: 'Digite sua chave configurada no backend PHP',
            ),
          ),
          if (_erroAuth != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: OmniConstants.rubyRedAlert.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: OmniConstants.rubyRedAlert.withValues(alpha: 0.45)),
              ),
              child: Text(
                _erroAuth!,
                style: const TextStyle(fontSize: 11.5, color: Color(0xFFFCA5A5)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _carregandoAuth ? null : () => _autenticarDono(vincularInicial: false),
            style: ElevatedButton.styleFrom(
              backgroundColor: OmniConstants.neonCyan,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: _carregandoAuth
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.lock_open_rounded),
            label: Text(
              _carregandoAuth ? 'VALIDANDO...' : 'ENTRAR NO MOTOR DE CAMPANHAS',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
            ),
          ),
          if (_precisaVincularChave) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _carregandoAuth ? null : () => _autenticarDono(vincularInicial: true),
              style: OutlinedButton.styleFrom(
                foregroundColor: OmniConstants.goldAccent,
                side: const BorderSide(color: OmniConstants.goldAccent),
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.vpn_key_rounded, size: 18),
              label: const Text(
                'CONFIGURAR ESTA CHAVE COMO DONO INICIAL',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPainelAdmin() {
    final saFound = _pushStatus?['service_account_found'] == true;
    final oauthOk = _pushStatus?['oauth_token_ok'] == true;
    final sqlTokens = (_pushStatus?['sql_tokens_count'] as num?)?.toInt() ?? 0;
    final rtdbTokens = (_pushStatus?['rtdb_tokens_count'] as num?)?.toInt() ?? 0;
    final totalTokens = sqlTokens > rtdbTokens ? sqlTokens : rtdbTokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_pushStatus != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: OmniTheme.cardDecoration(
              backgroundColor: OmniConstants.darkCard,
              borderColor: (saFound && oauthOk)
                  ? OmniConstants.emeraldSuccess.withValues(alpha: 0.45)
                  : OmniConstants.amberWarning.withValues(alpha: 0.45),
              borderRadius: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      (saFound && oauthOk)
                          ? Icons.verified_rounded
                          : Icons.warning_amber_rounded,
                      color: (saFound && oauthOk)
                          ? const Color(0xFF34D399)
                          : OmniConstants.amberWarning,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (saFound && oauthOk)
                            ? 'FCM HTTP v1 Ativo · RTDB em Tempo Real'
                            : 'RTDB Ao Vivo · Pendente firebase-service-account.json',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Tokens registrados: $totalTokens (SQL: $sqlTokens / RTDB: $rtdbTokens)',
                  style: const TextStyle(fontSize: 11, color: OmniConstants.textSecondary),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _dispararPushTeste,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: OmniConstants.neonCyan,
                      side: const BorderSide(color: OmniConstants.neonCyan),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _disparandoTeste
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: OmniConstants.neonCyan),
                          )
                        : const Icon(Icons.notifications_active_rounded, size: 16),
                    label: Text(
                      _disparandoTeste ? 'DISPARANDO...' : 'DISPARAR PUSH TESTE',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        // 1. Presets rápidos sazonais e turísticos
        const Text(
          'MODELOS PRONTOS (SAZONAIS / TURÍSTICOS)',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: OmniConstants.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: const Text('Dia dos Pais (PAIS20)'),
              onPressed: () => _aplicarPreset('pais'),
              backgroundColor: OmniConstants.darkCard,
              labelStyle: const TextStyle(fontSize: 11.5, color: OmniConstants.neonCyan),
            ),
            ActionChip(
              label: const Text('Festa Turística (FESTA15)'),
              onPressed: () => _aplicarPreset('festa'),
              backgroundColor: OmniConstants.darkCard,
              labelStyle: const TextStyle(fontSize: 11.5, color: OmniConstants.goldAccent),
            ),
            ActionChip(
              label: const Text('R\$ 10 OFF (OMNI10R)'),
              onPressed: () => _aplicarPreset('fixo10'),
              backgroundColor: OmniConstants.darkCard,
              labelStyle: const TextStyle(fontSize: 11.5, color: Color(0xFF34D399)),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 2. Formulário de Nova Campanha
        Container(
          padding: const EdgeInsets.all(16),
          decoration: OmniTheme.cardDecoration(
            backgroundColor: OmniConstants.darkCard,
            borderColor: OmniConstants.darkBorder,
            borderRadius: 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Nova Campanha Promocional',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tituloCtrl,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: const InputDecoration(labelText: 'Título da Notificação'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _mensagemCtrl,
                maxLines: 2,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: const InputDecoration(labelText: 'Mensagem Promocional'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cupomCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Código do Cupom'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _descontoValorCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        labelText: _tipoDesconto == 'percentual' ? '% Desconto' : 'R\$ Fixo',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'percentual', label: Text('Percentual (%)')),
                  ButtonSegment(value: 'valor_fixo', label: Text('Valor Fixo (R\$)')),
                ],
                selected: {_tipoDesconto},
                onSelectionChanged: (s) => setState(() => _tipoDesconto = s.first),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _cidadeAlvo,
                dropdownColor: OmniConstants.darkCard,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: const InputDecoration(labelText: 'Público / Cidade Alvo'),
                items: const [
                  DropdownMenuItem(value: 'todas', child: Text('Todas as Cidades (perfil_passageiro)')),
                  DropdownMenuItem(value: 'Camboriú', child: Text('Camboriú (passageiro_cidade_camboriu)')),
                  DropdownMenuItem(
                    value: 'Balneário Camboriú',
                    child: Text('Balneário Camboriú (passageiro_cidade_balneario_camboriu)'),
                  ),
                  DropdownMenuItem(value: 'Itajaí', child: Text('Itajaí (passageiro_cidade_itajai)')),
                  DropdownMenuItem(value: 'custom', child: Text('Outra cidade personalizada...')),
                ],
                onChanged: (v) => setState(() => _cidadeAlvo = v ?? 'todas'),
              ),
              if (_cidadeAlvo == 'custom') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _cidadeCustomCtrl,
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Nome exato da cidade'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _imagemUrlCtrl,
                keyboardType: TextInputType.url,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'URL da Imagem (opcional, https://...)',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dataDisparoCtrl,
                      style: const TextStyle(fontSize: 11.5, color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Disparo Agendado (UTC)',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.event_rounded, size: 18, color: OmniConstants.neonCyan),
                          onPressed: () => _selecionarDataHora(_dataDisparoCtrl),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _dataExpiracaoCtrl,
                      style: const TextStyle(fontSize: 11.5, color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Expiração (UTC)',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.timer_off_outlined, size: 18, color: OmniConstants.goldAccent),
                          onPressed: () => _selecionarDataHora(_dataExpiracaoCtrl),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _salvando
                          ? null
                          : () => _salvarOuDispararCampanha(dispararAgora: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: OmniConstants.neonCyan,
                        side: const BorderSide(color: OmniConstants.neonCyan),
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.schedule_send_rounded, size: 17),
                      label: const Text('AGENDAR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _salvando
                          ? null
                          : () => _salvarOuDispararCampanha(dispararAgora: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OmniConstants.neonCyan,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.campaign_rounded, size: 18),
                      label: const Text('DISPARAR AGORA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Fila e Listagem de Campanhas
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'CAMPANHAS CADASTRADAS',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: OmniConstants.textMuted,
              ),
            ),
            TextButton.icon(
              onPressed: _processarFilaAgendada,
              icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
              label: const Text('Processar Fila (Cron)', style: TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          children: [
            _StatusFilterChip(
              label: 'Todas',
              selected: _filtroStatus == '',
              onTap: () {
                setState(() => _filtroStatus = '');
                _carregarCampanhas();
              },
            ),
            _StatusFilterChip(
              label: 'Agendadas',
              selected: _filtroStatus == 'agendada',
              onTap: () {
                setState(() => _filtroStatus = 'agendada');
                _carregarCampanhas();
              },
            ),
            _StatusFilterChip(
              label: 'Enviadas',
              selected: _filtroStatus == 'enviada',
              onTap: () {
                setState(() => _filtroStatus = 'enviada');
                _carregarCampanhas();
              },
            ),
            _StatusFilterChip(
              label: 'Canceladas',
              selected: _filtroStatus == 'cancelada',
              onTap: () {
                setState(() => _filtroStatus = 'cancelada');
                _carregarCampanhas();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_carregandoLista)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: OmniConstants.neonCyan),
            ),
          )
        else if (_campanhas.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: OmniConstants.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OmniConstants.darkBorder),
            ),
            child: const Text(
              'Nenhuma campanha cadastrada ainda para este filtro.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: OmniConstants.textMuted),
            ),
          )
        else
          ..._campanhas.map((c) {
            final corStatus = c.status == 'enviada'
                ? const Color(0xFF34D399)
                : (c.status == 'cancelada' ? OmniConstants.rubyRedAlert : OmniConstants.goldAccent);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
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
                    children: [
                      Expanded(
                        child: Text(
                          c.titulo,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: corStatus.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          c.status.toUpperCase(),
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: corStatus),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.mensagem,
                    style: const TextStyle(fontSize: 12, color: OmniConstants.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Cupom: ${c.codigoCupom.isEmpty ? "—" : c.codigoCupom} (${c.resumoDesconto}) · Cidade: ${c.cidadeAlvo}',
                    style: const TextStyle(fontSize: 11, color: OmniConstants.neonCyan),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (c.status != 'cancelada')
                        OutlinedButton(
                          onPressed: () => _acaoCampanha(OmniBackendMethods.adminCampaignDispatchNow, c.id),
                          child: const Text('Disparar Agora', style: TextStyle(fontSize: 11)),
                        ),
                      OutlinedButton(
                        onPressed: () => _acaoCampanha(OmniBackendMethods.adminCampaignDuplicate, c.id),
                        child: const Text('Duplicar', style: TextStyle(fontSize: 11)),
                      ),
                      if (c.status != 'cancelada')
                        OutlinedButton(
                          onPressed: () => _acaoCampanha(OmniBackendMethods.adminCampaignCancel, c.id),
                          style: OutlinedButton.styleFrom(foregroundColor: OmniConstants.rubyRedAlert),
                          child: const Text('Cancelar', style: TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StatusFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: OmniConstants.neonCyan,
      backgroundColor: OmniConstants.darkCard,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: selected ? Colors.black : OmniConstants.textSecondary,
      ),
    );
  }
}
