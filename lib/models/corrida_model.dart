import '../tools/mapas_service.dart';
import 'categoria_model.dart';
import 'motorista_model.dart';

/// Estados Oficiais da Corrida no Ecossistema OMNI
enum OmniStatusCorrida {
  solicitada,
  buscandoMotorista,
  aceita,
  aCaminhoEmbarque,
  aguardandoPassageiro,
  emAndamento,
  concluida,
  canceladaPassageiro,
  canceladaMotorista,
}

/// Preferências de Viagem (Conforto / Black / Particular)
class OmniPreferenciasViagem {
  final String temperatura; // 'Frio' | 'Ameno' | 'Sem preferência'
  final String conversa; // 'Prefiro silêncio' | 'Gosto de conversar' | 'Sem preferência'
  final bool precisaPortaMalas;

  const OmniPreferenciasViagem({
    this.temperatura = 'Sem preferência',
    this.conversa = 'Sem preferência',
    this.precisaPortaMalas = false,
  });

  bool get possuiCustomizacao =>
      temperatura != 'Sem preferência' || conversa != 'Sem preferência' || precisaPortaMalas;

  OmniPreferenciasViagem copyWith({
    String? temperatura,
    String? conversa,
    bool? precisaPortaMalas,
  }) {
    return OmniPreferenciasViagem(
      temperatura: temperatura ?? this.temperatura,
      conversa: conversa ?? this.conversa,
      precisaPortaMalas: precisaPortaMalas ?? this.precisaPortaMalas,
    );
  }

  Map<String, dynamic> toJson() => {
    'temperatura': temperatura,
    'conversa': conversa,
    'precisa_porta_malas': precisaPortaMalas,
  };
}

/// Dados de Agendamento de Corrida (Ir agora vs. Mais tarde / Reserve)
class OmniAgendamentoCorrida {
  final DateTime dataHora;
  final bool porHorarioChegada; // false = Horário da partida, true = Horário de chegada

  const OmniAgendamentoCorrida({
    required this.dataHora,
    this.porHorarioChegada = false,
  });

  String get resumoCurto {
    final hh = dataHora.hour.toString().padLeft(2, '0');
    final mm = dataHora.minute.toString().padLeft(2, '0');
    final hoje = DateTime.now();
    final isHoje = dataHora.year == hoje.year && dataHora.month == hoje.month && dataHora.day == hoje.day;
    final diaStr = isHoje ? 'Hoje' : '${dataHora.day.toString().padLeft(2, '0')}/${dataHora.month.toString().padLeft(2, '0')}';
    return '$diaStr · $hh:$mm';
  }
}

/// Dados quando o passageiro solicita corrida para outra pessoa
class OmniPassageiroTerceiro {
  final String nome;
  final String telefone;

  const OmniPassageiroTerceiro({required this.nome, required this.telefone});
}

/// Item de Histórico / Destino Recente (Persistido em SharedPreferences)
class OmniDestinoRecente {
  final String titulo;
  final String subtitulo;
  final double distanciaKm;
  final bool precoAbaixoNormal;

  const OmniDestinoRecente({
    required this.titulo,
    required this.subtitulo,
    required this.distanciaKm,
    this.precoAbaixoNormal = false,
  });

  Map<String, dynamic> toJson() => {
    'titulo': titulo,
    'subtitulo': subtitulo,
    'distancia_km': distanciaKm,
    'preco_abaixo_normal': precoAbaixoNormal,
  };

  factory OmniDestinoRecente.fromJson(Map<String, dynamic> json) => OmniDestinoRecente(
    titulo: json['titulo'] ?? '',
    subtitulo: json['subtitulo'] ?? '',
    distanciaKm: (json['distancia_km'] as num?)?.toDouble() ?? 1.0,
    precoAbaixoNormal: json['preco_abaixo_normal'] == true,
  );
}

/// Dados da cobrança Pix associada
class OmniPixResumo {
  final String idTransacao;
  final String copiaECola;
  final String expiraEm;
  final String status; // 'pendente' | 'aprovado'

  const OmniPixResumo({
    required this.idTransacao,
    required this.copiaECola,
    required this.expiraEm,
    required this.status,
  });

  OmniPixResumo copyWith({String? status}) => OmniPixResumo(
    idTransacao: idTransacao,
    copiaECola: copiaECola,
    expiraEm: expiraEm,
    status: status ?? this.status,
  );
}

