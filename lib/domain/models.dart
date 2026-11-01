// Modèle de données du MVP (cahier des charges, section « Modèle de données »).
// Les objets sont volontairement mutables : l'état est centralisé dans AppState,
// qui sauvegarde et notifie l'interface après chaque modification.

enum QuoteStatus { draft, sent, accepted, refused }

/// Base de quantité d'un ouvrage ou d'une ligne de devis.
/// [walls] = murs nets d'ouvertures ; [count] = élément compté pièce par pièce ([QuoteLine.countKey]) ;
/// [free] = quantité saisie.
enum QuantityBase { floor, ceiling, walls, wallsGross, skirting, perimeter, volume, doors, windows, count, free }

/// Codes partagés avec le serveur (backend/app/models.py, QUANTITY_BASES).
const Map<QuantityBase, String> kBaseCodes = {
  QuantityBase.floor: 'floor',
  QuantityBase.ceiling: 'ceiling',
  QuantityBase.walls: 'walls_net',
  QuantityBase.wallsGross: 'walls_gross',
  QuantityBase.skirting: 'skirting',
  QuantityBase.perimeter: 'perimeter',
  QuantityBase.volume: 'volume',
  QuantityBase.doors: 'doors',
  QuantityBase.windows: 'windows',
  QuantityBase.count: 'count',
  QuantityBase.free: 'manual',
};

QuantityBase baseFromCode(Object? code) =>
    kBaseCodes.entries.firstWhere((e) => e.value == code, orElse: () => const MapEntry(QuantityBase.free, 'manual')).key;

/// Unités explicites (codes serveur → libellés).
const Map<String, String> kUnitLabels = {
  'm': 'm',
  'm2': 'm²',
  'm3': 'm³',
  'kg': 'kg',
  'l': 'l',
  'u': 'u',
  'forfait': 'forfait',
};

/// Libellé d'unité → code (reprise des données Qiyas : « m² », « ml »…).
String unitCode(String unit) => switch (unit.trim()) {
      'm²' || 'm2' => 'm2',
      'ml' || 'm' => 'm',
      'm³' || 'm3' => 'm3',
      'kg' => 'kg',
      'l' || 'litre' => 'l',
      'forfait' || 'ff' => 'forfait',
      _ => 'u',
    };

/// Catégories (lots) de la bibliothèque et du métré.
const Map<String, String> kCategories = {
  'floor': 'Sols',
  'wall': 'Murs',
  'ceiling': 'Plafonds',
  'joinery': 'Menuiseries',
  'electricity': 'Électricité',
  'plumbing': 'Plomberie',
  'masonry': 'Maçonnerie',
  'other': 'Autre',
};

/// Éléments comptés dans chaque pièce : (catégorie, libellé, unité).
const Map<String, (String, String, String)> kCountItems = {
  'prises': ('electricity', 'Prises', 'u'),
  'interrupteurs': ('electricity', 'Interrupteurs', 'u'),
  'points_lumineux': ('electricity', 'Points lumineux', 'u'),
  'points_eau': ('plumbing', 'Points d\'eau', 'u'),
  'evacuations': ('plumbing', 'Évacuations', 'u'),
  'sanitaires': ('plumbing', 'Appareils sanitaires', 'u'),
  'placards': ('joinery', 'Placards', 'u'),
  'cloisons_m2': ('masonry', 'Cloisons à créer', 'm2'),
  'demolition_m2': ('masonry', 'Démolitions', 'm2'),
  'reprises_m2': ('masonry', 'Reprises de maçonnerie', 'm2'),
  'ouvertures_a_creer': ('masonry', 'Ouvertures à créer', 'u'),
};

enum OpeningType { door, window }

const double kDoorWidth = 0.83;
const double kDoorHeight = 2.04;
const double kWindowWidth = 1.20;
const double kWindowHeight = 1.25;

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

double _d(Object? v, [double fallback = 0]) => v is num ? v.toDouble() : fallback;
int _i(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
String _s(Object? v, [String fallback = '']) => v is String ? v : fallback;
List<String> _strings(Object? v) => v is List ? v.whereType<String>().toList() : <String>[];

class Company {
  Company({
    this.name = '',
    this.phone = '',
    this.address = '',
    this.city = '',
    this.ice = '',
    this.ifNumber = '',
    this.rc = '',
    this.patente = '',
    this.vatPercent = 20,
    this.validityDays = 30,
    this.footer = '',
    this.logoPath,
  });

  String name;
  String phone;
  String address;
  String city;
  String ice;
  String ifNumber;
  String rc;
  String patente;
  double vatPercent;
  int validityDays;
  String footer;
  String? logoPath;

  bool get hasValidIce => RegExp(r'^\d{15}$').hasMatch(ice);

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'address': address,
        'city': city,
        'ice': ice,
        'if': ifNumber,
        'rc': rc,
        'patente': patente,
        'vat': vatPercent,
        'validity': validityDays,
        'footer': footer,
        'logo': logoPath,
      };

  factory Company.fromJson(Map<String, dynamic> j) => Company(
        name: _s(j['name']),
        phone: _s(j['phone']),
        address: _s(j['address']),
        city: _s(j['city']),
        ice: _s(j['ice']),
        ifNumber: _s(j['if']),
        rc: _s(j['rc']),
        patente: _s(j['patente']),
        vatPercent: _d(j['vat'], 20),
        validityDays: _i(j['validity'], 30),
        footer: _s(j['footer']),
        logoPath: j['logo'] as String?,
      );
}

