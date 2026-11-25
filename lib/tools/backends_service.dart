import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/omni_integration_contracts.dart';
import '../constants/omni_constants.dart';
import 'local_http_overrides.dart';

/// Registro individual de cada tentativa (HTTP ou HTTPS) na comunicação híbrida
class OmniTentativaComunicacao {
  final String protocolo;
  final String url;
  final bool sucesso;
  final int statusCode;
  final int latenciaMs;
  final bool nonceObtido;
  final String mensagem;
  final dynamic dados;

  const OmniTentativaComunicacao({
    required this.protocolo,
    required this.url,
    required this.sucesso,
    required this.statusCode,
    required this.latenciaMs,
    this.nonceObtido = false,
    required this.mensagem,
    this.dados,
  });
}

/// Resultado padronizado de chamadas ao backend
class OmniBackendResponse {
  final bool sucesso;
  final String mensagem;
  final dynamic dados;
  final int statusCode;
  final String? codigoErro;
  final String? urlUtilizada;
  final List<OmniTentativaComunicacao> tentativas;

  OmniBackendResponse({
    required this.sucesso,
    required this.mensagem,
    this.dados,
    required this.statusCode,
    this.codigoErro,
    this.urlUtilizada,
    this.tentativas = const [],
  });

  factory OmniBackendResponse.fromJson(
    Map<String, dynamic> json,
    int statusCode, {
    String? urlUtilizada,
    List<OmniTentativaComunicacao> tentativas = const [],
  }) {
    final bool ok = json['success'] == true || json['sucesso'] == true || json['status'] == 'ok' || json['status'] == 'success';
    final dynamic rawData = json['data'] ?? json['dados'];
    String msg = (json['message'] ?? json['mensagem'] ?? json['error'] ?? '').toString();
    if (msg.isEmpty && rawData is Map && rawData['message'] != null) {
      msg = rawData['message'].toString();
    }
    return OmniBackendResponse(
      sucesso: ok,
      mensagem: msg,
      dados: rawData ?? json,
      statusCode: statusCode,
      codigoErro: (json['code'] ?? json['codigo_erro'] ?? json['error_code'])?.toString(),
      urlUtilizada: urlUtilizada,
      tentativas: tentativas,
    );
  }

  factory OmniBackendResponse.erro(
    String mensagem, {
    int statusCode = 500,
    String? codigoErro,
    String? urlUtilizada,
    List<OmniTentativaComunicacao> tentativas = const [],
  }) {
    return OmniBackendResponse(
      sucesso: false,
      mensagem: mensagem,
      statusCode: statusCode,
      codigoErro: codigoErro,
      urlUtilizada: urlUtilizada,
      tentativas: tentativas,
    );
  }
}

/// Serviço Centralizado de Comunicação Híbrida: Flutter <-> WordPress PHP
/// Integrado 100% ao roteador dinâmico `omni_global_dynamic_router` do functions.php:
///   1) GET  ?action=omni_get_router_nonce -> obtém e armazena em cache o nonce
///   2) POST action=omni_global_router + nonce + payload JSON:
///      { backend_file, class_name, target_method (snake_case), args }
///   3) Renovação automática de nonce em caso de HTTP 403 + fallback HTTP -> HTTPS.
class OmniBackendUniversal {
  static String get baseUrl => OmniRouterConfig.baseUrl;
  static String get dominioAtual => OmniRouterConfig.configuredInput;

  static String? _tokenAutenticacao;
  static String? _ultimaUrlFuncionando;
  static bool _overridesConfigurados = false;
  static bool _dominioCacheCarregado = false;
  static final Map<String, String> _nonceCache = {};

  static void _garantirOverridesLocais() {
    if (!_overridesConfigurados) {
      configurarHttpLocalOverrides();
      _overridesConfigurados = true;
    }
  }

