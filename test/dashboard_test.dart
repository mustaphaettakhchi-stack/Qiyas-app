import 'package:flutter_test/flutter_test.dart';
import 'package:lamaalam/domain/dashboard.dart';
import 'package:lamaalam/domain/models.dart';

Quote _q(String id, String estimate, int version, QuoteStatus status, {DateTime? decided, DateTime? sent, bool legacy = false}) => Quote(
      id: id,
      estimateId: estimate,
      versionNo: version,
      date: DateTime(2026, 10, 1),
      status: status,
      number: status == QuoteStatus.draft ? null : 'DV-2026-000$version',
      decidedAt: decided,
      sentAt: sent,
      legacy: legacy,
      lines: [QuoteLine(id: 'l', label: 'x', quantity: 1, manual: true, unitPriceCents: 100000, vatRateBp: 2000)],
    );

void main() {
  final now = DateTime(2026, 11, 20);
  AppData data() => AppData(company: Company(), projects: [
        Project(id: 'a', status: 'prospect', visitDate: DateTime(2026, 11, 22)),
        Project(id: 'b', status: 'estimating', quotes: [
          _q('b1', 'B', 1, QuoteStatus.draft),
          _q('c1', 'C', 1, QuoteStatus.sent, sent: DateTime(2026, 11, 1)),
        ]),
        Project(id: 'c', status: 'won', quotes: [
          _q('d1', 'D', 1, QuoteStatus.superseded),
          _q('d2', 'D', 2, QuoteStatus.accepted, decided: DateTime(2026, 11, 10)),
          _q('e1', 'E', 1, QuoteStatus.accepted, decided: DateTime(2025, 12, 1)),
          _q('f1', 'F', 1, QuoteStatus.validated),
          _q('old', 'OLD', 1, QuoteStatus.sent, legacy: true),
        ]),
        Project(id: 'd', status: 'in_progress'),
        Project(id: 'e', status: 'lost'),
        Project(id: 'gone', status: 'in_progress')..deleted = true,
      ]);

  test('Indicateurs : mêmes définitions que le serveur', () {
    final s = dashboardStats(data(), now: now);
    expect(s.activeSites, 2); // won + in_progress, projet supprimé exclu
    expect(s.prospects, 2); // prospect + estimating
    expect(s.quotesToValidate, 1);
    expect(s.quotesToSend, 1);
    expect(s.quotesWaiting, 1); // le devis Qiyas local est exclu
    expect(s.quotesAccepted, 2); // dernière version seulement (D v2 et E)
    expect(s.acceptedTtcYear, {'MAD': 120000}); // seul D v2 accepté en 2026 : 1 000 + 20 %
  });

  test('À faire : validation (administrateur), envoi, relance après 15 jours, visite', () {
    final admin = todoItems(data(), isAdmin: true, clientName: (_) => 'Client', now: now);
    expect(admin.map((t) => t.kind), containsAll([TodoKind.validateQuote, TodoKind.sendQuote, TodoKind.followUp, TodoKind.visit]));
    expect(admin.firstWhere((t) => t.kind == TodoKind.followUp).detail, contains('19 jours'));
    final collab = todoItems(data(), isAdmin: false, clientName: (_) => 'Client', now: now);
    expect(collab.any((t) => t.kind == TodoKind.validateQuote), isFalse);
    final early = todoItems(data(), isAdmin: true, clientName: (_) => 'Client', now: DateTime(2026, 11, 10));
    expect(early.any((t) => t.kind == TodoKind.followUp), isFalse);
  });
}