int? _iOrNull(Object? v) => v is num ? v.toInt() : null;

/// Ouvrage de la bibliothèque (table work_items). Un prix null = « prix à renseigner ».
class WorkItem with Syncable {
  WorkItem({
    required this.id,
    required this.name,
    this.code = '',
    this.category = 'other',
    this.description = '',
    this.unit = 'u',
    this.base = QuantityBase.free,
    this.countKey,
    this.wasteRateBp = 0,
    this.labourCostCents,
    this.salePriceCents,
    this.currency = 'MAD',
    List<Map<String, dynamic>>? components,
    this.active = true,
    this.priceNote = '',
  }) : components = components ?? [];

  final String id;
  String code;
  String category;
  String name;
  String description;

  /// Code d'unité (voir [kUnitLabels]).
  String unit;
  QuantityBase base;
  String? countKey;

  /// Taux de perte en points de base (1000 = 10 %). 0 par défaut, jamais implicite.
  int wasteRateBp;
  int? labourCostCents;
  int? salePriceCents;
  String currency;
  List<Map<String, dynamic>> components;
  bool active;

  /// Source du dernier prix (devis fournisseur…), enregistrée dans l'historique des prix.
  String priceNote;

  String get unitLabel => kUnitLabels[unit] ?? unit;

  Map<String, dynamic> toServer() => {
        'code': code.trim(),
        'category': category,
        'name': name.trim(),
        'description': description.trim(),
        'unit': unit,
        'quantity_basis': kBaseCodes[base],
        'count_key': base == QuantityBase.count ? countKey : null,
        'waste_rate_bp': wasteRateBp,
        'labour_cost_cents': labourCostCents,
        'sale_price_cents': salePriceCents,
        'currency': currency,
        'components': components,
        'is_active': active,
        'price_note': priceNote.trim(),
      };

  void applyServer(Map<String, dynamic> d) {
    code = _s(d['code']);
    category = _s(d['category'], 'other');
    name = _s(d['name']);
    description = _s(d['description']);
    unit = _s(d['unit'], 'u');
    base = baseFromCode(d['quantity_basis']);
    countKey = d['count_key'] as String?;
    wasteRateBp = _i(d['waste_rate_bp']);
    labourCostCents = _iOrNull(d['labour_cost_cents']);
    salePriceCents = _iOrNull(d['sale_price_cents']);
    currency = _s(d['currency'], 'MAD');
    components = [for (final c in d['components'] as List? ?? const []) Map<String, dynamic>.from(c as Map)];
    active = d['is_active'] != false;
    priceNote = _s(d['price_note']);
  }

  Map<String, dynamic> toJson() => {'id': id, ...toServer(), ...syncJson()};

  factory WorkItem.fromJson(Map<String, dynamic> j) => WorkItem(id: _s(j['id']), name: '')
    ..applyServer(j)
    ..readSync(j);

  /// Reprise d'une « prestation » Qiyas (prix 0 = non renseigné).
  factory WorkItem.fromLegacy(Map<String, dynamic> j) {
    final legacyBase = _s(j['base']);
    final pu = _i(j['pu']);
    return WorkItem(
      id: _s(j['id']),
      name: _s(j['name']),
      description: _s(j['desc']),
      unit: unitCode(_s(j['unit'], 'u')),
      base: _enumByName(QuantityBase.values, legacyBase, QuantityBase.free),
      salePriceCents: pu > 0 ? pu : null,
      active: j['active'] != false,
      priceNote: pu > 0 ? 'Prix repris de Qiyas' : '',
    );
  }
}

/// Matériau ou fourniture (table materials). Le prix d'achat n'est connu que des administrateurs.
class MaterialItem with Syncable {
  MaterialItem({
    required this.id,
    required this.name,
    this.supplierId,
    this.category = 'other',
    this.brand = '',
    this.reference = '',
    this.unit = 'u',
    this.packSize,
    this.wasteRateBp = 0,
    this.purchasePriceCents,
    this.salePriceCents,
    this.currency = 'MAD',
    this.city = '',
    this.priceNote = '',
  });

