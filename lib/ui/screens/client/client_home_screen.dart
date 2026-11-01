import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/labels.dart';
import '../../../data/client_space.dart';
import '../../../session/api_client.dart';
import '../../../session/session_controller.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';
import 'client_project_screen.dart';

/// Accueil d'un compte client : ses projets, rien d'autre (USER_FLOWS P8).
class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  List<ClientProject>? _projects;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final p = await ClientSpaceApi(context.read<SessionController>().api).projects();
      if (mounted) {
        setState(() {
          _projects = p;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final t = Theme.of(context).textTheme;
    final projects = _projects;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const LogoTile(size: 32),
            const SizedBox(width: 10),
            Flexible(child: Text(session.user?.fullName ?? 'Mon espace', overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'logout' &&
                  await confirm(context, 'Se déconnecter ?', 'Vous pourrez revenir avec votre mot de passe.', ok: 'Se déconnecter')) {
                await session.logout();
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'logout', child: Text('Se déconnecter'))],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Mes projets avec Group LAMAALAM', style: t.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Consultation seulement : devis envoyés, photos partagées par l\'équipe, étapes et messages. '
              'Une connexion internet est nécessaire.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_error != null && projects == null)
              AlertBox(
                _error!,
                kind: AlertKind.error,
                action: TextButton(onPressed: _load, child: const Text('Réessayer')),
              )
            else if (projects == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (projects.isEmpty)
              const AlertBox('Aucun projet n\'est encore rattaché à votre compte. Contactez Group LAMAALAM.')
            else
              for (final p in projects)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.home_work_outlined),
                    title: Text(p.title),
                    subtitle: Text(
                      [
                        if (p.reference.isNotEmpty && p.reference != p.title) p.reference,
                        kProjectStatuses[p.status] ?? p.status,
                        [p.address, p.city].where((x) => x.isNotEmpty).join(', '),
                        'mis à jour le ${frDate(p.updatedAt)}',
                      ].where((x) => x.isNotEmpty).join(' · '),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ClientProjectScreen(projectId: p.id, title: p.title),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