  /// Carrega do cache local (SharedPreferences) o domínio/IP salvo pelo usuário
  static Future<String> carregarDominioDoCache() async {
    if (!_dominioCacheCarregado) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString(OmniRouterConfig.cacheStorageKey);
        if (saved != null && saved.trim().isNotEmpty) {
          OmniRouterConfig.setConfiguredDomain(saved);
        }
      } catch (_) {}
      _dominioCacheCarregado = true;
      configurarHttpLocalOverrides();
      _overridesConfigurados = true;
    }
    return OmniRouterConfig.configuredInput;
  }

  /// Salva o novo domínio/IP no cache (SharedPreferences) e limpa caches antigos de nonce/URL
  static Future<String> salvarDominioEmCache(String rawValue) async {
    final normalized = OmniRouterConfig.normalizeInput(rawValue);
    OmniRouterConfig.setConfiguredDomain(normalized);
    _dominioCacheCarregado = true;
    _nonceCache.clear();
    _ultimaUrlFuncionando = null;
    configurarHttpLocalOverrides();
    _overridesConfigurados = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(OmniRouterConfig.cacheStorageKey, normalized);
    } catch (_) {}
    return normalized;
  }

  static void setToken(String token) {
    _tokenAutenticacao = token;
  }

  static void limparSessao() {
    _tokenAutenticacao = null;
    _nonceCache.clear();
  }

  static String? get ultimaUrlFuncionando => _ultimaUrlFuncionando;

  /// Obtém e guarda em cache o nonce do roteador (`omni_get_router_nonce`)
  static Future<String> _obterNonce(
    http.Client client,
    String targetUrl, {
    bool forcarRenovacao = false,
    int timeoutSegundos = OmniRouterConfig.timeoutSeconds,
  }) async {
    if (!forcarRenovacao && _nonceCache.containsKey(targetUrl)) {
      return _nonceCache[targetUrl]!;
    }

    final uri = Uri.parse('$targetUrl?action=${OmniRouterConfig.actionGetNonce}');
    final resp = await client.get(
      uri,
      headers: const {'Accept': 'application/json'},
    ).timeout(Duration(seconds: timeoutSegundos));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Falha ao obter nonce (HTTP ${resp.statusCode})');
    }

    final decoded = jsonDecode(resp.body);
    String? nonce;
    if (decoded is Map<String, dynamic>) {
      if (decoded['data'] is Map && decoded['data']['nonce'] != null) {
        nonce = decoded['data']['nonce'].toString();
      } else if (decoded['nonce'] != null) {
        nonce = decoded['nonce'].toString();
      }
    }

    if (nonce == null || nonce.isEmpty) {
      throw Exception('Nonce ausente na resposta de omni_get_router_nonce');
    }

    _nonceCache[targetUrl] = nonce;
    return nonce;
  }

  /// Executa a chamada completa (Nonce + POST omni_global_router) em uma URL específica
  static Future<OmniTentativaComunicacao> _executarNaUrl(
    String url,
    String targetMethod, {
    Map<String, dynamic>? args,
    String backendFile = OmniRouterConfig.backendFile,
    String className = OmniRouterConfig.className,
    String? chaveIdempotencia,
    int timeoutSegundos = OmniRouterConfig.timeoutSeconds,
  }) async {
    _garantirOverridesLocais();
    final protocolo = url.toLowerCase().startsWith('https://') ? 'HTTPS' : 'HTTP';
    final sw = Stopwatch()..start();
    final client = http.Client();
    bool nonceObtido = false;

    Future<http.Response> enviarPost(String nonce) {
      final uri = Uri.parse(url);
      final payloadJson = jsonEncode({
        'backend_file': backendFile,
        'class_name': className,
        'target_method': targetMethod.toLowerCase(),
        'args': args ?? <String, dynamic>{},
      });

      final corpoEnvio = <String, String>{
        'action': OmniRouterConfig.actionGlobalRouter,
        'nonce': nonce,
        'payload': payloadJson,
      };

      final headers = <String, String>{
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        if (_tokenAutenticacao != null) 'Authorization': 'Bearer $_tokenAutenticacao',
        if (chaveIdempotencia != null) 'X-Idempotency-Key': chaveIdempotencia,
      };

      final encodedBody = Uri(queryParameters: corpoEnvio).query;
      return client
          .post(uri, body: encodedBody, headers: headers, encoding: utf8)
          .timeout(Duration(seconds: timeoutSegundos));
    }

    try {
      String nonce = await _obterNonce(client, url, timeoutSegundos: timeoutSegundos);
      nonceObtido = true;

      http.Response response = await enviarPost(nonce);

      // Se o nonce expirou (HTTP 403), renova automaticamente uma vez e reenvia
      if (response.statusCode == 403) {
        _nonceCache.remove(url);
        nonce = await _obterNonce(client, url, forcarRenovacao: true, timeoutSegundos: timeoutSegundos);
        response = await enviarPost(nonce);
      }

      sw.stop();
      final bodyText = response.body.trim();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (bodyText.isEmpty) {
          return OmniTentativaComunicacao(
            protocolo: protocolo,
            url: url,
            sucesso: true,
            statusCode: response.statusCode,
            latenciaMs: sw.elapsedMilliseconds,
            nonceObtido: nonceObtido,
            mensagem: 'Servidor alcançado via $protocolo (HTTP ${response.statusCode}).',
          );
        }

        try {
          final decoded = jsonDecode(bodyText);
          if (decoded is Map<String, dynamic>) {
            final parsed = OmniBackendResponse.fromJson(decoded, response.statusCode, urlUtilizada: url);
            return OmniTentativaComunicacao(
              protocolo: protocolo,
              url: url,
              sucesso: parsed.sucesso,
              statusCode: response.statusCode,
              latenciaMs: sw.elapsedMilliseconds,
              nonceObtido: nonceObtido,
              mensagem: parsed.mensagem.isNotEmpty
                  ? parsed.mensagem
                  : 'Resposta JSON recebida via $protocolo (HTTP ${response.statusCode}).',
              dados: parsed.dados ?? decoded,
            );
          }
          return OmniTentativaComunicacao(
            protocolo: protocolo,
            url: url,
            sucesso: true,
            statusCode: response.statusCode,
            latenciaMs: sw.elapsedMilliseconds,
            nonceObtido: nonceObtido,
            mensagem: 'Resposta recebida via $protocolo (HTTP ${response.statusCode}).',
            dados: decoded,
          );
        } catch (_) {
          final preview = bodyText.length > 350 ? '${bodyText.substring(0, 350)}...' : bodyText;
          return OmniTentativaComunicacao(
            protocolo: protocolo,
            url: url,
            sucesso: true,
            statusCode: response.statusCode,
            latenciaMs: sw.elapsedMilliseconds,
            nonceObtido: nonceObtido,
            mensagem: 'Servidor alcançado via $protocolo (HTTP ${response.statusCode}, retorno texto/HTML).',
            dados: preview,
          );
        }
      }

      final previewErro = bodyText.length > 260 ? '${bodyText.substring(0, 260)}...' : bodyText;
      return OmniTentativaComunicacao(
        protocolo: protocolo,
        url: url,
        sucesso: false,
        statusCode: response.statusCode,
        latenciaMs: sw.elapsedMilliseconds,
        nonceObtido: nonceObtido,
        mensagem: 'Servidor respondeu HTTP ${response.statusCode} via $protocolo.',
        dados: previewErro.isEmpty ? null : previewErro,
      );
    } catch (e) {
      sw.stop();
      return OmniTentativaComunicacao(
        protocolo: protocolo,
        url: url,
        sucesso: false,
        statusCode: 0,
        latenciaMs: sw.elapsedMilliseconds,
        nonceObtido: nonceObtido,
        mensagem: 'Falha via $protocolo: ${e.toString()}',
      );
    } finally {
      client.close();
    }
  }

  /// Executa operações remotas via `omni_global_dynamic_router` em modo híbrido (HTTP -> HTTPS).
  /// Aceita `args` (padrão do roteador) ou `payload` (alias de compatibilidade).
  static Future<OmniBackendResponse> executar(
    String targetMethod, {
    Map<String, dynamic>? args,
    Map<String, dynamic>? payload,
    String backendFile = OmniRouterConfig.backendFile,
    String className = OmniRouterConfig.className,
    String? chaveIdempotencia,
    bool testarTodosOsProtocolos = false,
  }) async {
    await carregarDominioDoCache();
    final effectiveArgs = args ?? payload ?? <String, dynamic>{};
    final List<String> urlsOrdenadas = [];

    if (!testarTodosOsProtocolos && _ultimaUrlFuncionando != null) {
      urlsOrdenadas.add(_ultimaUrlFuncionando!);
    }
    for (final u in OmniRouterConfig.candidateUrls) {
      if (!urlsOrdenadas.contains(u)) {
        urlsOrdenadas.add(u);
      }
    }

    final List<OmniTentativaComunicacao> tentativas = [];
    OmniTentativaComunicacao? primeiraComSucesso;

    for (final url in urlsOrdenadas) {
      final tentativa = await _executarNaUrl(
        url,
        targetMethod,
        args: effectiveArgs,
        backendFile: backendFile,
        className: className,
        chaveIdempotencia: chaveIdempotencia,
      );
      tentativas.add(tentativa);

      if (tentativa.sucesso && primeiraComSucesso == null) {
        primeiraComSucesso = tentativa;
        _ultimaUrlFuncionando = url;
        if (!testarTodosOsProtocolos) {
          break;
        }
      }
    }

    if (primeiraComSucesso != null) {
      return OmniBackendResponse(
        sucesso: true,
        mensagem: primeiraComSucesso.mensagem,
        dados: primeiraComSucesso.dados,
        statusCode: primeiraComSucesso.statusCode,
        urlUtilizada: primeiraComSucesso.url,
        tentativas: tentativas,
      );
    }

    final ultima = tentativas.isNotEmpty ? tentativas.last : null;
    return OmniBackendResponse.erro(
      ultima?.mensagem ?? 'Não foi possível conectar ao servidor OMNI via HTTP nem HTTPS.',
      statusCode: ultima?.statusCode ?? 0,
      urlUtilizada: ultima?.url,
      tentativas: tentativas,
    );
  }

  /// Executa o teste diagnóstico completo (Nonce + POST omni_global_router) em HTTP e HTTPS
  static Future<OmniBackendResponse> testarComunicacaoHibrida({
    String targetMethod = OmniBackendMethods.systemPing,
    Map<String, dynamic>? args,
  }) {
    return executar(
      targetMethod,
      args: args ??
          {
            'origem': 'app_passageiro_flutter',
            'modo': 'hibrido_http_https',
            'app_version': OmniConstants.appVersion,
          },
      testarTodosOsProtocolos: true,
    );
  }
}