  final String id;
  String? supplierId;
  String category;
  String name;
  String brand;
  String reference;
  String unit;
  double? packSize;
  int wasteRateBp;
  int? purchasePriceCents;
  int? salePriceCents;
  String currency;
  String city;
  String priceNote;

  String get unitLabel => kUnitLabels[unit] ?? unit;

  Map<String, dynamic> toServer() => {
        'supplier_id': supplierId,
        'category': category,
        'name': name.trim(),
        'brand': brand.trim(),
        'reference': reference.trim(),
        'unit': unit,
        'pack_size': packSize,
        'waste_rate_bp': wasteRateBp,
        'purchase_price_cents': purchasePriceCents,
        'sale_price_cents': salePriceCents,
        'currency': currency,
        'city': city.trim(),
        'price_note': priceNote.trim(),
      };

  void applyServer(Map<String, dynamic> d) {
    supplierId = d['supplier_id'] as String?;
    category = _s(d['category'], 'other');
    name = _s(d['name']);
    brand = _s(d['brand']);
    reference = _s(d['reference']);
    unit = _s(d['unit'], 'u');
    packSize = (d['pack_size'] as num?)?.toDouble();
    wasteRateBp = _i(d['waste_rate_bp']);
    purchasePriceCents = _iOrNull(d['purchase_price_cents']);
    salePriceCents = _iOrNull(d['sale_price_cents']);
    currency = _s(d['currency'], 'MAD');
    city = _s(d['city']);
    priceNote = _s(d['price_note']);
  }

  Map<String, dynamic> toJson() => {'id': id, ...toServer(), ...syncJson()};

  factory MaterialItem.fromJson(Map<String, dynamic> j) => MaterialItem(id: _s(j['id']), name: '')
    ..applyServer(j)
    ..readSync(j);
}

class Supplier with Syncable {
  Supplier({
    required this.id,
    required this.name,
    this.contactName = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.city = '',
    this.ice = '',
    this.notes = '',
  });

  final String id;
  String name;
  String contactName;
  String phone;
  String email;
  String address;
  String city;
  String ice;
  String notes;

  Map<String, dynamic> toServer() => {
        'name': name.trim(),
        'contact_name': contactName.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'address': address.trim(),
        'city': city.trim(),
        'ice': ice.trim(),
        'notes': notes.trim(),
      };

  void applyServer(Map<String, dynamic> d) {
    name = _s(d['name']);
    contactName = _s(d['contact_name']);
    phone = _s(d['phone']);
    email = _s(d['email']);
    address = _s(d['address']);
    city = _s(d['city']);
    ice = _s(d['ice']);
    notes = _s(d['notes']);
  }

  Map<String, dynamic> toJson() => {'id': id, ...toServer(), ...syncJson()};

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(id: _s(j['id']), name: '')
    ..applyServer(j)
    ..readSync(j);
}

/// Origine d'une cote (docs/ARCHITECTURE.md §5).
abstract final class MeasureSource {
  /// Saisie par l'utilisateur (mètre, télémètre lu à l'écran) : cote vérifiée.
  static const manual = 'manual';

  /// Reçue d'un télémètre connecté : cote vérifiée.
  static const laser = 'laser';

  /// Valeur standard proposée par l'application : cote estimée, à vérifier.
  static const standard = 'default';

  static const all = [manual, laser, standard];

  static bool verified(String source) => source != standard;
}

double _clampAngle(double a) => a.isFinite && a > 0 && a < 360 ? a : 90;

class Wall {
  Wall({required this.id, required this.length, this.lengthSource = MeasureSource.manual, this.angle = 90});

  final String id;
  double length;
  String lengthSource;

  /// Angle intérieur au coin qui termine ce mur, en degrés (90 par défaut, 270 si rentrant).
  double angle;

  Map<String, dynamic> toJson() => {'id': id, 'length': length, 'length_source': lengthSource, 'angle': angle};

  factory Wall.fromJson(Map<String, dynamic> j) => Wall(
        id: _s(j['id']),
        length: _d(j['length']),
        lengthSource: _s(j['length_source'], MeasureSource.manual),
        angle: _clampAngle(_d(j['angle'], 90)),
      );
}

class Opening {
  Opening({
    required this.id,
    required this.type,
    required this.width,
    required this.height,
    this.wallIndex = 0,
    this.widthSource = MeasureSource.manual,
    this.heightSource = MeasureSource.manual,
  });

