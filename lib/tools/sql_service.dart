import '../config/omni_integration_contracts.dart';
import 'backends_service.dart';

/// Serviço de Acesso a Dados Persistidos (SQL via Backend PHP `class_omni_passageiro_backend_pro`)
class OmniSqlService {
  /// Busca histórico de corridas do passageiro persistido em `omni_corridas`
  static Future<List<Map<String, dynamic>>> obterHistoricoCorridas(String passageiroId) async {
    final response = await OmniBackendUniversal.executar(
      OmniBackendMethods.tripsHistory,
      args: {'passageiro_id': passageiroId},
    );

    if (response.sucesso && response.dados is List) {
      return List<Map<String, dynamic>>.from(response.dados as List);
    }
    return [];
  }

  /// Salva preferências de locais favoritos em `omni_passageiro_favoritos`
  static Future<bool> salvarLocalFavorito({
    required String passageiroId,
    required String rotulo,
    required String endereco,
    required double lat,
    required double lng,
  }) async {
    final response = await OmniBackendUniversal.executar(
      OmniBackendMethods.favoriteSave,
      args: {
        'passageiro_id': passageiroId,
        'rotulo': rotulo,
        'endereco': endereco,
        'lat': lat,
        'lng': lng,
      },
    );
    return response.sucesso;
  }

  /// Lê dados públicos do motorista e veículo ativo (`omni_motoristas` + `omni_veiculos`)
  static Future<Map<String, dynamic>?> obterDadosPublicosMotorista(String driverId) async {
    final response = await OmniBackendUniversal.executar(
      OmniBackendMethods.getDriverPublicInfo,
      args: {'driver_id': driverId},
    );
    if (response.sucesso && response.dados is Map) {
      return Map<String, dynamic>.from(response.dados as Map);
    }
    return null;
  }
}
