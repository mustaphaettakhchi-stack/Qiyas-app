// Modèle de données du MVP (cahier des charges, section « Modèle de données »).
// Les objets sont volontairement mutables : l'état est centralisé dans AppState,
// qui sauvegarde et notifie l'interface après chaque modification.

enum QuoteStatus { draft, sent, accepted, refused }

enum QuantityBase { floor, ceiling, walls, skirting, free }

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

class Prestation {
  Prestation({
    required this.id,
    required this.name,
    this.description = '',
    this.unit = 'm²',
    this.base = QuantityBase.floor,
    this.unitPriceCents = 0,
    this.active = true,
  });

  final String id;
  String name;
  String description;
  String unit;
  QuantityBase base;
  int unitPriceCents;
  bool active;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'desc': description,
        'unit': unit,
        'base': base.name,
        'pu': unitPriceCents,
        'active': active,
      };

  factory Prestation.fromJson(Map<String, dynamic> j) => Prestation(
        id: _s(j['id']),
        name: _s(j['name']),
        description: _s(j['desc']),
        unit: _s(j['unit'], 'm²'),
        base: _enumByName(QuantityBase.values, j['base'], QuantityBase.free),
        unitPriceCents: _i(j['pu']),
        active: j['active'] != false,
      );
}

class Opening {
  Opening({required this.id, required this.type, required this.width, required this.height});

  factory Opening.standard(String id, OpeningType type) => type == OpeningType.door
      ? Opening(id: id, type: type, width: kDoorWidth, height: kDoorHeight)
      : Opening(id: id, type: type, width: kWindowWidth, height: kWindowHeight);

  final String id;
  OpeningType type;
  double width;
  double height;

  double get area => width * height;

  Map<String, dynamic> toJson() => {'id': id, 'type': type.name, 'w': width, 'h': height};

  factory Opening.fromJson(Map<String, dynamic> j) => Opening(
        id: _s(j['id']),
        type: _enumByName(OpeningType.values, j['type'], OpeningType.door),
        width: _d(j['w']),
        height: _d(j['h']),
      );
}

class Room {
  Room({
    required this.id,
    required this.name,
    required this.length,
    required this.width,
    required this.height,
    List<Opening>? openings,
    List<String>? photoPaths,
    this.planX,
    this.planY,
  })  : openings = openings ?? [],
        photoPaths = photoPaths ?? [];

  final String id;
  String name;
  double length;
  double width;
  double height;
  List<Opening> openings;
  List<String> photoPaths;
  double? planX;
  double? planY;

  int get doorCount => openings.where((o) => o.type == OpeningType.door).length;
  int get windowCount => openings.where((o) => o.type == OpeningType.window).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'L': length,
        'W': width,
        'H': height,
        'openings': openings.map((o) => o.toJson()).toList(),
        'photos': photoPaths,
        'x': planX,
        'y': planY,
      };

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        id: _s(j['id']),
        name: _s(j['name']),
        length: _d(j['L']),
        width: _d(j['W']),
        height: _d(j['H'], 2.8),
        openings: (j['openings'] as List? ?? [])
            .map((e) => Opening.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        photoPaths: _strings(j['photos']),
        planX: (j['x'] as num?)?.toDouble(),
        planY: (j['y'] as num?)?.toDouble(),
      );
}

class QuoteLine {
  QuoteLine({
    required this.id,
    this.prestationId,
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
  String? prestationId;
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
        prestationId: prestationId,
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
        'presId': prestationId,
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
        prestationId: j['presId'] as String?,
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

class Project {
  Project({
    required this.id,
    this.client = '',
    this.phone = '',
    this.address = '',
    this.city = '',
    this.notes = '',
    List<String>? photoPaths,
    List<Room>? rooms,
    List<Quote>? quotes,
    this.archived = false,
    this.synced = false,
    DateTime? updatedAt,
  })  : photoPaths = photoPaths ?? [],
        rooms = rooms ?? [],
        quotes = quotes ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String client;
  String phone;
  String address;
  String city;
  String notes;
  List<String> photoPaths;
  List<Room> rooms;
  List<Quote> quotes;
  bool archived;
  bool synced;
  DateTime updatedAt;

  Quote? get lastQuote => quotes.isEmpty ? null : quotes.last;

  Map<String, dynamic> toJson() => {
        'id': id,
        'client': client,
        'phone': phone,
        'address': address,
        'city': city,
        'notes': notes,
        'photos': photoPaths,
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'quotes': quotes.map((q) => q.toJson()).toList(),
        'archived': archived,
        'synced': synced,
        'updated': updatedAt.toIso8601String(),
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: _s(j['id']),
        client: _s(j['client']),
        phone: _s(j['phone']),
        address: _s(j['address']),
        city: _s(j['city']),
        notes: _s(j['notes']),
        photoPaths: _strings(j['photos']),
        rooms: (j['rooms'] as List? ?? [])
            .map((e) => Room.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        quotes: (j['quotes'] as List? ?? [])
            .map((e) => Quote.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        archived: j['archived'] == true,
        synced: j['synced'] == true,
        updatedAt: DateTime.tryParse(_s(j['updated'])) ?? DateTime.now(),
      );
}

class AppData {
  AppData({
    required this.company,
    required this.prestations,
    required this.projects,
    this.quoteCounter = 0,
    this.phone = '',
    this.authenticated = false,
    this.online = true,
  });

  Company company;
  List<Prestation> prestations;
  List<Project> projects;

  /// Compteur local de numérotation des devis.
  /// Avec un backend, il sera remplacé par une réserve de numéros par appareil.
  int quoteCounter;
  String phone;
  bool authenticated;

  /// Simulation de l'état réseau, en attendant le service de synchronisation.
  bool online;

  Map<String, dynamic> toJson() => {
        'schema': 1,
        'company': company.toJson(),
        'prestations': prestations.map((p) => p.toJson()).toList(),
        'projects': projects.map((p) => p.toJson()).toList(),
        'counter': quoteCounter,
        'phone': phone,
        'auth': authenticated,
        'online': online,
      };

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        company: Company.fromJson(Map<String, dynamic>.from(j['company'] as Map? ?? {})),
        prestations: (j['prestations'] as List? ?? [])
            .map((e) => Prestation.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        projects: (j['projects'] as List? ?? [])
            .map((e) => Project.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        quoteCounter: _i(j['counter']),
        phone: _s(j['phone']),
        authenticated: j['auth'] == true,
        online: j['online'] != false,
      );
}
