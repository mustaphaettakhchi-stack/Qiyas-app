// Tableau de bord (lot 1.7), calculé sur les données du téléphone pour rester disponible
// hors connexion. Mêmes définitions que le serveur (backend/app/routes/dashboard.py) :
// - chantiers actifs : projets « accepté » ou « travaux en cours » ;
// - prospects : « prospect », « visite prévue », « chiffrage en cours » ;
// - devis : seule la dernière version de chaque devis compte ; les devis Qiyas non
//   synchronisés sont exclus.

import 'calculations.dart';
import 'metre.dart';
import 'models.dart';

const kActiveStatuses = {'won', 'in_progress'};
const kProspectStatuses = {'prospect', 'visit_planned', 'estimating'};

/// Délai après lequel un devis envoyé sans réponse est à relancer.
const kFollowUpDays = 15;

class DashboardStats {
  const DashboardStats({
    required this.activeSites,
    required this.prospects,
    required this.quotesToValidate,
    required this.quotesToSend,
    required this.quotesWaiting,
    required this.quotesAccepted,
    required this.acceptedTtcYear,
  });

  final int activeSites;
  final int prospects;
  final int quotesToValidate;
  final int quotesToSend;
  final int quotesWaiting;
  final int quotesAccepted;

  /// Montant TTC des devis acceptés dans l'année, par devise (centimes).
  final Map<String, int> acceptedTtcYear;

  Map<String, Object> toServerShape() => {
        'active_sites': activeSites,
        'prospects': prospects,
        'quotes_to_validate': quotesToValidate,
        'quotes_to_send': quotesToSend,
        'quotes_waiting': quotesWaiting,
        'quotes_accepted': quotesAccepted,
        'accepted_ttc_year': acceptedTtcYear,
      };
}

/// Dernière version de chaque devis d'un projet (hors devis Qiyas locaux).
List<Quote> latestQuotes(Project p) {
  final latest = <String, Quote>{};
  for (final q in p.quotes.where((q) => !q.legacy)) {
    final cur = latest[q.estimateId];
    if (cur == null || q.versionNo > cur.versionNo) latest[q.estimateId] = q;
  }
  return latest.values.toList();
}

DashboardStats dashboardStats(AppData data, {DateTime? now}) {
  final year = (now ?? DateTime.now()).year;
  final projects = data.projects.where((p) => !p.deleted).toList();
  final byStatus = <QuoteStatus, int>{};
  final accepted = <String, int>{};
  for (final p in projects) {
    for (final q in latestQuotes(p)) {
      byStatus[q.status] = (byStatus[q.status] ?? 0) + 1;
      if (q.status == QuoteStatus.accepted && q.decidedAt != null && q.decidedAt!.toUtc().year == year) {
        accepted[q.currency] = (accepted[q.currency] ?? 0) + quoteTotals(p, q).ttc;
      }
    }
  }
  return DashboardStats(
    activeSites: projects.where((p) => kActiveStatuses.contains(p.status)).length,
    prospects: projects.where((p) => kProspectStatuses.contains(p.status)).length,
    quotesToValidate: byStatus[QuoteStatus.draft] ?? 0,
    quotesToSend: byStatus[QuoteStatus.validated] ?? 0,
    quotesWaiting: byStatus[QuoteStatus.sent] ?? 0,
    quotesAccepted: byStatus[QuoteStatus.accepted] ?? 0,
    acceptedTtcYear: accepted,
  );
}

enum TodoKind { validateQuote, numberPending, sendQuote, followUp, metreStale, visit, syncIssue }

class TodoItem {
  const TodoItem(this.kind, this.title, this.detail, {this.projectId, this.quoteId});
  final TodoKind kind;
  final String title;
  final String detail;
  final String? projectId;
  final String? quoteId;
}

/// Actions à mener, calculées à partir des données (aucune notification inventée).
List<TodoItem> todoItems(AppData data, {required bool isAdmin, required String Function(Project) clientName, DateTime? now}) {
  final today = now ?? DateTime.now();
  final out = <TodoItem>[];
  final issues = data.conflicts.length +
      data.clients.where((c) => c.syncError != null).length +
      data.projects.where((p) => p.syncError != null).length;
  if (issues > 0) {
    out.add(TodoItem(TodoKind.syncIssue, 'Synchronisation : $issues point(s) à régler', 'Conflits ou envois refusés'));
  }
  for (final p in data.projects.where((p) => !p.deleted)) {
    final name = clientName(p);
    final ref = p.reference ?? 'projet non synchronisé';
    for (final q in latestQuotes(p)) {
      switch (q.status) {
        case QuoteStatus.draft when isAdmin && q.lines.isNotEmpty:
          out.add(TodoItem(TodoKind.validateQuote, 'Devis à valider · $name', ref, projectId: p.id, quoteId: q.id));
        case QuoteStatus.validated when q.number == null:
          out.add(TodoItem(TodoKind.numberPending, 'Numéro en attente · $name', 'Synchronisez pour numéroter le devis',
              projectId: p.id, quoteId: q.id));
        case QuoteStatus.validated:
          out.add(TodoItem(TodoKind.sendQuote, 'Devis à envoyer · $name', q.number!, projectId: p.id, quoteId: q.id));
        case QuoteStatus.sent when q.sentAt != null && today.difference(q.sentAt!).inDays >= kFollowUpDays:
          out.add(TodoItem(TodoKind.followUp, 'À relancer · $name',
              '${q.number ?? ''} envoyé il y a ${today.difference(q.sentAt!).inDays} jours', projectId: p.id, quoteId: q.id));
        default:
          break;
      }
      if (q.status == QuoteStatus.draft && q.lines.isNotEmpty && metreState(p) == MetreState.stale) {
        out.add(TodoItem(TodoKind.metreStale, 'Métré à revalider · $name', ref, projectId: p.id));
      }
    }
    final visit = p.visitDate;
    if (visit != null) {
      final days = DateTime(visit.year, visit.month, visit.day).difference(DateTime(today.year, today.month, today.day)).inDays;
      if (days >= 0 && days <= 7 && kProspectStatuses.contains(p.status)) {
        out.add(TodoItem(TodoKind.visit, days == 0 ? 'Visite aujourd\'hui · $name' : 'Visite dans $days jour(s) · $name',
            [p.address, p.city].where((x) => x.isNotEmpty).join(', '), projectId: p.id));
      }
    }
  }
  return out;
}