  /// Dimensions standard, marquées « à vérifier » tant qu'elles ne sont pas mesurées.
  factory Opening.standard(String id, OpeningType type, {int wallIndex = 0}) => Opening(
        id: id,
        type: type,
        wallIndex: wallIndex,
        width: type == OpeningType.door ? kDoorWidth : kWindowWidth,
        height: type == OpeningType.door ? kDoorHeight : kWindowHeight,
        widthSource: MeasureSource.standard,
        heightSource: MeasureSource.standard,
      );

  final String id;
  OpeningType type;
  int wallIndex;
  double width;
  double height;
  String widthSource;
  String heightSource;

  double get area => width * height;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'wall': wallIndex,
        'width': width,
        'height': height,
        'width_source': widthSource,
        'height_source': heightSource,
      };

  factory Opening.fromJson(Map<String, dynamic> j) => Opening(
        id: _s(j['id']),
        type: _enumByName(OpeningType.values, j['type'], OpeningType.door),
        wallIndex: _i(j['wall']),
        width: _d(j['width'] ?? j['w']),
        height: _d(j['height'] ?? j['h']),
        // Ouvertures Qiyas : dimensions standard jamais confirmées.
        widthSource: _s(j['width_source'], j.containsKey('w') ? MeasureSource.standard : MeasureSource.manual),
        heightSource: _s(j['height_source'], j.containsKey('h') ? MeasureSource.standard : MeasureSource.manual),
      );
}

/// Pièce décrite mur par mur. Partagée avec le serveur (table rooms).
class Room with Syncable {
  Room({
    required this.id,
    required this.name,
    required this.height,
    this.heightSource = MeasureSource.manual,
    List<Wall>? walls,
    List<Opening>? openings,
    List<String>? photoPaths,
    Map<String, double>? counts,
    this.level = 'RDC',
    this.planX,
    this.planY,
  })  : walls = walls ?? [],
        openings = openings ?? [],
        photoPaths = photoPaths ?? [],
        counts = counts ?? {};

  /// Pièce rectangulaire : 4 murs (longueur, largeur, longueur, largeur) à angle droit.
  /// Les ouvertures sans mur désigné sont réparties sur les murs dans l'ordre.
  factory Room.rectangle({
    required String id,
    required String name,
    required double length,
    required double width,
    required double height,
    List<Opening>? openings,
    String source = MeasureSource.manual,
  }) {
    final ops = openings ?? [];
    for (var i = 0; i < ops.length; i++) {
      ops[i].wallIndex = i % 4;
    }
    return Room(
      id: id,
      name: name,
      height: height,
      heightSource: source,
      walls: [
        for (var i = 0; i < 4; i++) Wall(id: '$id-w$i', length: i.isEven ? length : width, lengthSource: source),
      ],
      openings: ops,
    );
  }

  final String id;
  String name;
  String level;
  double height;
  String heightSource;
  List<Wall> walls;
  List<Opening> openings;
  List<String> photoPaths;

  /// Éléments comptés dans la pièce (clés de [kCountItems]) : prises, points d'eau…
  Map<String, double> counts;
  double? planX;
  double? planY;

  bool get isRectangle =>
      walls.length == 4 &&
      walls.every((w) => w.angle == 90) &&
      walls[0].length == walls[2].length &&
      walls[1].length == walls[3].length;

  /// Longueur et largeur pour une pièce rectangulaire (murs 1 et 2).
  double get length => walls.isEmpty ? 0 : walls[0].length;
  double get width => walls.length < 2 ? 0 : walls[1].length;

  int get doorCount => openings.where((o) => o.type == OpeningType.door).length;
  int get windowCount => openings.where((o) => o.type == OpeningType.window).length;

  /// Nombre de cotes encore à la valeur standard (à vérifier sur place).
  int get unverifiedCount =>
      (MeasureSource.verified(heightSource) ? 0 : 1) +
      walls.where((w) => !MeasureSource.verified(w.lengthSource)).length +
      openings.fold<int>(0, (n, o) => n + (MeasureSource.verified(o.widthSource) ? 0 : 1) + (MeasureSource.verified(o.heightSource) ? 0 : 1));

  Map<String, dynamic> toServer(String projectId) => {
        'project_id': projectId,
        'name': name.trim(),
        'level_name': level,
        'height_m': height,
        'height_source': heightSource,
        'walls': [for (final w in walls) w.toJson()],
        'openings': [for (final o in openings) o.toJson()],
        'plan_x': planX,
        'plan_y': planY,
        'counts': {for (final e in counts.entries) if (e.value > 0) e.key: e.value},
      };

