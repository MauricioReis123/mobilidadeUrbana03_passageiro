/// Serviço de Tradução e Centralização de Textos OMNI
class OmniTranslateService {
  static const Map<String, String> _textosPtBr = {
    'app_title': 'OMNI Mobilidade Urbana',
    'onde_vamos': 'Para onde vamos hoje?',
    'casa': 'Casa',
    'trabalho': 'Trabalho',
    'solicitar': 'Solicitar OMNI',
    'buscando': 'Buscando motorista próximo...',
    'motorista_a_caminho': 'Motorista a caminho',
    'otp_label': 'Código de Embarque (OTP)',
    'cancelar': 'Cancelar Corrida',
    'pagamento_pix': 'Pix (Instantâneo)',
    'pagamento_cartao': 'Cartão de Crédito',
    'pagamento_dinheiro': 'Dinheiro a Bordo',
    'fidelidade_titulo': 'Clube OMNI Fidelidade',
    'pacotes_titulo': 'Pacotes de Viagens com Desconto',
    'indique_titulo': 'Indique e Ganhe',
    'viagem_particular': 'OMNI Particular & Translados',
  };

  static String obter(String chave) {
    return _textosPtBr[chave] ?? chave;
  }
}
