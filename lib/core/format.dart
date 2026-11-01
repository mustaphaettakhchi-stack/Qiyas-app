// Formats français sans dépendance à intl : séparateur de milliers en espace simple,
// virgule décimale. L'espace simple garde le texte compatible avec les polices du PDF.

String _group(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

/// 1234.5 -> "1 234,50"
String fmt2(double v) {
  final cents = (v * 100).round();
  final whole = cents ~/ 100;
  final frac = (cents.abs() % 100).toString().padLeft(2, '0');
  final sign = cents < 0 && whole == 0 ? '-' : '';
  return '$sign${_group(whole)},$frac';
}

/// Centimes -> "27 989 DH" (arrondi au dirham pour l'affichage).
String dh(int cents) => '${_group((cents / 100).round())} DH';

/// "5,20" ou "5.20" -> 5.2 ; renvoie null si invalide.
double? parseNum(String s) {
  final v = double.tryParse(s.trim().replaceAll(' ', '').replaceAll(',', '.'));
  if (v == null || v.isNaN || v < 0) return null;
  return v;
}

String frDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// "05/11/2026 à 09:30".
String frDateTime(DateTime d) => '${frDate(d)} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Numéro marocain -> format international pour wa.me (212XXXXXXXXX).
String waNumber(String phone) {
  var t = phone.replaceAll(RegExp(r'\D'), '');
  if (t.startsWith('00')) t = t.substring(2);
  if (t.startsWith('0')) t = '212${t.substring(1)}';
  if (t.length == 9) t = '212$t';
  return t;
}

/// Montant exact au centime, avec sa devise : 2798895 -> "27 988,95 MAD" ; EUR -> "… €".
/// À utiliser sur les devis : les montants affichés doivent correspondre exactement aux calculs.
String money(int cents, String currency) {
  final sign = cents < 0 ? '-' : '';
  final a = cents.abs();
  return '$sign${_group(a ~/ 100)},${(a % 100).toString().padLeft(2, '0')} ${currency == 'EUR' ? '€' : 'MAD'}';
}

/// Points de base -> pourcentage : 2000 -> "20 %", 750 -> "7,5 %".
String pctBp(int bp) {
  final s = (bp / 100).toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return '${s.replaceAll('.', ',')} %';
}

/// Taux de change × 10 000 -> "10,8500".
String rateE4(int e4) => '${e4 ~/ 10000},${(e4 % 10000).toString().padLeft(4, '0')}';
