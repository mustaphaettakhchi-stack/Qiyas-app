import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/calculations.dart';
import '../domain/models.dart';
import 'local_store.dart';
import 'templates.dart';

/// État central de l'application. Chaque modification passe par [mutate], qui horodate,
/// sauvegarde sur le téléphone, rafraîchit l'interface et prévient la synchronisation.
class AppState extends ChangeNotifier {
  AppState({required this.store});

  final LocalStore store;
  static const _uuid = Uuid();

  late AppData data;
  bool loaded = false;

  /// Appelé après chaque modification enregistrée (déclenche la synchronisation différée).
  VoidCallback? onLocalChange;

  /// Identifiants ordonnés dans le temps (UUID v7), générés hors connexion.
  String newId() => _uuid.v7();

  Future<void> init() async {
    data = await store.load() ?? AppData(company: Company(), prestations: [], projects: []);
    _migrateLegacyClients();
    loaded = true;
    notifyListeners();
  }

  /// Reprise des projets Qiyas : le nom et le téléphone saisis deviennent une fiche client.
  void _migrateLegacyClients() {
    var changed = false;
    for (final p in data.projects) {
      if (p.clientId != null || p.legacyClientName.trim().isEmpty) continue;
      final existing = data.clients.where((c) =>
          c.displayName.trim().toLowerCase() == p.legacyClientName.trim().toLowerCase() &&
          c.phone == p.legacyClientPhone);
      final client = existing.isNotEmpty
          ? existing.first
          : (Client(id: newId(), displayName: p.legacyClientName.trim(), phone: p.legacyClientPhone, city: p.city)
            ..markEdited());
      if (existing.isEmpty) data.clients.add(client);
      p
        ..clientId = client.id
        ..legacyClientName = ''
        ..legacyClientPhone = ''
        ..markEdited();
      changed = true;
    }
    if (changed) store.save(data);
  }

  Future<void> save() async {
    try {
      await store.save(data);
    } catch (e) {
      debugPrint('Sauvegarde impossible : $e');
    }
  }

  /// Applique une modification, puis sauvegarde et notifie.
  /// [meta] : la modification touche des informations partagées avec le serveur
  /// (fiche projet ou client) et devra être synchronisée.
  void mutate(VoidCallback change, {Project? touch, bool meta = false, Client? client, Room? room}) {
    change();
    room?.markEdited();
    if (touch != null) {
      touch.updatedAt = DateTime.now();
      if (meta) touch.markEdited();
    }
    client?.markEdited();
    notifyListeners();
    save().then((_) => onLocalChange?.call());
  }

  /// Rafraîchit l'interface après une synchronisation (données déjà modifiées).
  Future<void> afterSync() async {
    await save();
    notifyListeners();
  }

  // ---------- lecture ----------
  Company get company => data.company;
  List<Prestation> get prestations => data.prestations;
  List<Project> get activeProjects => data.projects.where((p) => !p.deleted && !p.archived).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  List<Client> get activeClients => data.clients.where((c) => !c.deleted).toList()
    ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

  /// Fiches en attente d'envoi (y compris les suppressions), hors refus et conflits.
  int get pendingCount =>
      data.clients.where((c) => c.dirty && c.syncError == null).length +
      data.projects.where((p) => p.dirty && p.syncError == null).length +
      data.projects.fold<int>(0, (n, p) => n + p.rooms.where((r) => r.dirty && r.syncError == null).length) +
      data.roomTombstones.where((t) => t.syncError == null).length;

  int get rejectedCount =>
      data.clients.where((c) => c.syncError != null).length +
      data.projects.where((p) => p.syncError != null).length +
      data.projects.fold<int>(0, (n, p) => n + p.rooms.where((r) => r.syncError != null).length) +
      data.roomTombstones.where((t) => t.syncError != null).length;

  Project? project(String id) {
    for (final p in data.projects) {
      if (p.id == id && !p.deleted) return p;
    }
    return null;
  }

  Client? client(String? id) {
    if (id == null) return null;
    for (final c in data.clients) {
      if (c.id == id && !c.deleted) return c;
    }
    return null;
  }

  Client? clientOf(Project p) => client(p.clientId);

  String clientName(Project p) {
    final c = clientOf(p);
    return c == null || c.displayName.trim().isEmpty ? 'Client à renseigner' : c.displayName;
  }

  List<Project> projectsOf(Client c) => data.projects.where((p) => !p.deleted && p.clientId == c.id).toList();

  // ---------- clients ----------
  Client createClient({String name = ''}) {
    final c = Client(id: newId(), displayName: name);
    mutate(() => data.clients.add(c), client: c);
    return c;
  }

  /// Supprime une fiche client sans projet. La suppression est envoyée au serveur.
  void deleteClient(Client c) {
    if (projectsOf(c).isNotEmpty) return;
    mutate(() {
      if (c.serverVersion == null) {
        data.clients.remove(c); // jamais envoyée : rien à supprimer sur le serveur
      } else {
        c.deleted = true;
      }
    }, client: c);
  }

  // ---------- projets ----------
  Project createProject({String? clientId}) {
    final c = client(clientId);
    final p = Project(id: newId(), clientId: clientId, city: c?.city ?? company.city, address: c?.address ?? '');
    mutate(() => data.projects.add(p), touch: p, meta: true);
    return p;
  }

