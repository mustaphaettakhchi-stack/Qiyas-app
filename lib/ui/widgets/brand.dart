import 'package:flutter/material.dart';

/// Logo Groupe LAMAALAM sur sa tuile claire d'origine (jamais détouré ni recoloré).
class LogoTile extends StatelessWidget {
  const LogoTile({super.key, this.size = 140});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.12),
        child: Image.asset(
          'assets/branding/logo_lamaalam_sans_telephone_512.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          semanticLabel: 'Logo Groupe LAMAALAM',
        ),
      );
}

/// Champ mot de passe avec bouton afficher / masquer.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Mot de passe',
    this.newPassword = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool newPassword;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        obscureText: _hidden,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
        onSubmitted: widget.onSubmitted,
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: IconButton(
            tooltip: _hidden ? 'Afficher' : 'Masquer',
            icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        ),
      );
}
