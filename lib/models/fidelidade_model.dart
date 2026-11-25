/// Modelo de Nível de Fidelidade OMNI
class OmniNivelFidelidade {
  final String id;
  final String nome; // OMNI Start, OMNI Silver, OMNI Gold, OMNI Black
  final int pontosNecessarios;
  final double cashbackPorCorrida; // Ex: 2%, 5%, 8%, 12%
  final String badgeCorHex;
  final List<String> vantagensExclusivas;

  const OmniNivelFidelidade({
    required this.id,
    required this.nome,
    required this.pontosNecessarios,
    required this.cashbackPorCorrida,
    required this.badgeCorHex,
    required this.vantagensExclusivas,
  });

  int get pontosMinimos => pontosNecessarios;

  static const List<OmniNivelFidelidade> niveis = [
    OmniNivelFidelidade(
      id: 'tier_start',
      nome: 'OMNI Start',
      pontosNecessarios: 0,
      cashbackPorCorrida: 0.02,
      badgeCorHex: '#94A3B8',
      vantagensExclusivas: ['2% de pontos de volta', 'Acesso a cupons mensais'],
    ),
    OmniNivelFidelidade(
      id: 'tier_silver',
      nome: 'OMNI Silver',
      pontosNecessarios: 1000,
      cashbackPorCorrida: 0.05,
      badgeCorHex: '#E2E8F0',
      vantagensExclusivas: ['5% de pontos de volta', 'Descontos de 10% no aeroporto', 'Suporte ágil'],
    ),
    OmniNivelFidelidade(
      id: 'tier_gold',
      nome: 'OMNI Gold',
      pontosNecessarios: 5000,
      cashbackPorCorrida: 0.08,
      badgeCorHex: '#FFB800',
      vantagensExclusivas: [
        '8% de pontos de volta',
        'Prioridade no despacho em horários de pico',
        'Isenção de taxa de cancelamento (até 2x/mês)',
      ],
    ),
    OmniNivelFidelidade(
      id: 'tier_black',
      nome: 'OMNI Black',
      pontosNecessarios: 15000,
      cashbackPorCorrida: 0.12,
      badgeCorHex: '#00FFCC',
      vantagensExclusivas: [
        '12% de pontos de volta em todas as viagens',
        'Motoristas nota 4.95+ exclusivos',
        'Linha direta de concierge 24h',
        'Bebidas de cortesia nas categorias Conforto e Black',
      ],
    ),
  ];
}