  void applyServer(Map<String, dynamic> d) {
    counts = {
      for (final e in (d['counts'] as Map? ?? const {}).entries)
        if (kCountItems.containsKey(e.key) && e.value is num) e.key as String: (e.value as num).toDouble(),
    };
    name = _s(d['name']);
    level = _s(d['level_name'], 'RDC');
    height = _d(d['height_m'], 2.8);
    heightSource = _s(d['height_source'], MeasureSource.manual);
    walls = [for (final w in d['walls'] as List? ?? const []) Wall.fromJson(Map<String, dynamic>.from(w as Map))];
    openings = [for (final o in d['openings'] as List? ?? const []) Opening.fromJson(Map<String, dynamic>.from(o as Map))];
    planX = (d['plan_x'] as num?)?.toDouble();
    planY = (d['plan_y'] as num?)?.toDouble();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        ...toServer(''),
        'photos': photoPaths,
        ...syncJson(),
      };

  factory Room.fromJson(Map<String, dynamic> j) {
    if (!j.containsKey('walls') && j.containsKey('L')) {
      // Format Qiyas : pièce rectangulaire, hauteur saisie, ouvertures sans mur désigné.
      return Room.rectangle(
        id: _s(j['id']),
        name: _s(j['name']),
        length: _d(j['L']),
        width: _d(j['W']),
        height: _d(j['H'], 2.8),
        openings: [for (final o in j['openings'] as List? ?? const []) Opening.fromJson(Map<String, dynamic>.from(o as Map))],
      )
        ..photoPaths = _strings(j['photos'])
        ..planX = (j['x'] as num?)?.toDouble()
        ..planY = (j['y'] as num?)?.toDouble();
    }
    return Room(id: _s(j['id']), name: '', height: 2.8)
      ..applyServer(j)
      ..photoPaths = _strings(j['photos'])
      ..readSync(j);
  }
}

/// Pièce supprimée sur le téléphone, en attente d'envoi de la suppression au serveur.
class RoomTombstone {
  RoomTombstone({required this.id, required this.projectId, required this.serverVersion, this.syncError});

  final String id;
  final String projectId;
  int serverVersion;
  String? syncError;

  Map<String, dynamic> toJson() => {'id': id, 'project': projectId, 'sv': serverVersion, 'serr': syncError};

  factory RoomTombstone.fromJson(Map<String, dynamic> j) => RoomTombstone(
        id: _s(j['id']),
        projectId: _s(j['project']),
        serverVersion: _i(j['sv']),
        syncError: j['serr'] as String?,
      );
}

class QuoteLine {
  QuoteLine({
    required this.id,
    this.workItemId,
    this.countKey,
    this.wasteRateBp = 0,
    this.priceMissing = false,
    required this.label,
    this.description = '',
    this.unit = 'm²',
    this.base = QuantityBase.free,
    this.quantity = 0,
    this.manual = false,
    this.unitPriceCents = 0,
    this.frozenQuantity,
  });

  final String id;

  /// Ouvrage de la bibliothèque d'origine (null pour une ligne libre).
  String? workItemId;

  /// Élément compté quand [base] vaut [QuantityBase.count].
  String? countKey;

  /// Taux de perte appliqué à la quantité issue du métré (points de base), affiché sur la ligne.
  int wasteRateBp;

  /// Vrai tant qu'aucun prix n'a été saisi : la ligne bloque l'envoi du devis.
  bool priceMissing;
  String label;
  String description;
  String unit;
  QuantityBase base;

  /// Quantité saisie à la main (utilisée si [manual] ou si la base est libre).
  double quantity;

  /// Vrai quand l'artisan a modifié la quantité : elle ne suit plus le métré.
  bool manual;
  int unitPriceCents;

  /// Quantité figée à l'envoi du devis. Un devis envoyé ne bouge plus.
  double? frozenQuantity;

  QuoteLine copyWith({required String id}) => QuoteLine(
        id: id,
        workItemId: workItemId,
        countKey: countKey,
        wasteRateBp: wasteRateBp,
        priceMissing: priceMissing,
        label: label,
        description: description,
        unit: unit,
        base: base,
        quantity: quantity,
        manual: manual,
        unitPriceCents: unitPriceCents,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'presId': workItemId,
        'count': countKey,
        'waste': wasteRateBp,
        'noPrice': priceMissing,
        'label': label,
        'desc': description,
        'unit': unit,
        'base': base.name,
        'qty': quantity,
        'manual': manual,
        'pu': unitPriceCents,
        'frozen': frozenQuantity,
      };

