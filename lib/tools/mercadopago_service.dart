import '../config/omni_integration_contracts.dart';
import 'backends_service.dart';

/// Modelo de Cobrança Pix OMNI
class OmniPixCobranca {
  final String idTransacao;
  final String qrCodeBase64;
  final String copiaECola;
  final double valor;
  final String status;
  final DateTime expiraEm;

  OmniPixCobranca({
    required this.idTransacao,
    required this.qrCodeBase64,
    required this.copiaECola,
    required this.valor,
    required this.status,
    required this.expiraEm,
  });

  factory OmniPixCobranca.fromJson(Map<String, dynamic> json) {
    return OmniPixCobranca(
      idTransacao: (json['id_transacao'] ?? json['payment_id'] ?? json['id'] ?? '').toString(),
      qrCodeBase64: (json['qr_code_base64'] ?? json['pix_qr_code_base64'] ?? '').toString(),
      copiaECola: (json['copia_e_cola'] ?? json['pix_copia_cola'] ?? json['qr_code'] ?? '').toString(),
      valor: (json['valor'] as num?)?.toDouble() ?? 0.0,
      status: (json['status'] ?? 'pending').toString(),
      expiraEm: json['expira_em'] != null
          ? DateTime.tryParse(json['expira_em'].toString()) ?? DateTime.now().add(const Duration(minutes: 15))
          : DateTime.now().add(const Duration(minutes: 15)),
    );
  }
}

/// Serviço de Pagamentos Mercado Pago Integrado ao OMNI Backend Seguro (PHP)
class OmniMercadoPagoService {
  /// Solicita geração de Pix via `passenger_wallet_generate_pix` (token privado no PHP)
  static Future<OmniPixCobranca?> gerarPixParaCorrida({
    required String rideId,
    required double valor,
    required String descricao,
    String cpf = '12345678909',
    String email = 'passageiro@omni.mobi',
    String passengerId = '',
  }) async {
    final response = await OmniBackendUniversal.executar(
      OmniBackendMethods.walletGeneratePix,
      args: {
        'trip_id': rideId,
        'valor': valor,
        'cpf': cpf,
        'email': email,
        'passenger_id': passengerId,
      },
      chaveIdempotencia: 'pix_${rideId}_${DateTime.now().millisecondsSinceEpoch}',
    );

    if (response.sucesso && response.dados is Map) {
      return OmniPixCobranca.fromJson(Map<String, dynamic>.from(response.dados as Map));
    }
    return null;
  }

  /// Consulta autoritativa no servidor se o Pix foi liquidado (`passenger_wallet_check_pix`)
  static Future<bool> verificarLiquidacaoPix(String idTransacao) async {
    final response = await OmniBackendUniversal.executar(
      OmniBackendMethods.walletCheckPix,
      args: {
        'id_transacao': idTransacao,
      },
    );

    if (response.sucesso && response.dados is Map) {
      final status = (response.dados['status'] ?? '').toString().toLowerCase();
      return status == 'approved' || status == 'aprovado' || status == 'pago';
    }
    return false;
  }
}
