// Données de référence UNIQUEMENT pour les tests (cas « M. Benali », 5 pièces).
// Elles ne sont jamais embarquées dans l'application.

import 'package:lamaalam/data/templates.dart';
import 'package:lamaalam/domain/calculations.dart';
import 'package:lamaalam/domain/models.dart';

Room _room(String id, String name, double l, double w, double h, int doors, int windows) => Room.rectangle(
      id: id,
      name: name,
      length: l,
      width: w,
      height: h,
      openings: [
        for (var i = 0; i < doors; i++) Opening.standard('$id-d$i', OpeningType.door),
        for (var i = 0; i < windows; i++) Opening.standard('$id-w$i', OpeningType.window),
      ],
    );

List<Room> referenceRooms() => [
      _room('r1', 'Salon', 5.2, 4.1, 2.8, 1, 2),
      _room('r2', 'Chambre', 3.8, 3.4, 2.8, 1, 1),
      _room('r3', 'Cuisine', 3.1, 2.6, 2.8, 1, 1),
      _room('r4', 'Salle de bain', 2.4, 1.9, 2.6, 1, 0),
      _room('r5', 'Couloir', 4.0, 1.2, 2.8, 0, 0),
    ];

List<WorkItem> samplePrestations() => [
      WorkItem(id: 'pm', name: 'Peinture murs', description: '2 couches, enduit compris', unit: unitCode('m²'), base: QuantityBase.walls, salePriceCents: 4500),
      WorkItem(id: 'pp', name: 'Peinture plafond', description: '2 couches', unit: unitCode('m²'), base: QuantityBase.ceiling, salePriceCents: 5000),
      WorkItem(id: 'cs', name: 'Carrelage sol', description: 'fourni et posé', unit: unitCode('m²'), base: QuantityBase.floor, salePriceCents: 28000),
      WorkItem(id: 'pl', name: 'Plinthes', description: 'carrelage assorti', unit: unitCode('ml'), base: QuantityBase.skirting, salePriceCents: 6000),
      WorkItem(id: 'fp', name: 'Faux plafond plâtre', description: 'plaques BA13 sur ossature', unit: unitCode('m²'), base: QuantityBase.ceiling, salePriceCents: 22000),
      WorkItem(id: 'dp', name: 'Dépose ancien revêtement', description: 'évacuation des gravats', unit: unitCode('m²'), base: QuantityBase.floor, salePriceCents: 4000),
      WorkItem(id: 'ne', name: 'Nettoyage fin de chantier', unit: unitCode('forfait'), base: QuantityBase.free, salePriceCents: 80000),
    ];

void _freeze(Project p, Quote q) {
  final m = projectMeasures(p);
  for (final l in q.lines) {
    l.frozenQuantity = lineQuantity(p, l, measures: m);
  }
}

AppData sampleData() {
  final pres = samplePrestations();
  WorkItem byId(String id) => pres.firstWhere((p) => p.id == id);
  final now = DateTime.now();

  final p1 = Project(
    id: 'p1',
    legacyClientName: 'M. Benali (exemple)',
    legacyClientPhone: '0661234567',
    address: 'Appartement, quartier Maârif',
    city: 'Casablanca',
    notes: 'Client présent le samedi. Carrelage gris clair souhaité.',
    rooms: referenceRooms(),
    updatedAt: now,
    quotes: [
      Quote(
        id: 'q1',
        number: 'DV-${now.year}-0003',
        date: now,
        lines: [for (final id in ['pm', 'pp', 'cs', 'pl']) lineFrom(byId(id), 'q1-$id')],
      ),
    ],
  );

  final p2 = Project(
    id: 'p2',
    legacyClientName: 'Mme Alaoui (exemple)',
    legacyClientPhone: '0670112233',
    address: 'Villa, Agdal',
    city: 'Rabat',
    updatedAt: now.subtract(const Duration(days: 11)),
    rooms: [_room('r6', 'Salon', 6.0, 4.5, 3.0, 1, 3), _room('r7', 'Chambre', 4.0, 3.5, 3.0, 1, 1)],
    quotes: [
      Quote(
        id: 'q2',
        number: 'DV-${now.year}-0001',
        date: now.subtract(const Duration(days: 11)),
        status: QuoteStatus.accepted,
        discountBp: 500,
        lines: [for (final id in ['pm', 'pp']) lineFrom(byId(id), 'q2-$id')],
      ),
    ],
  );

  final p3 = Project(
    id: 'p3',
    legacyClientName: 'Riad Dar Zitoun (exemple)',
    legacyClientPhone: '0524445566',
    address: 'Médina, derb Dabachi',
    city: 'Marrakech',
    notes: "Programme de mise à niveau, 4 chambres d'hôtes.",
    updatedAt: now.subtract(const Duration(days: 5)),
    rooms: [_room('r8', 'Chambre', 4.2, 3.6, 3.2, 1, 1), _room('r9', 'Chambre', 4.0, 3.4, 3.2, 1, 1)],
    quotes: [
      Quote(
        id: 'q3',
        number: 'DV-${now.year}-0002',
        date: now.subtract(const Duration(days: 5)),
        status: QuoteStatus.sent,
        depositBp: 4000,
        lines: [for (final id in ['pm', 'fp']) lineFrom(byId(id), 'q3-$id')],
      ),
    ],
  );
  _freeze(p2, p2.quotes.first);
  _freeze(p3, p3.quotes.first);

  return AppData(
    company: Company(
      name: 'Atelier Benjelloun Rénovation (exemple)',
      phone: '0522 00 00 00',
      address: '12 rue Ibn Battouta',
      city: 'Casablanca',
      ice: '001234567000089',
      ifNumber: '40123456',
      rc: '512345',
      patente: '34567890',
      footer: 'Devis gratuit. Acompte à la commande, solde à la réception des travaux.',
    ),
    workItems: pres,
    projects: [p1, p2, p3],
    quoteCounter: 3,
  );
}