  factory QuoteLine.fromJson(Map<String, dynamic> j) => QuoteLine(
        id: _s(j['id']),
        workItemId: j['presId'] as String?,
        countKey: j['count'] as String?,
        wasteRateBp: _i(j['waste']),
        priceMissing: j['noPrice'] == true,
        label: _s(j['label']),
        description: _s(j['desc']),
        unit: _s(j['unit'], 'm²'),
        base: _enumByName(QuantityBase.values, j['base'], QuantityBase.free),
        quantity: _d(j['qty']),
        manual: j['manual'] == true,
        unitPriceCents: _i(j['pu']),
        frozenQuantity: (j['frozen'] as num?)?.toDouble(),
      );
}

class Quote {
  Quote({
    required this.id,
    required this.number,
    this.version = 1,
    required this.date,
    this.status = QuoteStatus.draft,
    this.discountPercent = 0,
    this.depositPercent = 30,
    List<QuoteLine>? lines,
  }) : lines = lines ?? [];

  final String id;
  String number;
  int version;
  DateTime date;
  QuoteStatus status;
  double discountPercent;
  double depositPercent;
  List<QuoteLine> lines;

  bool get locked => status != QuoteStatus.draft;

  Map<String, dynamic> toJson() => {
        'id': id,
        'num': number,
        'version': version,
        'date': date.toIso8601String(),
        'status': status.name,
        'remise': discountPercent,
        'acompte': depositPercent,
        'lines': lines.map((l) => l.toJson()).toList(),
      };

