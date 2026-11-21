/// Modelo de Pacote Promocional Inteligente
class OmniPacoteModel {
  final String id;
  final String titulo;
  final String subtitulo;
  final int totalViagens;
  final double valorCheio;
  final double valorComDesconto;
  final int porcentagemDesconto;
  final int validadeDias;
  final String categoriaPermitida;
  final List<String> beneficios;

  const OmniPacoteModel({
    required this.id,
    required this.titulo,
    required this.subtitulo,
    required this.totalViagens,
    required this.valorCheio,
    required this.valorComDesconto,
    required this.porcentagemDesconto,
    required this.validadeDias,
    required this.categoriaPermitida,
    required this.beneficios,
  });

  int get quantidadeViagens => totalViagens;

  static const List<OmniPacoteModel> pacotesDisponiveis = [
    OmniPacoteModel(
      id: 'pkg_5',
      titulo: 'Pacote 5 Viagens',
      subtitulo: 'Ideal para sua semana',
      totalViagens: 5,
      valorCheio: 150.00,
      valorComDesconto: 135.00,
      porcentagemDesconto: 10,
      validadeDias: 30,
      categoriaPermitida: 'OMNI Pop & Conforto',
      beneficios: ['10% de economia direta', 'Válido por 30 dias', 'Sem tarifa dinâmica surpresa'],
    ),
    OmniPacoteModel(
      id: 'pkg_10',
      titulo: 'Pacote 10 Viagens OMNI',
      subtitulo: 'Máxima economia garantida',
      totalViagens: 10,
      valorCheio: 300.00,
      valorComDesconto: 255.00,
      porcentagemDesconto: 15,
      validadeDias: 45,
      categoriaPermitida: 'OMNI Pop & Conforto',
      beneficios: ['15% de desconto garantido', 'Válido por 45 dias', 'Atendimento prioritário'],
    ),
    OmniPacoteModel(
      id: 'pkg_trabalho',
      titulo: 'Passaporte Casa-Trabalho (20 Viagens)',
      subtitulo: 'O pacote corporativo definitivo',
      totalViagens: 20,
      valorCheio: 600.00,
      valorComDesconto: 480.00,
      porcentagemDesconto: 20,
      validadeDias: 30,
      categoriaPermitida: 'OMNI Conforto',
      beneficios: ['20% de economia real', 'Carros categoria Conforto', 'Garantia de pontualidade'],
    ),
  ];
}
