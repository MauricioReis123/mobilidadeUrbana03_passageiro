import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/omni_constants.dart';
import '../tools/mapas_service.dart';

/// Campo de Endereço com Autocomplete em Tempo Real ordenado por proximidade GPS
/// Reutilizável em Origem, Paradas Intermediárias e Destino (sem overflow em telas Android)
class OmniAddressAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final double latReferencia;
  final double lngReferencia;
  final ValueChanged<OmniCoordenada> onSelectCoordenada;
  final VoidCallback? onChangedTexto;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;
  final bool autofocus;
  final Color dotColor;
  final bool isSquare;

  const OmniAddressAutocompleteField({
    super.key,
    required this.controller,
    required this.hint,
    required this.latReferencia,
    required this.lngReferencia,
    required this.onSelectCoordenada,
    this.onChangedTexto,
    this.onSubmitted,
    this.trailing,
    this.autofocus = false,
    this.dotColor = OmniConstants.neonCyan,
    this.isSquare = false,
  });

  @override
  State<OmniAddressAutocompleteField> createState() => _OmniAddressAutocompleteFieldState();
}

class _OmniAddressAutocompleteFieldState extends State<OmniAddressAutocompleteField> {
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  bool _loading = false;
  bool _buscaRealizada = false;
  bool _tocandoSugestao = false;
  String? _sessionToken;
  int _buscaSeq = 0;
  List<OmniEnderecoSugestao> _sugestoes = const [];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (_focusNode.hasFocus) {
      setState(() {});
      final q = widget.controller.text.trim();
      if (q.length >= 2 && _sugestoes.isEmpty && !_loading) {
        _dispararBusca(q, imediato: false);
      }
    } else {
      Future.delayed(const Duration(milliseconds: 260), () {
        if (mounted && !_focusNode.hasFocus && !_tocandoSugestao) {
          setState(() {
            _sugestoes = const [];
            _buscaRealizada = false;
          });
        }
      });
    }
  }

  void _dispararBusca(String q, {bool imediato = false}) {
    _debounce?.cancel();
    if (q.length < 2) {
      if (_loading || _buscaRealizada || _sugestoes.isNotEmpty) {
        setState(() {
          _loading = false;
          _buscaRealizada = false;
          _sugestoes = const [];
        });
      }
      return;
    }

    _sessionToken ??= 'omni_${DateTime.now().millisecondsSinceEpoch}';
    final seqAtual = ++_buscaSeq;
    if (!_loading) {
      setState(() => _loading = true);
    }

    Future<void> executar() async {
      final res = await OmniMapasService.buscarEnderecosProximos(
        query: q,
        latReferencia: widget.latReferencia,
        lngReferencia: widget.lngReferencia,
        sessionToken: _sessionToken,
      );
      if (!mounted || seqAtual != _buscaSeq) return;
      setState(() {
        _loading = false;
        _buscaRealizada = true;
        _sugestoes = _focusNode.hasFocus ? res : const [];
      });
    }

    if (imediato) {
      executar();
    } else {
      _debounce = Timer(const Duration(milliseconds: 300), executar);
    }
  }

  void _onTextChanged(String valor) {
    widget.onChangedTexto?.call();
    _dispararBusca(valor.trim());
  }

  Future<void> _selecionarSugestao(OmniEnderecoSugestao sug) async {
    _tocandoSugestao = true;
    _debounce?.cancel();
    _buscaSeq++;
    final tokenUsado = _sessionToken;
    _sessionToken = null;

    setState(() {
      _loading = false;
      _buscaRealizada = false;
      _sugestoes = const [];
      widget.controller.value = TextEditingValue(
        text: sug.enderecoCompleto,
        selection: TextSelection.collapsed(offset: sug.enderecoCompleto.length),
      );
    });
    _focusNode.unfocus();

    final coord = await OmniMapasService.obterDetalhesLugar(
      sugestao: sug,
      fallbackLat: widget.latReferencia,
      fallbackLng: widget.lngReferencia,
      sessionToken: tokenUsado,
    );
    _tocandoSugestao = false;
    if (!mounted) return;
    if (coord.endereco != null && coord.endereco!.isNotEmpty) {
      widget.controller.value = TextEditingValue(
        text: coord.endereco!,
        selection: TextSelection.collapsed(offset: coord.endereco!.length),
      );
    }
    widget.onSelectCoordenada(coord);
    widget.onChangedTexto?.call();
  }

  IconData _iconePorTipo(String tipoIcone) {
    switch (tipoIcone) {
      case 'airport':
        return Icons.flight_takeoff_rounded;
      case 'transit':
        return Icons.directions_transit_rounded;
      case 'shopping':
        return Icons.shopping_bag_rounded;
      case 'hospital':
        return Icons.local_hospital_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      case 'hotel':
        return Icons.hotel_rounded;
      case 'park':
        return Icons.park_rounded;
      case 'fuel':
        return Icons.local_gas_station_rounded;
      case 'school':
        return Icons.school_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool mostrarLista =
        _focusNode.hasFocus && (_loading || _sugestoes.isNotEmpty || _buscaRealizada);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: widget.dotColor,
                shape: widget.isSquare ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: widget.isSquare ? BorderRadius.circular(2.5) : null,
                boxShadow: [
                  BoxShadow(
                    color: widget.dotColor.withValues(alpha: 0.65),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              key: const ValueKey('omni_ac_input_expanded'),
              child: TextField(
                key: ObjectKey(widget.controller),
                controller: widget.controller,
                focusNode: _focusNode,
                autofocus: widget.autofocus,
                textInputAction: TextInputAction.search,
                onChanged: _onTextChanged,
                onSubmitted: widget.onSubmitted,
                style: const TextStyle(fontSize: 13.5, color: OmniConstants.textPrimary),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: const TextStyle(fontSize: 13, color: OmniConstants.textDim),
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
            KeyedSubtree(
              key: const ValueKey('omni_ac_status_slot'),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: OmniConstants.neonCyan,
                        ),
                      ),
                    )
                  : (_focusNode.hasFocus && widget.controller.text.isNotEmpty)
                      ? IconButton(
                          icon: const Icon(Icons.cancel_rounded, size: 16, color: OmniConstants.textDim),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          onPressed: () {
                            widget.controller.clear();
                            _onTextChanged('');
                            _focusNode.requestFocus();
                          },
                        )
                      : const SizedBox.shrink(),
            ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
        if (mostrarLista)
          Container(
            key: const ValueKey('omni_ac_dropdown_container'),
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 230),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: OmniConstants.neonCyan.withValues(alpha: 0.4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: const BoxDecoration(
                    color: OmniConstants.darkSurface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
                    border: Border(bottom: BorderSide(color: OmniConstants.darkBorderSubtle)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.near_me_rounded, size: 12, color: OmniConstants.neonCyan),
                          SizedBox(width: 5),
                          Text(
                            'MAIS PRÓXIMOS DE VOCÊ',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                              color: OmniConstants.neonCyan,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _loading ? 'Buscando...' : '${_sugestoes.length} locais',
                        style: const TextStyle(fontSize: 10, color: OmniConstants.textMuted),
                      ),
                    ],
                  ),
                ),
                if (_loading && _sugestoes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: OmniConstants.neonCyan),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Localizando endereços próximos...',
                            style: TextStyle(fontSize: 12, color: OmniConstants.textMuted),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_sugestoes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Nenhum endereço próximo encontrado. Tente incluir bairro ou cidade.',
                      style: TextStyle(fontSize: 11.5, color: OmniConstants.textMuted),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      key: const ValueKey('omni_ac_results_list'),
                      primary: false,
                      shrinkWrap: true,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                      padding: EdgeInsets.zero,
                      itemCount: _sugestoes.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: OmniConstants.darkBorderSubtle,
                      ),
                      itemBuilder: (_, idx) {
                        final sug = _sugestoes[idx];
                        final distLabel = OmniMapasService.formatarDistanciaProximidade(sug.distanciaKm);
                        final isMaisProximo = idx == 0;
                        return KeyedSubtree(
                          key: ValueKey('sug_${sug.id}_$idx'),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTapDown: (_) => _tocandoSugestao = true,
                              onTapCancel: () => _tocandoSugestao = false,
                              onTap: () => _selecionarSugestao(sug),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              child: Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: isMaisProximo
                                          ? OmniConstants.neonCyan.withValues(alpha: 0.14)
                                          : Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isMaisProximo
                                            ? OmniConstants.neonCyan.withValues(alpha: 0.45)
                                            : OmniConstants.darkBorder,
                                      ),
                                    ),
                                    child: Icon(
                                      _iconePorTipo(sug.tipoIcone),
                                      size: 16,
                                      color: OmniConstants.neonCyan,
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                sug.titulo,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                            if (isMaisProximo && distLabel != null) ...[
                                              const SizedBox(width: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: OmniConstants.emeraldSuccess.withValues(alpha: 0.16),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'Mais próximo',
                                                  style: TextStyle(
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFF34D399),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (sug.subtitulo.isNotEmpty)
                                          Text(
                                            sug.subtitulo,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: OmniConstants.textMuted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (distLabel != null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: OmniConstants.neonCyan.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: OmniConstants.neonCyan.withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Text(
                                        distLabel,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: OmniConstants.neonCyan,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