  factory Quote.fromJson(Map<String, dynamic> j) => Quote(
        id: _s(j['id']),
        number: _s(j['num']),
        version: _i(j['version'], 1),
        date: DateTime.tryParse(_s(j['date'])) ?? DateTime.now(),
        status: _enumByName(QuoteStatus.values, j['status'], QuoteStatus.draft),
        discountPercent: _d(j['remise']),
        depositPercent: _d(j['acompte'], 30),
        lines: (j['lines'] as List? ?? [])
            .map((e) => QuoteLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// État de synchronisation commun aux fiches partagées avec le serveur.
mixin Syncable {
  /// Version connue du serveur ; null tant que la fiche n'a jamais été envoyée.
  int? serverVersion;

  /// Modifiée sur le téléphone depuis le dernier envoi.
  bool dirty = true;

  /// Supprimée sur le téléphone, en attente d'envoi de la suppression.
  bool deleted = false;

  /// Message du serveur si l'envoi a été refusé ; la fiche n'est renvoyée qu'après modification.
  String? syncError;

  void markEdited() {
    dirty = true;
    syncError = null;
  }

  Map<String, dynamic> syncJson() => {'sv': serverVersion, 'dirty': dirty, 'del': deleted, 'serr': syncError};

  void readSync(Map<String, dynamic> j, {bool legacyDirty = true}) {
    serverVersion = j['sv'] is num ? (j['sv'] as num).toInt() : null;
    dirty = j.containsKey('dirty') ? j['dirty'] == true : legacyDirty;
    deleted = j['del'] == true;
    syncError = j['serr'] as String?;
  }
}

/// Fiche client (docs/DATABASE_SCHEMA.md, table clients).
class Client with Syncable {
  Client({
    required this.id,
    this.type = 'individual',
    this.displayName = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.city = '',
    this.ice = '',
    this.notes = '',
    this.consentAt,
    this.consentTextVersion = '',
  });

  /// Version du texte de consentement affiché dans l'application.
  static const currentConsentVersion = '2026-11-01';

  final String id;
  String type;
  String displayName;
  String phone;
  String email;
  String address;
  String city;
  String ice;
  String notes;
  DateTime? consentAt;
  String consentTextVersion;

  bool get hasConsent => consentAt != null;

  Map<String, dynamic> toServer() => {
        'type': type,
        'display_name': displayName.trim(),
        'phone': phone.trim(),
        'email': email.trim(),
        'address': address.trim(),
        'city': city.trim(),
        'ice': ice.trim(),
        'notes': notes.trim(),
        'consent_at': consentAt?.toUtc().toIso8601String(),
        'consent_text_version': consentTextVersion,
      };

  void applyServer(Map<String, dynamic> d) {
    type = _s(d['type'], 'individual');
    displayName = _s(d['display_name']);
    phone = _s(d['phone']);
    email = _s(d['email']);
    address = _s(d['address']);
    city = _s(d['city']);
    ice = _s(d['ice']);
    notes = _s(d['notes']);
    consentAt = d['consent_at'] == null ? null : DateTime.tryParse(_s(d['consent_at']));
    consentTextVersion = _s(d['consent_text_version']);
  }

  Map<String, dynamic> toJson() => {'id': id, ...toServer(), ...syncJson()};

  factory Client.fromJson(Map<String, dynamic> j) => Client(id: _s(j['id']))
    ..applyServer(j)
    ..readSync(j);
}

class Project with Syncable {
  Project({
    required this.id,
    this.clientId,
    this.reference,
    this.name = '',
    this.projectType = 'renovation',
    this.propertyKind,
    this.status = 'prospect',
    this.description = '',
    this.budgetCents,
    this.currency = 'MAD',
    this.visitDate,
    this.managerId,
    this.address = '',
    this.city = '',
    this.notes = '',
    this.legacyClientName = '',
    this.legacyClientPhone = '',
    List<String>? photoPaths,
    List<Room>? rooms,
    List<Quote>? quotes,
    DateTime? updatedAt,
  })  : photoPaths = photoPaths ?? [],
        rooms = rooms ?? [],
        quotes = quotes ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String? clientId;

  /// Référence attribuée par le serveur (ex. LMA-2026-0042) ; null avant la première synchronisation.
  String? reference;
  String name;
  String projectType;
  String? propertyKind;
  String status;
  String description;
  int? budgetCents;
  String currency;
  DateTime? visitDate;
  String? managerId;

  /// Validation du métré : {validated_at, validated_by, validated_by_name, fingerprint, rooms,
  /// unverified_accepted}. Null tant que le métré n'est pas validé.
  Map<String, dynamic>? metreValidation;

  /// Adresse et ville du chantier.
  String address;
  String city;
  String notes;

  /// Nom et téléphone saisis avec l'ancienne version (avant les fiches clients) ; servent
  /// uniquement à créer la fiche client lors de la reprise des données.
  String legacyClientName;
  String legacyClientPhone;

  // Pièces : synchronisées séparément (table rooms). Photos et devis : encore locaux.
  List<String> photoPaths;
  List<Room> rooms;
  List<Quote> quotes;
  DateTime updatedAt;

  bool get archived => status == 'archived';
  /// Données présentes uniquement sur ce téléphone (perdues si le projet était supprimé ici).
  bool get hasLocalOnlyData =>
      quotes.isNotEmpty || photoPaths.isNotEmpty || rooms.any((r) => r.dirty || r.photoPaths.isNotEmpty);
  Quote? get lastQuote => quotes.isEmpty ? null : quotes.last;

  Map<String, dynamic> toServer() => {
        'client_id': clientId,
        'name': name.trim(),
        'project_type': projectType,
        'property_kind': propertyKind,
        'status': status,
        'description': description.trim(),
        'budget_cents': budgetCents,
        'currency': currency,
        'visit_date': visitDate == null
            ? null
            : '${visitDate!.year.toString().padLeft(4, '0')}-${visitDate!.month.toString().padLeft(2, '0')}-${visitDate!.day.toString().padLeft(2, '0')}',
        'manager_id': managerId,
        'site_address': address.trim(),
        'site_city': city.trim(),
        'notes': notes.trim(),
        'metre_validation': metreValidation,
      };

  void applyServer(Map<String, dynamic> d) {
    metreValidation = d['metre_validation'] == null ? null : Map<String, dynamic>.from(d['metre_validation'] as Map);
    clientId = d['client_id'] as String?;
    name = _s(d['name']);
    projectType = _s(d['project_type'], 'renovation');
    propertyKind = d['property_kind'] as String?;
    status = _s(d['status'], 'prospect');
    description = _s(d['description']);
    budgetCents = d['budget_cents'] is num ? (d['budget_cents'] as num).toInt() : null;
    currency = _s(d['currency'], 'MAD');
    visitDate = d['visit_date'] == null ? null : DateTime.tryParse(_s(d['visit_date']));
    managerId = d['manager_id'] as String?;
    address = _s(d['site_address']);
    city = _s(d['site_city']);
    notes = _s(d['notes']);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        ...toServer(),
        'reference': reference,
        'legacy_client': legacyClientName,
        'legacy_phone': legacyClientPhone,
        'photos': photoPaths,
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'quotes': quotes.map((q) => q.toJson()).toList(),
        'updated': updatedAt.toIso8601String(),
        ...syncJson(),
      };

  factory Project.fromJson(Map<String, dynamic> j) {
    final legacy = !j.containsKey('site_city'); // format Qiyas
    final p = Project(
      id: _s(j['id']),
      reference: j['reference'] as String?,
      legacyClientName: legacy ? _s(j['client']) : _s(j['legacy_client']),
      legacyClientPhone: legacy ? _s(j['phone']) : _s(j['legacy_phone']),
      photoPaths: _strings(j['photos']),
      rooms: (j['rooms'] as List? ?? []).map((e) => Room.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      quotes: (j['quotes'] as List? ?? []).map((e) => Quote.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      updatedAt: DateTime.tryParse(_s(j['updated'])) ?? DateTime.now(),
    );
    if (legacy) {
      p
        ..address = _s(j['address'])
        ..city = _s(j['city'])
        ..notes = _s(j['notes'])
        ..status = j['archived'] == true ? 'archived' : 'prospect';
    } else {
      p.applyServer(j);
    }
    p.readSync(j);
    return p;
  }
}

/// Conflit de synchronisation à arbitrer par l'utilisateur : rien n'est écrasé en silence.
class SyncConflict {
  SyncConflict({required this.entity, required this.id, required this.server, this.reason = ''});

  final String entity; // 'clients' ou 'projects'
  final String id;

  /// Enregistrement du serveur (version, deleted, data).
  final Map<String, dynamic> server;
  final String reason;

  Map<String, dynamic> toJson() => {'entity': entity, 'id': id, 'server': server, 'reason': reason};

  factory SyncConflict.fromJson(Map<String, dynamic> j) => SyncConflict(
        entity: _s(j['entity']),
        id: _s(j['id']),
        server: Map<String, dynamic>.from(j['server'] as Map? ?? {}),
        reason: _s(j['reason']),
      );
}

class AppData {
  AppData({
    required this.company,
    required this.projects,
    List<WorkItem>? workItems,
    List<MaterialItem>? materials,
    List<Supplier>? suppliers,
    List<Client>? clients,
    List<SyncConflict>? conflicts,
    List<RoomTombstone>? roomTombstones,
    List<Map<String, dynamic>>? pendingRooms,
    this.quoteCounter = 0,
    this.syncCursor = 0,
    this.syncAccount,
    this.lastSyncAt,
  })  : workItems = workItems ?? [],
        materials = materials ?? [],
        suppliers = suppliers ?? [],
        clients = clients ?? [],
        conflicts = conflicts ?? [],
        roomTombstones = roomTombstones ?? [],
        pendingRooms = pendingRooms ?? [];

  Company company;
  List<WorkItem> workItems;
  List<MaterialItem> materials;
  List<Supplier> suppliers;
  List<Project> projects;
  List<Client> clients;
  List<SyncConflict> conflicts;
  List<RoomTombstone> roomTombstones;

  /// Pièces reçues du serveur avant leur projet (rattachées à son arrivée).
  List<Map<String, dynamic>> pendingRooms;

  /// Compteur local de numérotation des devis (numérotation serveur au lot 1.6).
  int quoteCounter;

  /// Dernier numéro d'ordre reçu du serveur, et compte utilisateur auquel il se rapporte.
  int syncCursor;
  String? syncAccount;
  DateTime? lastSyncAt;

  Map<String, dynamic> toJson() => {
        'schema': 4,
        'company': company.toJson(),
        'work_items': workItems.map((p) => p.toJson()).toList(),
        'materials': materials.map((p) => p.toJson()).toList(),
        'suppliers': suppliers.map((p) => p.toJson()).toList(),
        'projects': projects.map((p) => p.toJson()).toList(),
        'clients': clients.map((c) => c.toJson()).toList(),
        'conflicts': conflicts.map((c) => c.toJson()).toList(),
        'room_tombstones': roomTombstones.map((t) => t.toJson()).toList(),
        'pending_rooms': pendingRooms,
        'counter': quoteCounter,
        'sync_cursor': syncCursor,
        'sync_account': syncAccount,
        'last_sync': lastSyncAt?.toIso8601String(),
      };

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        company: Company.fromJson(Map<String, dynamic>.from(j['company'] as Map? ?? {})),
        // Les « prestations » Qiyas deviennent des ouvrages de la bibliothèque.
        workItems: j.containsKey('work_items')
            ? (j['work_items'] as List).map((e) => WorkItem.fromJson(Map<String, dynamic>.from(e as Map))).toList()
            : (j['prestations'] as List? ?? []).map((e) => WorkItem.fromLegacy(Map<String, dynamic>.from(e as Map))).toList(),
        materials: (j['materials'] as List? ?? []).map((e) => MaterialItem.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        suppliers: (j['suppliers'] as List? ?? []).map((e) => Supplier.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        projects: (j['projects'] as List? ?? [])
            .map((e) => Project.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        clients: (j['clients'] as List? ?? [])
            .map((e) => Client.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        conflicts: (j['conflicts'] as List? ?? [])
            .map((e) => SyncConflict.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        roomTombstones: (j['room_tombstones'] as List? ?? [])
            .map((e) => RoomTombstone.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        pendingRooms: (j['pending_rooms'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        quoteCounter: _i(j['counter']),
        syncCursor: _i(j['sync_cursor']),
        syncAccount: j['sync_account'] as String?,
        lastSyncAt: j['last_sync'] == null ? null : DateTime.tryParse(_s(j['last_sync'])),
      );
}
