import 'dart:math' as math;

/// Modelo de Categoria de Corrida OMNI (Alinhado ao Ecossistema OMNI + Benchmarking Mercado)
class OmniCategoriaModel {
  final String id;
  final String nome;
  final String descricao;
  final String icone;
  final double tarifaBase;
  final double valorKm;
  final double valorMinuto;
  final double tarifaMinima;
  final int capacidadePassageiros;
  final int tempoEstimadoMinutos;
  final bool disponivel;
  final List<String> diferenciais;
  final String? destaqueTag; // Ex: 'Mais rápido', 'Excelentes ofertas'
  final bool requerCapacete; // Obrigatório para OMNI Moto
  final bool suportaPreferenciasConforto; // Ar-condicionado e conversa (Conforto/Black)
  final bool ehEnvio; // Modalidade de entrega de pacotes/itens

  const OmniCategoriaModel({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.icone,
    required this.tarifaBase,
    required this.valorKm,
    required this.valorMinuto,
    this.tarifaMinima = 9.90,
    this.capacidadePassageiros = 4,
    this.tempoEstimadoMinutos = 4,
    this.disponivel = true,
    required this.diferenciais,
    this.destaqueTag,
    this.requerCapacete = false,
    this.suportaPreferenciasConforto = false,
    this.ehEnvio = false,
  });

  /// Calcula o preço estimado padronizado para distância, duração, paradas e desconto opcional (percentual ou valor fixo)
  /// Fórmula de mobilidade urbana: max(tarifaMinima, tarifaBase + km * valorKm + min * valorMinuto + paradas * 1.50)
  double calcularValorEstimado({
    double km = 9.8,
    int minutos = 22,
    int paradasCount = 0,
    double descontoPercentual = 0.0,
    double descontoValorFixo = 0.0,
  }) {
    final kmEfetivo = km > 0 ? km : 9.8;
    final minEfetivo = minutos > 0 ? minutos : 22;
    final taxaParadas = paradasCount > 0 ? paradasCount * 1.50 : 0.0;
    final calculado = tarifaBase + (kmEfetivo * valorKm) + (minEfetivo * valorMinuto) + taxaParadas;
    final bruto = calculado < tarifaMinima ? tarifaMinima : calculado;
    var liquido = descontoPercentual > 0 ? bruto * (1 - descontoPercentual / 100) : bruto;
    if (descontoValorFixo > 0) {
      liquido = math.max(5.0, liquido - descontoValorFixo);
    }
    return double.parse(liquido.toStringAsFixed(2));
  }

  /// Categorias padrões do ecossistema OMNI
  static const List<OmniCategoriaModel> categoriasPadrao = [
    OmniCategoriaModel(
      id: 'omni_pop',
      nome: 'OMNI Pop',
      descricao: 'Carros compactos e econômicos para o dia a dia',
      icone: 'car_pop',
      tarifaBase: 5.50,
      valorKm: 2.10,
      valorMinuto: 0.35,
      tarifaMinima: 9.90,
      capacidadePassageiros: 4,
      tempoEstimadoMinutos: 3,
      diferenciais: ['Econômico', 'Em 3 min'],
      destaqueTag: 'Mais rápido',
    ),
    OmniCategoriaModel(
      id: 'omni_conforto',
      nome: 'OMNI Conforto',
      descricao: 'Sedans e SUVs com ar-condicionado e motoristas 4.9+',
      icone: 'car_conforto',
      tarifaBase: 7.90,
      valorKm: 2.75,
      valorMinuto: 0.45,
      tarifaMinima: 13.90,
      capacidadePassageiros: 4,
      tempoEstimadoMinutos: 4,
      diferenciais: ['Ar ligado', 'Espaço extra', 'Preferências de viagem'],
      destaqueTag: 'Excelentes ofertas',
      suportaPreferenciasConforto: true,
    ),
    OmniCategoriaModel(
      id: 'omni_moto',
      nome: 'OMNI Moto',
      descricao: 'Viagens ágeis de motocicleta com preço acessível',
      icone: 'moto',
      tarifaBase: 3.50,
      valorKm: 1.25,
      valorMinuto: 0.20,
      tarifaMinima: 6.50,
      capacidadePassageiros: 1,
      tempoEstimadoMinutos: 4,
      diferenciais: ['Mais econômico', 'Foge do trânsito', 'Capacete obrigatório'],
      requerCapacete: true,
    ),
    OmniCategoriaModel(
      id: 'omni_envios',
      nome: 'OMNI Envios',
      descricao: 'Envio rápido de documentos e itens pela cidade',
      icone: 'envios',
      tarifaBase: 4.90,
      valorKm: 1.55,
      valorMinuto: 0.25,
      tarifaMinima: 8.50,
      capacidadePassageiros: 0,
      tempoEstimadoMinutos: 6,
      diferenciais: ['Rastreio ao vivo', 'Código de entrega'],
      ehEnvio: true,
    ),
    OmniCategoriaModel(
      id: 'omni_black',
      nome: 'OMNI Black',
      descricao: 'Sedans executivos pretos com motoristas de elite',
      icone: 'car_black',
      tarifaBase: 12.50,
      valorKm: 3.90,
      valorMinuto: 0.70,
      tarifaMinima: 19.90,
      capacidadePassageiros: 4,
      tempoEstimadoMinutos: 6,
      diferenciais: ['Carro de luxo', 'Água e snacks', 'Motorista nota 4.98+'],
      suportaPreferenciasConforto: true,
    ),
    OmniCategoriaModel(
      id: 'omni_particular',
      nome: 'OMNI Particular',
      descricao: 'Motorista exclusivo agendado, translados e diárias',
      icone: 'car_particular',
      tarifaBase: 25.00,
      valorKm: 4.50,
      valorMinuto: 0.85,
      tarifaMinima: 35.00,
      capacidadePassageiros: 4,
      tempoEstimadoMinutos: 12,
      diferenciais: ['Horário marcado', 'Translado aeroporto', 'Flexibilidade total'],
      suportaPreferenciasConforto: true,
    ),
  ];
}
