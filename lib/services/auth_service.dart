/// Connexion par numéro de téléphone et code SMS (écran E1).
///
/// L'application est « local d'abord » : en attendant le choix du fournisseur SMS
/// (question ouverte du cahier des charges), [FakeSmsAuthService] simule l'envoi.
/// Brancher un vrai service = implémenter [AuthService] et l'injecter dans main.dart.
abstract class AuthService {
  /// Envoie un code au numéro (9 chiffres, sans le 0 ni +212).
  Future<void> requestCode(String phone);

  /// Vérifie le code saisi.
  Future<bool> verifyCode(String phone, String code);

  /// Texte d'aide affiché sous le champ de code (démo uniquement).
  String? get demoHint;
}

class FakeSmsAuthService implements AuthService {
  static const demoCode = '482913';

  @override
  Future<void> requestCode(String phone) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  Future<bool> verifyCode(String phone, String code) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return code.trim() == demoCode;
  }

  @override
  String? get demoHint => 'Mode démonstration : le code est $demoCode.';
}

/// Numéro mobile ou fixe marocain : 9 chiffres commençant par 5, 6 ou 7.
String? normalizeMoroccanPhone(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('212')) digits = digits.substring(3);
  if (digits.startsWith('0')) digits = digits.substring(1);
  return RegExp(r'^[5-7]\d{8}$').hasMatch(digits) ? digits : null;
}
