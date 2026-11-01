import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/app_state.dart';
import '../../session/session_controller.dart';
import 'team_screen.dart';
import '../widgets/common.dart';
import '../widgets/photos.dart';

/// E2 · Profil de l'entreprise.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final session = context.watch<SessionController>();
    final me = session.user;
    final c = s.company;
    void edit(VoidCallback f) => s.mutate(f);

    return Scaffold(
      appBar: AppBar(title: const Text('Profil de l\'entreprise'), actions: const [SyncBadge()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (me != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(me.fullName),
              subtitle: Text([
                me.email,
                me.roleLabel,
                if (session.isDemo) 'démonstration sans serveur' else if (!session.verifiedOnline) 'hors connexion',
              ].join(' · ')),
            ),
          ),
        if (me != null && me.isAdmin && !session.isDemo)
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TeamScreen())),
            icon: const Icon(Icons.group_outlined),
            label: const Text('Équipe et invitations'),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Container(
            width: 72,
            height: 72,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: c.logoPath == null
                ? const Center(child: Text('Logo'))
                : Image.file(File(c.logoPath!), fit: BoxFit.contain),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () async {
              final picked = await pickPhotos(context, multiple: false);
              if (picked.isNotEmpty) edit(() => c.logoPath = picked.first);
            },
            child: const Text('Choisir un logo'),
          ),
        ]),
        const SizedBox(height: 12),
        if (!c.hasValidIce)
          const AlertBox(
            'L\'ICE (15 chiffres) est obligatoire avant le premier devis : il figure sur vos documents commerciaux.',
            kind: AlertKind.warning,
          ),
        EditField(label: 'Raison sociale', value: c.name, onChanged: (v) => edit(() => c.name = v)),
        Row(children: [
          Expanded(child: EditField(label: 'Téléphone', value: c.phone, keyboardType: TextInputType.phone, onChanged: (v) => edit(() => c.phone = v))),
          const SizedBox(width: 12),
          Expanded(child: EditField(label: 'Ville', value: c.city, onChanged: (v) => edit(() => c.city = v))),
        ]),
        EditField(label: 'Adresse', value: c.address, onChanged: (v) => edit(() => c.address = v)),
        const SectionHeader('Identifiants légaux'),
        EditField(
          label: 'ICE (15 chiffres)',
          value: c.ice,
          keyboardType: TextInputType.number,
          maxLength: 15,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) => edit(() => c.ice = v),
        ),
        Row(children: [
          Expanded(child: EditField(label: 'IF', value: c.ifNumber, keyboardType: TextInputType.number, onChanged: (v) => edit(() => c.ifNumber = v))),
          const SizedBox(width: 12),
          Expanded(child: EditField(label: 'RC', value: c.rc, onChanged: (v) => edit(() => c.rc = v))),
          const SizedBox(width: 12),
          Expanded(child: EditField(label: 'Patente', value: c.patente, keyboardType: TextInputType.number, onChanged: (v) => edit(() => c.patente = v))),
        ]),
        const SectionHeader('Devis'),
        Row(children: [
          Expanded(child: NumField(label: 'TVA par défaut', suffix: '%', value: c.vatPercent, onChanged: (v) => edit(() => c.vatPercent = v.clamp(0, 100).toDouble()))),
          const SizedBox(width: 12),
          Expanded(child: NumField(label: 'Validité', suffix: 'jours', decimals: 0, value: c.validityDays.toDouble(), onChanged: (v) => edit(() => c.validityDays = v.round()))),
        ]),
        EditField(label: 'Mentions de bas de page', value: c.footer, maxLines: 3, onChanged: (v) => edit(() => c.footer = v)),
        const Divider(height: 32),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
            onPressed: () async {
              final path = await s.store.exportFile(s.data);
              await SharePlus.instance.share(
                ShareParams(files: [XFile(path, mimeType: 'application/json')], subject: 'Export LAMAALAM'),
              );
            },
            child: const Text('Exporter mes données'),
          ),
          TextButton(
            onPressed: () async {
              if (await confirm(context, 'Se déconnecter ?',
                  'Les données saisies restent sur ce téléphone. Il faudra votre mot de passe et votre code pour revenir.',
                  ok: 'Se déconnecter')) {
                await session.logout();
              }
            },
            child: const Text('Se déconnecter'),
          ),
        ]),
      ]),
    );
  }
}
