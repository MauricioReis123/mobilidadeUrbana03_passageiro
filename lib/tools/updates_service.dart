import '../config/omni_integration_contracts.dart';
import 'backends_service.dart';
import '../constants/omni_constants.dart';

/// Informações de Atualização do App
class OmniAppUpdateInfo {
  final bool atualizacaoDisponivel;
  final bool obrigatoria;
  final String versaoRemota;
  final String urlDownload;
  final List<String> novidades;

  OmniAppUpdateInfo({
    required this.atualizacaoDisponivel,
    required this.obrigatoria,
    required this.versaoRemota,
    required this.urlDownload,
    required this.novidades,
  });
}

/// Serviço de Verificação de Versão e Atualizações OMNI
class OmniUpdatesService {
  static Future<OmniAppUpdateInfo> verificarAtualizacoes() async {
    final response = await OmniBackendUniversal.executar(
      OmniBackendMethods.systemCheckVersion,
      args: {
        'plataforma': 'android',
        'versao_instalada': OmniConstants.appVersion,
      },
    );

    if (response.sucesso && response.dados != null) {
      final d = response.dados;
      return OmniAppUpdateInfo(
        atualizacaoDisponivel: d['atualizacao_disponivel'] ?? false,
        obrigatoria: d['obrigatoria'] ?? false,
        versaoRemota: d['versao_remota'] ?? OmniConstants.appVersion,
        urlDownload: d['url_download'] ?? '',
        novidades: List<String>.from(d['novidades'] ?? []),
      );
    }

    return OmniAppUpdateInfo(
      atualizacaoDisponivel: false,
      obrigatoria: false,
      versaoRemota: OmniConstants.appVersion,
      urlDownload: '',
      novidades: [],
    );
  }
}
