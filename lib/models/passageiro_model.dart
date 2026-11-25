/// Modelo de Passageiro OMNI
class OmniPassageiroModel {
  final String id;
  final String nome;
  final String email;
  final String telefone;
  final String cpf;
  final String? fotoUrl;
  final String nivelFidelidade; // OMNI Start, Silver, Gold, Black
  final int saldoPontos;
  final String codigoIndicacao;
  final double saldoCarteira;
  final double avaliacaoMedia;

  OmniPassageiroModel({
    required this.id,
    required this.nome,
    required this.email,
    required this.telefone,
    required this.cpf,
    this.fotoUrl,
    this.nivelFidelidade = 'OMNI Start',
    this.saldoPontos = 150,
    required this.codigoIndicacao,
    this.saldoCarteira = 0.0,
    this.avaliacaoMedia = 5.0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'nome': nome,
    'email': email,
    'telefone': telefone,
    'cpf': cpf,
    'foto_url': fotoUrl,
    'nivel_fidelidade': nivelFidelidade,
    'saldo_pontos': saldoPontos,
    'codigo_indicacao': codigoIndicacao,
    'saldo_carteira': saldoCarteira,
    'avaliacao_media': avaliacaoMedia,
  };

  factory OmniPassageiroModel.fromJson(Map<String, dynamic> json) => OmniPassageiroModel(
    id: json['id'] ?? '',
    nome: json['nome'] ?? '',
    email: json['email'] ?? '',
    telefone: json['telefone'] ?? '',
    cpf: json['cpf'] ?? '',
    fotoUrl: json['foto_url'],
    nivelFidelidade: json['nivel_fidelidade'] ?? 'OMNI Start',
    saldoPontos: json['saldo_pontos'] ?? 0,
    codigoIndicacao: json['codigo_indicacao'] ?? '',
    saldoCarteira: (json['saldo_carteira'] as num?)?.toDouble() ?? 0.0,
    avaliacaoMedia: (json['avaliacao_media'] as num?)?.toDouble() ?? 5.0,
  );
}