/// Modelo Completo de Corrida OMNI
class OmniCorridaModel {
  final String id;
  final String passageiroId;
  final String? motoristaId;
  final OmniMotoristaModel? motorista;
  final OmniCoordenada origem;
  final OmniCoordenada destino;
  final List<OmniCoordenada> paradas;
  final OmniCategoriaModel categoria;
  final double valorEstimado;
  final double? valorFinal;
  final String metodoPagamento; // 'pix', 'cartao', 'dinheiro'
  final String perfilPagamento; // 'pessoal' | 'corporativo'
  final bool usarSaldoCarteira;
  final String? cupomAplicado;
  final double descontoPercentual;
  final double descontoValorFixo;
  final OmniPreferenciasViagem preferencias;
  final OmniAgendamentoCorrida? agendamento;
  final OmniPassageiroTerceiro? passageiroTerceiro;
  final OmniStatusCorrida status;
  final String otpEmbarque;
  final double distanciaKm;
  final int tempoMinutos;
  final DateTime criadoEm;
  final OmniPixResumo? pixCobranca;

  OmniCorridaModel({
    required this.id,
    required this.passageiroId,
    this.motoristaId,
    this.motorista,
    required this.origem,
    required this.destino,
    this.paradas = const [],
    required this.categoria,
    required this.valorEstimado,
    this.valorFinal,
    required this.metodoPagamento,
    this.perfilPagamento = 'pessoal',
    this.usarSaldoCarteira = false,
    this.cupomAplicado,
    this.descontoPercentual = 0.0,
    this.descontoValorFixo = 0.0,
    this.preferencias = const OmniPreferenciasViagem(),
    this.agendamento,
    this.passageiroTerceiro,
    required this.status,
    required this.otpEmbarque,
    required this.distanciaKm,
    required this.tempoMinutos,
    required this.criadoEm,
    this.pixCobranca,
  });

  OmniCorridaModel copyWith({
    OmniStatusCorrida? status,
    OmniMotoristaModel? motorista,
    double? valorFinal,
    OmniCoordenada? destino,
    List<OmniCoordenada>? paradas,
    double? distanciaKm,
    int? tempoMinutos,
    OmniPixResumo? pixCobranca,
  }) {
    return OmniCorridaModel(
      id: id,
      passageiroId: passageiroId,
      motoristaId: motorista?.id ?? motoristaId,
      motorista: motorista ?? this.motorista,
      origem: origem,
      destino: destino ?? this.destino,
      paradas: paradas ?? this.paradas,
      categoria: categoria,
      valorEstimado: valorEstimado,
      valorFinal: valorFinal ?? this.valorFinal,
      metodoPagamento: metodoPagamento,
      perfilPagamento: perfilPagamento,
      usarSaldoCarteira: usarSaldoCarteira,
      cupomAplicado: cupomAplicado,
      descontoPercentual: descontoPercentual,
      descontoValorFixo: descontoValorFixo,
      preferencias: preferencias,
      agendamento: agendamento,
      passageiroTerceiro: passageiroTerceiro,
      status: status ?? this.status,
      otpEmbarque: otpEmbarque,
      distanciaKm: distanciaKm ?? this.distanciaKm,
      tempoMinutos: tempoMinutos ?? this.tempoMinutos,
      criadoEm: criadoEm,
      pixCobranca: pixCobranca ?? this.pixCobranca,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'passageiro_id': passageiroId,
    'motorista_id': motoristaId,
    'origem': origem.toJson(),
    'destino': destino.toJson(),
    'paradas': paradas.map((p) => p.toJson()).toList(),
    'categoria_id': categoria.id,
    'valor_estimado': valorEstimado,
    'valor_final': valorFinal,
    'metodo_pagamento': metodoPagamento,
    'perfil_pagamento': perfilPagamento,
    'usar_saldo_carteira': usarSaldoCarteira,
    'cupom_aplicado': cupomAplicado,
    'desconto_percentual': descontoPercentual,
    'desconto_valor_fixo': descontoValorFixo,
    'preferencias': preferencias.toJson(),
    'status': status.name,
    'otp_embarque': otpEmbarque,
    'distancia_km': distanciaKm,
    'tempo_minutos': tempoMinutos,
    'criado_em': criadoEm.toIso8601String(),
  };
}
