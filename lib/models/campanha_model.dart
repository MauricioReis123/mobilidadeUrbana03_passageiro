/// Modelo de Campanha Promocional / Cupom para Passageiros OMNI
/// Sincronizado com MySQL (`omni_campanhas_passageiro`) e Firebase RTDB (`/campanhas_passageiro`)
class OmniCampanhaPassageiro {
  final String id;
  final String titulo;
  final String mensagem;
  final String imagemUrl;
  final String codigoCupom;
  final String tipoDesconto; // 'percentual' | 'valor_fixo'
  final double percentualDesconto;
  final double valorFixo;
  final String cidadeAlvo; // 'todas' ou nome da cidade (ex: 'Camboriú', 'Balneário Camboriú')
  final String dataHoraDisparo;
  final String dataHoraExpiracao;
  final String status; // 'agendada' | 'enviada' | 'cancelada'
  final String disparadaEm;
  final String fcmMessageId;
  final String fcmWarning;

  const OmniCampanhaPassageiro({
    required this.id,
    required this.titulo,
    required this.mensagem,
    this.imagemUrl = '',
    this.codigoCupom = '',
    this.tipoDesconto = 'percentual',
    this.percentualDesconto = 0.0,
    this.valorFixo = 0.0,
    this.cidadeAlvo = 'todas',
    this.dataHoraDisparo = '',
    this.dataHoraExpiracao = '',
    this.status = 'enviada',
    this.disparadaEm = '',
    this.fcmMessageId = '',
    this.fcmWarning = '',
  });

  bool get estaExpirada {
    final exp = dataHoraExpiracao.trim();
    if (exp.isEmpty) return false;
    final dt = DateTime.tryParse(exp);
    if (dt == null) return false;
    return dt.isBefore(DateTime.now());
  }

  bool get ehAtivaParaPassageiro {
    if (status == 'cancelada' || estaExpirada) return false;
    if (status == 'enviada') return true;
    if (status == 'agendada') {
      final disp = dataHoraDisparo.trim();
      if (disp.isEmpty) return false;
      final dt = DateTime.tryParse(disp);
      if (dt == null) return false;
      return !dt.isAfter(DateTime.now());
    }
    return false;
  }

  static String normalizarSlugCidade(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    const mapa = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    mapa.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return s.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  bool aplicaNaCidade(String cidadeAtual) {
    final alvo = cidadeAlvo.trim();
    if (alvo.isEmpty || alvo.toLowerCase() == 'todas') return true;
    final atualSlug = normalizarSlugCidade(cidadeAtual);
    if (atualSlug.isEmpty) return true;
    return normalizarSlugCidade(alvo) == atualSlug;
  }

  String get resumoDesconto {
    if (tipoDesconto == 'valor_fixo' && valorFixo > 0) {
      return 'R\$ ${valorFixo.toStringAsFixed(2).replaceAll('.', ',')} OFF';
    }
    if (percentualDesconto > 0) {
      return '${percentualDesconto.toStringAsFixed(0)}% OFF';
    }
    return 'Promoção OMNI';
  }

  factory OmniCampanhaPassageiro.fromMap(String keyId, Map<dynamic, dynamic> map) {
    final cid = (map['campaign_id'] ?? map['id'] ?? keyId).toString();
    return OmniCampanhaPassageiro(
      id: cid,
      titulo: (map['titulo'] ?? '').toString(),
      mensagem: (map['mensagem'] ?? '').toString(),
      imagemUrl: (map['imagem_url'] ?? '').toString(),
      codigoCupom: (map['codigo_cupom'] ?? '').toString().trim().toUpperCase(),
      tipoDesconto: (map['tipo_desconto'] ?? 'percentual').toString(),
      percentualDesconto: (map['percentual_desconto'] as num?)?.toDouble() ??
          double.tryParse((map['percentual_desconto'] ?? '0').toString()) ??
          0.0,
      valorFixo: (map['valor_fixo'] as num?)?.toDouble() ??
          double.tryParse((map['valor_fixo'] ?? '0').toString()) ??
          0.0,
      cidadeAlvo: (map['cidade_alvo'] ?? 'todas').toString(),
      dataHoraDisparo: (map['data_hora_disparo'] ?? '').toString(),
      dataHoraExpiracao: (map['data_hora_expiracao'] ?? '').toString(),
      status: (map['status'] ?? 'enviada').toString(),
      disparadaEm: (map['disparada_em'] ?? '').toString(),
      fcmMessageId: (map['fcm_message_id'] ?? '').toString(),
      fcmWarning: (map['fcm_warning'] ?? map['fcm_erro'] ?? '').toString(),
    );
  }
}
