import '../domain/calculations.dart';
import '../domain/models.dart';

/// Données d'exemple : elles reprennent le cas de test de référence du cahier des charges
/// (projet M. Benali, 5 pièces : 27 989 MAD HT, 33 587 MAD TTC).
/// Elles sont clairement marquées « exemple » et peuvent être effacées depuis le profil.

Room _room(String id, String name, double l, double w, double h, int doors, int windows) => Room(
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

List<Prestation> samplePrestations() => [
      Prestation(id: 'pm', name: 'Peinture murs', description: '2 couches, enduit compris', unit: 'm²', base: QuantityBase.walls, unitPriceCents: 4500),
      Prestation(id: 'pp', name: 'Peinture plafond', description: '2 couches', unit: 'm²', base: QuantityBase.ceiling, unitPriceCents: 5000),
      Prestation(id: 'cs', name: 'Carrelage sol', description: 'fourni et posé', unit: 'm²', base: QuantityBase.floor, unitPriceCents: 28000),
      Prestation(id: 'pl', name: 'Plinthes', description: 'carrelage assorti', unit: 'ml', base: QuantityBase.skirting, unitPriceCents: 6000),
      Prestation(id: 'fp', name: 'Faux plafond plâtre', description: 'plaques BA13 sur ossature', unit: 'm²', base: QuantityBase.ceiling, unitPriceCents: 22000),
      Prestation(id: 'dp', name: 'Dépose ancien revêtement', description: 'évacuation des gravats', unit: 'm²', base: QuantityBase.floor, unitPriceCents: 4000),
      Prestation(id: 'ne', name: 'Nettoyage fin de chantier', unit: 'forfait', base: QuantityBase.free, unitPriceCents: 80000),
    ];

QuoteLine lineFrom(Prestation p, String id) => QuoteLine(
      id: id,
      prestationId: p.id,
      label: p.name,
      description: p.description,
      unit: p.unit,
      base: p.base,
      quantity: p.base == QuantityBase.free ? 1 : 0,
      unitPriceCents: p.unitPriceCents,
    );

void _freeze(Project p, Quote q) {
  final m = projectMeasures(p);
  for (final l in q.lines) {
    l.frozenQuantity = lineQuantity(p, l, measures: m);
  }
}

AppData sampleData() {
  final pres = samplePrestations();
  Prestation byId(String id) => pres.firstWhere((p) => p.id == id);
  final now = DateTime.now();

  final p1 = Project(
    id: 'p1',
    client: 'M. Benali (exemple)',
    phone: '0661234567',
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
    client: 'Mme Alaoui (exemple)',
    phone: '0670112233',
    address: 'Villa, Agdal',
    city: 'Rabat',
    synced: true,
    updatedAt: now.subtract(const Duration(days: 11)),
    rooms: [_room('r6', 'Salon', 6.0, 4.5, 3.0, 1, 3), _room('r7', 'Chambre', 4.0, 3.5, 3.0, 1, 1)],
    quotes: [
      Quote(
        id: 'q2',
        number: 'DV-${now.year}-0001',
        date: now.subtract(const Duration(days: 11)),
        status: QuoteStatus.accepted,
        discountPercent: 5,
        lines: [for (final id in ['pm', 'pp']) lineFrom(byId(id), 'q2-$id')],
      ),
    ],
  );

  final p3 = Project(
    id: 'p3',
    client: 'Riad Dar Zitoun (exemple)',
    phone: '0524445566',
    address: 'Médina, derb Dabachi',
    city: 'Marrakech',
    notes: "Programme de mise à niveau, 4 chambres d'hôtes.",
    synced: true,
    updatedAt: now.subtract(const Duration(days: 5)),
    rooms: [_room('r8', 'Chambre', 4.2, 3.6, 3.2, 1, 1), _room('r9', 'Chambre', 4.0, 3.4, 3.2, 1, 1)],
    quotes: [
      Quote(
        id: 'q3',
        number: 'DV-${now.year}-0002',
        date: now.subtract(const Duration(days: 5)),
        status: QuoteStatus.sent,
        depositPercent: 40,
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
    prestations: pres,
    projects: [p1, p2, p3],
    quoteCounter: 3,
  );
}

/// Grilles modèles par métier (E8). Les prix sont à zéro : l'artisan les complète.
const Map<String, List<(String, String, String, QuantityBase)>> kPriceTemplates = {
  'Peinture': [
    ('Peinture murs', '2 couches', 'm²', QuantityBase.walls),
    ('Peinture plafond', '2 couches', 'm²', QuantityBase.ceiling),
    ('Enduit de rebouchage', '', 'm²', QuantityBase.walls),
  ],
  'Carrelage': [
    ('Carrelage sol', 'fourni et posé', 'm²', QuantityBase.floor),
    ('Plinthes', 'assorties', 'ml', QuantityBase.skirting),
    ('Faïence murale', '', 'm²', QuantityBase.free),
  ],
  'Plâtre et faux plafond': [
    ('Faux plafond BA13', 'sur ossature', 'm²', QuantityBase.ceiling),
    ('Corniche plâtre', '', 'ml', QuantityBase.skirting),
  ],
  'Plomberie simple': [
    ('Remplacement robinetterie', '', 'u', QuantityBase.free),
    ('Pose lavabo', '', 'u', QuantityBase.free),
  ],
  'Électricité simple': [
    ('Point lumineux', '', 'u', QuantityBase.free),
    ('Prise de courant', '', 'u', QuantityBase.free),
  ],
  'Rénovation générale': [
    ('Dépose et évacuation', '', 'm²', QuantityBase.floor),
    ('Nettoyage fin de chantier', '', 'forfait', QuantityBase.free),
  ],
};