  Project duplicateProject(Project src) {
    final copy = Project.fromJson(src.toJson());
    final p = Project(
      id: newId(),
      clientId: src.clientId,
      name: src.name.isEmpty ? '' : '${src.name} (copie)',
      projectType: src.projectType,
      propertyKind: src.propertyKind,
      address: src.address,
      city: src.city,
      notes: src.notes,
      photoPaths: List.of(src.photoPaths),
      rooms: [for (final r in copy.rooms) _copyRoom(r)],
    );
    mutate(() => data.projects.add(p), touch: p, meta: true);
    return p;
  }

  void archiveProject(Project p) => mutate(() => p.status = 'archived', touch: p, meta: true);

  // ---------- pièces ----------
  static const roomNames = ['Salon', 'Chambre', 'Cuisine', 'Salle de bain', 'Couloir', 'Autre'];

  /// Nouvelle pièce : murs à mesurer (longueurs nulles), hauteur reprise de la pièce
  /// précédente ou valeur standard de 2,80 m marquée « à vérifier ».
  Room addRoom(Project p) {
    final previous = p.rooms.isEmpty ? null : p.rooms.last;
    final r = Room.rectangle(
      id: newId(),
      name: roomNames[p.rooms.length.clamp(0, roomNames.length - 1)],
      length: 0,
      width: 0,
      height: previous?.height ?? 2.8,
    )..heightSource = previous?.heightSource ?? MeasureSource.standard;
    for (var i = 0; i < r.walls.length; i++) {
      r.walls[i] = Wall(id: newId(), length: 0, lengthSource: MeasureSource.standard);
    }
    mutate(() => p.rooms.add(r), touch: p, room: r);
    return r;
  }

  Room _copyRoom(Room src) => Room.fromJson({...src.toJson(), 'id': newId(), 'sv': null, 'dirty': true})
    ..walls = [for (final w in src.walls) Wall(id: newId(), length: w.length, lengthSource: w.lengthSource, angle: w.angle)]
    ..openings = [
      for (final o in src.openings)
        Opening(
          id: newId(),
          type: o.type,
          wallIndex: o.wallIndex,
          width: o.width,
          height: o.height,
          widthSource: o.widthSource,
          heightSource: o.heightSource,
        ),
    ];

  /// Supprime une pièce ; si elle était connue du serveur, la suppression lui sera envoyée.
  void deleteRoom(Project p, Room r) => mutate(() {
        p.rooms.removeWhere((x) => x.id == r.id);
        final version = r.serverVersion;
        if (version != null) {
          data.roomTombstones.add(RoomTombstone(id: r.id, projectId: p.id, serverVersion: version));
        }
      }, touch: p);

  // ---------- prestations ----------
  void addPrestation() => mutate(() => data.prestations.add(Prestation(id: newId(), name: 'Nouvelle prestation')));

  void duplicatePrestation(Prestation src) => mutate(() {
        final i = data.prestations.indexOf(src);
        data.prestations.insert(
          i + 1,
          Prestation(
            id: newId(),
            name: '${src.name} (copie)',
            description: src.description,
            unit: src.unit,
            base: src.base,
            unitPriceCents: src.unitPriceCents,
          ),
        );
      });

  void addTemplate(String trade) => mutate(() {
        for (final t in kPriceTemplates[trade] ?? const <(String, String, String, QuantityBase)>[]) {
          data.prestations.add(Prestation(id: newId(), name: t.$1, description: t.$2, unit: t.$3, base: t.$4));
        }
      });

  // ---------- devis ----------
  Quote draftQuoteFor(Project p) {
    for (final q in p.quotes) {
      if (q.status == QuoteStatus.draft) return q;
    }
    return createQuote(p);
  }

  Quote createQuote(Project p) {
    late Quote q;
    mutate(() {
      data.quoteCounter++;
      final year = DateTime.now().year;
      q = Quote(
        id: newId(),
        number: 'DV-$year-${data.quoteCounter.toString().padLeft(4, '0')}',
        date: DateTime.now(),
      );
      p.quotes.add(q);
    }, touch: p);
    return q;
  }

  /// Un devis envoyé est figé : toute modification crée une nouvelle version (v2, v3…).
  Quote newVersion(Project p, Quote from) {
    final base = from.number.replaceAll(RegExp(r'-v\d+$'), '');
    final q = Quote(
      id: newId(),
      number: '$base-v${from.version + 1}',
      version: from.version + 1,
      date: DateTime.now(),
      discountPercent: from.discountPercent,
      depositPercent: from.depositPercent,
      lines: [for (final l in from.lines) l.copyWith(id: newId())],
    );
    mutate(() => p.quotes.add(q), touch: p);
    return q;
  }

  void addLineFromPrestation(Project p, Quote q, Prestation pres) =>
      mutate(() => q.lines.add(lineFrom(pres, newId())), touch: p);

  void addFreeLine(Project p, Quote q) => mutate(
        () => q.lines.add(QuoteLine(id: newId(), label: 'Ligne libre', unit: 'forfait', quantity: 1, manual: true)),
        touch: p,
      );

  void moveLine(Project p, Quote q, int index, int delta) {
    final j = index + delta;
    if (j < 0 || j >= q.lines.length) return;
    mutate(() {
      final l = q.lines.removeAt(index);
      q.lines.insert(j, l);
    }, touch: p);
  }

  void markSent(Project p, Quote q) => mutate(() {
        final m = projectMeasures(p);
        for (final l in q.lines) {
          l.frozenQuantity = lineQuantity(p, l, measures: m);
        }
        q.status = QuoteStatus.sent;
      }, touch: p);

  void setStatus(Project p, Quote q, QuoteStatus s) => mutate(() => q.status = s, touch: p);
}
