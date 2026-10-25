import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/calculations.dart';
import '../domain/models.dart';
import '../services/sync_service.dart';
import 'local_store.dart';
import 'sample_data.dart';

/// État central de l'application. Chaque modification passe par [mutate],
/// qui horodate le projet, sauvegarde sur le téléphone, tente une synchronisation
/// et rafraîchit l'interface.
class AppState extends ChangeNotifier {
  AppState({required this.store, required this.sync});

  final LocalStore store;
  final SyncService sync;
  static const _uuid = Uuid();

  late AppData data;
  bool loaded = false;

  String newId() => _uuid.v4();

  Future<void> init() async {
    data = await store.load() ?? sampleData();
    loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await store.save(data);
      final done = await sync.push(data);
      if (done.isNotEmpty) {
        for (final p in data.projects) {
          if (done.contains(p.id)) p.synced = true;
        }
        await store.save(data);
      }
    } catch (e) {
      debugPrint('Sauvegarde impossible : $e');
    }
  }

  /// Applique une modification, puis sauvegarde et notifie.
  void mutate(VoidCallback change, {Project? touch}) {
    change();
    if (touch != null) {
      touch.updatedAt = DateTime.now();
      touch.synced = false;
    }
    notifyListeners();
    _persist().then((_) => notifyListeners());
  }

  // ---------- lecture ----------
  Company get company => data.company;
  List<Prestation> get prestations => data.prestations;
  List<Project> get activeProjects => data.projects.where((p) => !p.archived).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  int get unsyncedCount => data.projects.where((p) => !p.synced && !p.archived).length;

  Project? project(String id) {
    for (final p in data.projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ---------- compte ----------
  void signIn(String phone) => mutate(() {
        data.phone = phone;
        data.authenticated = true;
      });

  void signOut() => mutate(() => data.authenticated = false);

  void setOnline(bool online) => mutate(() => data.online = online);

  Future<void> resetToSample() async {
    data = sampleData()..authenticated = true;
    notifyListeners();
    await _persist();
  }

  // ---------- projets ----------
  Project createProject() {
    final p = Project(id: newId(), city: company.city);
    mutate(() => data.projects.add(p), touch: p);
    return p;
  }

  Project duplicateProject(Project src) {
    final copy = Project.fromJson(src.toJson());
    final p = Project(
      id: newId(),
      client: '${src.client} (copie)',
      phone: src.phone,
      address: src.address,
      city: src.city,
      notes: src.notes,
      photoPaths: List.of(src.photoPaths),
      rooms: [
        for (final r in copy.rooms)
          Room(
            id: newId(),
            name: r.name,
            length: r.length,
            width: r.width,
            height: r.height,
            openings: [for (final o in r.openings) Opening(id: newId(), type: o.type, width: o.width, height: o.height)],
            photoPaths: r.photoPaths,
            planX: r.planX,
            planY: r.planY,
          ),
      ],
    );
    mutate(() => data.projects.add(p), touch: p);
    return p;
  }

  void archiveProject(Project p) => mutate(() => p.archived = true, touch: p);

  // ---------- pièces ----------
  static const roomNames = ['Salon', 'Chambre', 'Cuisine', 'Salle de bain', 'Couloir', 'Autre'];

  Room addRoom(Project p) {
    final previous = p.rooms.isEmpty ? null : p.rooms.last;
    final r = Room(
      id: newId(),
      name: roomNames[p.rooms.length.clamp(0, roomNames.length - 1)],
      length: 3,
      width: 3,
      height: previous?.height ?? 2.8,
      openings: [
        Opening.standard(newId(), OpeningType.door),
        Opening.standard(newId(), OpeningType.window),
      ],
    );
    mutate(() => p.rooms.add(r), touch: p);
    return r;
  }

  void deleteRoom(Project p, Room r) => mutate(() => p.rooms.removeWhere((x) => x.id == r.id), touch: p);

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
