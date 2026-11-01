import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/calculations.dart';
import '../domain/metre.dart';
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
    data = await store.load() ?? AppData(company: Company(), projects: []);
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
  void mutate(VoidCallback change, {Project? touch, bool meta = false, Client? client, Room? room, Quote? quote}) {
    change();
    room?.markEdited();
    quote?.markEdited();
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
  List<WorkItem> get workItems => data.workItems.where((w) => !w.deleted).toList()
    ..sort((a, b) => '${a.category}${a.code}${a.name}'.compareTo('${b.category}${b.code}${b.name}'));
  List<MaterialItem> get materials => data.materials.where((m) => !m.deleted).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  List<Supplier> get suppliers => data.suppliers.where((x) => !x.deleted).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  WorkItem? workItem(String? id) => data.workItems.where((w) => w.id == id && !w.deleted).firstOrNull;
  MaterialItem? material(String? id) => data.materials.where((m) => m.id == id && !m.deleted).firstOrNull;
  Supplier? supplier(String? id) => data.suppliers.where((x) => x.id == id && !x.deleted).firstOrNull;
  List<Project> get activeProjects => data.projects.where((p) => !p.deleted && !p.archived).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  List<Client> get activeClients => data.clients.where((c) => !c.deleted).toList()
    ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

  /// Fiches en attente d'envoi (y compris les suppressions), hors refus et conflits.
  int get pendingCount =>
      data.clients.where((c) => c.dirty && c.syncError == null).length +
      data.projects.where((p) => p.dirty && p.syncError == null).length +
      data.projects.fold<int>(0, (n, p) => n + p.rooms.where((r) => r.dirty && r.syncError == null).length) +
      data.roomTombstones.where((t) => t.syncError == null).length +
      data.projects.fold<int>(0, (n, p) => n + p.quotes.where((q) => q.dirty && !q.legacy && q.syncError == null).length);

  int get rejectedCount =>
      data.clients.where((c) => c.syncError != null).length +
      data.projects.where((p) => p.syncError != null).length +
      data.projects.fold<int>(0, (n, p) => n + p.rooms.where((r) => r.syncError != null).length) +
      data.roomTombstones.where((t) => t.syncError != null).length +
      data.projects.fold<int>(0, (n, p) => n + p.quotes.where((q) => q.syncError != null).length);

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

  // ---------- bibliothèque ----------
  /// Modifie une fiche de la bibliothèque (à synchroniser).
  void editLibrary(Syncable item, VoidCallback change) => mutate(() {
        change();
        item.markEdited();
      });

  WorkItem addWorkItem({String name = 'Nouvel ouvrage'}) {
    final w = WorkItem(id: newId(), name: name);
    editLibrary(w, () => data.workItems.add(w));
    return w;
  }

  WorkItem duplicateWorkItem(WorkItem src) {
    final w = WorkItem.fromJson({...src.toJson(), 'id': newId(), 'sv': null, 'dirty': true})
      ..name = '${src.name} (copie)'
      ..code = '';
    editLibrary(w, () => data.workItems.add(w));
    return w;
  }

  MaterialItem addMaterial() {
    final m = MaterialItem(id: newId(), name: 'Nouveau matériau');
    editLibrary(m, () => data.materials.add(m));
    return m;
  }

  Supplier addSupplier() {
    final x = Supplier(id: newId(), name: 'Nouveau fournisseur');
    editLibrary(x, () => data.suppliers.add(x));
    return x;
  }

  /// Suppression d'une fiche de la bibliothèque (envoyée au serveur si elle y est connue).
  void deleteLibrary(Syncable item) => mutate(() {
        if (item.serverVersion == null) {
          data.workItems.remove(item);
          data.materials.remove(item);
          data.suppliers.remove(item);
        } else {
          item
            ..deleted = true
            ..markEdited();
        }
      });

  void addTemplate(String trade) => mutate(() {
        for (final t in kPriceTemplates[trade] ?? const <Template>[]) {
          data.workItems.add(WorkItem(
            id: newId(),
            name: t.$1,
            description: t.$2,
            unit: t.$3,
            base: t.$4,
            countKey: t.$5,
            category: t.$6,
          ));
        }
      });

  // ---------- devis ----------
  /// TVA par défaut des nouvelles lignes : taux de l'entreprise (paramétrable dans le profil).
  int get defaultVatBp => (company.vatPercent * 100).round();

  Quote draftQuoteFor(Project p) {
    for (final q in p.quotes) {
      if (q.status == QuoteStatus.draft && !q.legacy) return q;
    }
    return createQuote(p);
  }

  Quote createQuote(Project p) {
    final q = Quote(id: newId(), date: DateTime.now(), validityDays: company.validityDays);
    mutate(() => p.quotes.add(q), touch: p, quote: q);
    return q;
  }

  /// Nouvelle version d'un devis figé : brouillon v+1 dont les quantités suivent à nouveau le métré.
  /// La version d'origine, si elle n'a pas reçu de réponse, est marquée « remplacée ».
  Quote newVersion(Project p, Quote from) {
    final versions = p.quotes.where((x) => x.estimateId == from.estimateId);
    final next = versions.fold<int>(0, (m, x) => x.versionNo > m ? x.versionNo : m) + 1;
    final q = Quote(
      id: newId(),
      estimateId: from.legacy ? null : from.estimateId,
      versionNo: from.legacy ? 1 : next,
      date: DateTime.now(),
      title: from.title,
      validityDays: from.validityDays,
      currency: from.currency,
      exchangeRateE4: from.exchangeRateE4,
      exchangeRateDate: from.exchangeRateDate,
      exchangeRateSource: from.exchangeRateSource,
      discountBp: from.discountBp,
      overheadBp: from.overheadBp,
      marginBp: from.marginBp,
      depositBp: from.depositBp,
      lines: [for (final l in from.lines) l.copyWith(id: newId())],
    );
    mutate(() {
      p.quotes.add(q);
      if (!from.legacy && (from.status == QuoteStatus.validated || from.status == QuoteStatus.sent)) {
        from
          ..status = QuoteStatus.superseded
          ..markEdited();
      }
    }, touch: p, quote: q);
    return q;
  }

  void editQuote(Project p, Quote q, VoidCallback change) => mutate(change, touch: p, quote: q);

  QuoteLine _line(WorkItem w) {
    final l = lineFrom(w, newId())..vatRateBp = defaultVatBp;
    if (w.labourCostCents != null && w.salePriceCents == null) {
      // Ouvrage défini par son coût : prix calculé (fournitures + main-d'œuvre, frais et marge).
      l
        ..pricing = 'cost_plus'
        ..labourCostCents = w.labourCostCents
        ..materialCostCents = _componentsCost(w)
        ..priceMissing = false;
    }
    l
      ..sourcePriceCents = w.salePriceCents
      ..sourceCurrency = w.currency;
    return l;
  }

  /// Coût des fournitures d'un ouvrage : Σ quantité × prix d'achat (connu des seuls administrateurs).
  int? _componentsCost(WorkItem w) {
    var total = 0;
    for (final c in w.components) {
      final m = material(c['material_id'] as String?);
      final price = m?.purchasePriceCents;
      if (price == null) return null;
      total += ((c['quantity_per_unit'] as num).toDouble() * price).round();
    }
    return w.components.isEmpty ? null : total;
  }

  void addLineFromWorkItem(Project p, Quote q, WorkItem w) => editQuote(p, q, () {
        final l = _line(w);
        if (q.currency == 'EUR') _convertLine(l, q);
        q.lines.add(l);
      });

  void addFreeLine(Project p, Quote q) => editQuote(
        p,
        q,
        () => q.lines.add(QuoteLine(
          id: newId(),
          label: 'Ligne libre',
          unit: 'forfait',
          quantity: 1,
          manual: true,
          priceMissing: true,
          vatRateBp: defaultVatBp,
        )),
      );

  void moveLine(Project p, Quote q, int index, int delta) {
    final j = index + delta;
    if (j < 0 || j >= q.lines.length) return;
    editQuote(p, q, () {
      final l = q.lines.removeAt(index);
      q.lines.insert(j, l);
    });
  }

  /// Prix d'une ligne converti depuis son prix d'origine en MAD (taux : MAD pour 1 EUR × 10 000).
  void _convertLine(QuoteLine l, Quote q) {
    final rate = q.exchangeRateE4;
    if (l.sourceCurrency != 'MAD' || l.sourcePriceCents == null || rate == null || rate <= 0) return;
    l
      ..unitPriceCents = (l.sourcePriceCents! * 10000 + rate ~/ 2) ~/ rate
      ..priceMissing = false;
  }

  /// Change la devise d'un brouillon. Les lignes issues de la bibliothèque en MAD sont converties
  /// au taux saisi ; les lignes libres gardent leur prix (à vérifier par l'utilisateur).
  void setCurrency(Project p, Quote q, String currency, {int? rateE4, DateTime? rateDate, String rateSource = ''}) =>
      editQuote(p, q, () {
        q
          ..currency = currency
          ..exchangeRateE4 = currency == 'EUR' ? rateE4 : null
          ..exchangeRateDate = currency == 'EUR' ? rateDate : null
          ..exchangeRateSource = currency == 'EUR' ? rateSource : '';
        for (final l in q.lines) {
          if (l.sourcePriceCents == null || l.sourceCurrency != 'MAD') continue;
          if (currency == 'EUR') {
            _convertLine(l, q);
          } else {
            l.unitPriceCents = l.sourcePriceCents!;
          }
        }
      });

  /// Raisons empêchant la validation (vide = validable).
  List<String> validationProblems(Project p, Quote q, {required bool isAdmin}) => [
        if (!isAdmin) 'Seul un administrateur peut valider un devis.',
        if (q.lines.isEmpty) 'Le devis n\'a aucune ligne.',
        if (q.lines.any((l) => lineUnitPriceCents(q, l) == null)) 'Des lignes n\'ont pas de prix.',
        if (q.currency == 'EUR' && (q.exchangeRateE4 == null || q.exchangeRateDate == null))
          'Indiquez le taux de change et sa date.',
        if (q.lines.any((l) => !l.manual && l.base != QuantityBase.free) && metreState(p) != MetreState.validated)
          'Le métré doit être validé (et à jour) avant le devis.',
        if (!company.hasValidIce) 'Renseignez l\'ICE de l\'entreprise (15 chiffres) dans le profil.',
      ];

  /// Validation : quantités figées, empreinte du métré enregistrée. Le numéro est attribué par le serveur.
  void validateQuote(Project p, Quote q, {required String userId}) => editQuote(p, q, () {
        final m = projectMeasures(p);
        for (final l in q.lines) {
          l.frozenQuantity = lineQuantity(p, l, measures: m);
        }
        q
          ..metreFingerprint = metreFingerprint(p)
          ..validatedAt = DateTime.now()
          ..validatedBy = userId
          ..status = QuoteStatus.validated;
      });

  void markSent(Project p, Quote q) => editQuote(p, q, () {
        q
          ..status = QuoteStatus.sent
          ..sentAt = DateTime.now();
      });

  void decide(Project p, Quote q, {required bool accepted, String note = ''}) => editQuote(p, q, () {
        q
          ..status = accepted ? QuoteStatus.accepted : QuoteStatus.refused
          ..decidedAt = DateTime.now()
          ..decisionNote = note;
      });

  /// Suppression d'un brouillon jamais envoyé au serveur.
  void deleteLocalDraft(Project p, Quote q) {
    if (q.status != QuoteStatus.draft || q.serverVersion != null) return;
    mutate(() => p.quotes.remove(q), touch: p);
  }
}
