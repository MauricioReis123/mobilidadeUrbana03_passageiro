/// Utilitários de Validação e Máscaras para Formulários do OMNI Passageiro
class OmniFormulariosService {
  /// Valida CPF brasileiro com cálculo oficial dos dois dígitos verificadores
  static bool validarCpf(String? cpf) {
    if (cpf == null || cpf.isEmpty) return false;
    final numeros = cpf.replaceAll(RegExp(r'\D'), '');
    if (numeros.length != 11) return false;
    if (RegExp(r'^(\d)\1*$').hasMatch(numeros)) return false;

    // Primeiro dígito
    int soma = 0;
    for (int i = 0; i < 9; i++) {
      soma += int.parse(numeros[i]) * (10 - i);
    }
    int resto = soma % 11;
    int digito1 = resto < 2 ? 0 : 11 - resto;
    if (int.parse(numeros[9]) != digito1) return false;

    // Segundo dígito
    soma = 0;
    for (int i = 0; i < 10; i++) {
      soma += int.parse(numeros[i]) * (11 - i);
    }
    resto = soma % 11;
    int digito2 = resto < 2 ? 0 : 11 - resto;
    return int.parse(numeros[10]) == digito2;
  }

  /// Valida formato de e-mail
  static bool validarEmail(String? email) {
    if (email == null || email.trim().isEmpty) return false;
    final regex = RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,4}$');
    return regex.hasMatch(email.trim());
  }

  /// Valida telefone celular brasileiro (10 ou 11 dígitos com DDD)
  static bool validarTelefone(String? telefone) {
    if (telefone == null || telefone.isEmpty) return false;
    final numeros = telefone.replaceAll(RegExp(r'\D'), '');
    return numeros.length >= 10 && numeros.length <= 11;
  }

  /// Aplica máscara de CPF: 000.000.000-00
  static String formatarCpf(String texto) {
    final numeros = texto.replaceAll(RegExp(r'\D'), '');
    if (numeros.length <= 3) return numeros;
    if (numeros.length <= 6) return '${numeros.substring(0, 3)}.${numeros.substring(3)}';
    if (numeros.length <= 9) {
      return '${numeros.substring(0, 3)}.${numeros.substring(3, 6)}.${numeros.substring(6)}';
    }
    return '${numeros.substring(0, 3)}.${numeros.substring(3, 6)}.${numeros.substring(6, 9)}-${numeros.substring(9, mathMin(11, numeros.length))}';
  }

  /// Aplica máscara de Telefone: (00) 00000-0000
  static String formatarTelefone(String texto) {
    final numeros = texto.replaceAll(RegExp(r'\D'), '');
    if (numeros.length <= 2) return numeros;
    if (numeros.length <= 7) return '(${numeros.substring(0, 2)}) ${numeros.substring(2)}';
    if (numeros.length <= 10) {
      return '(${numeros.substring(0, 2)}) ${numeros.substring(2, 6)}-${numeros.substring(6)}';
    }
    return '(${numeros.substring(0, 2)}) ${numeros.substring(2, 7)}-${numeros.substring(7, mathMin(11, numeros.length))}';
  }

  static int mathMin(int a, int b) => a < b ? a : b;
}
