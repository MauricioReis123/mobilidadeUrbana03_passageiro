import '../tools/firebase_service.dart';

/// Modelo de Motorista Parceiro OMNI
class OmniMotoristaModel {
  final String id;
  final String nome;
  final String fotoUrl;
  final String telefone;
  final double avaliacao;
  final int totalViagens;
  final String modeloVeiculo;
  final String corVeiculo;
  final String placaVeiculo;
  final String categoria;
  final double lat;
  final double lng;
  final int distanciaMinutos;

  const OmniMotoristaModel({
    required this.id,
    required this.nome,
    this.fotoUrl = '',
    required this.telefone,
    required this.avaliacao,
    required this.totalViagens,
    required this.modeloVeiculo,
    required this.corVeiculo,
    required this.placaVeiculo,
    required this.categoria,
    this.lat = -23.562,
    this.lng = -46.654,
    this.distanciaMinutos = 3,
  });

  String get iniciais {
    final parts = nome.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'OM';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  factory OmniMotoristaModel.fromTelemetria(
    OmniMotoristaTelemetria t, {
    int distanciaMinutos = 4,
  }) {
    return OmniMotoristaModel(
      id: t.driverId,
      nome: t.nome,
      telefone: '',
      avaliacao: t.avaliacao,
      totalViagens: 0,
      modeloVeiculo: t.modeloVeiculo,
      corVeiculo: 'Padrão OMNI',
      placaVeiculo: t.placa,
      categoria: 'omni_pop',
      lat: t.lat,
      lng: t.lng,
      distanciaMinutos: distanciaMinutos,
    );
  }

  factory OmniMotoristaModel.fromJson(Map<String, dynamic> json) => OmniMotoristaModel(
    id: json['id'] ?? '',
    nome: json['nome'] ?? '',
    fotoUrl: json['foto_url'] ?? '',
    telefone: json['telefone'] ?? '',
    avaliacao: (json['avaliacao'] as num?)?.toDouble() ?? 5.0,
    totalViagens: json['total_viagens'] ?? 0,
    modeloVeiculo: json['modelo_veiculo'] ?? '',
    corVeiculo: json['cor_veiculo'] ?? '',
    placaVeiculo: json['placa_veiculo'] ?? '',
    categoria: json['categoria'] ?? 'omni_pop',
    lat: (json['lat'] as num?)?.toDouble() ?? -23.562,
    lng: (json['lng'] as num?)?.toDouble() ?? -46.654,
    distanciaMinutos: json['distancia_minutos'] ?? 3,
  );
}
