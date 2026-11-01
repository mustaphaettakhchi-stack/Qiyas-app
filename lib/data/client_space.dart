import 'dart:typed_data';

import '../session/api_client.dart';

/// Espace client (lot 1.8, USER_FLOWS P8) : lecture seule, en ligne uniquement.
///
/// Rien n'est conservé sur le téléphone du client : chaque écran interroge le serveur,
/// qui ne renvoie que ce que l'entreprise a choisi de partager.

DateTime _dt(Object? v) => DateTime.parse(v as String).toLocal();

class ClientProject {
  ClientProject.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      reference = j['reference'] as String? ?? '',
      name = j['name'] as String? ?? '',
      status = j['status'] as String? ?? '',
      projectType = j['project_type'] as String? ?? '',
      address = j['site_address'] as String? ?? '',
      city = j['site_city'] as String? ?? '',
      updatedAt = _dt(j['updated_at']);

  final String id;
  final String reference;
  final String name;
  final String status;
  final String projectType;
  final String address;
  final String city;
  final DateTime updatedAt;

  String get title => name.isNotEmpty ? name : (reference.isNotEmpty ? reference : 'Projet');
}

class ClientQuote {
  ClientQuote.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      reference = j['reference'] as String?,
      versionNo = j['version_no'] as int,
      status = j['status'] as String,
      issueDate = DateTime.parse(j['issue_date'] as String),
      validityDays = j['validity_days'] as int,
      currency = j['currency'] as String,
      totalHtCents = j['total_ht_cents'] as int,
      totalTtcCents = j['total_ttc_cents'] as int,
      pdfFileId = j['pdf_file_id'] as String?;

  final String id;
  final String? reference;
  final int versionNo;
  final String status;
  final DateTime issueDate;
  final int validityDays;
  final String currency;
  final int totalHtCents;
  final int totalTtcCents;
  final String? pdfFileId;
}

class SharedPhoto {
  SharedPhoto.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      caption = j['caption'] as String? ?? '',
      createdAt = _dt(j['created_at']);

  final String id;
  final String caption;
  final DateTime createdAt;
}

class ProjectStep {
  ProjectStep.fromJson(Map<String, dynamic> j)
    : at = _dt(j['occurred_at']),
      action = j['action'] as String,
      reference = j['reference'] as String?;

  final DateTime at;
  final String action;
  final String? reference;
}

class ClientProjectDetail {
  ClientProjectDetail.fromJson(Map<String, dynamic> j)
    : project = ClientProject.fromJson(j),
      quotes = [for (final q in j['quotes'] as List) ClientQuote.fromJson(Map<String, dynamic>.from(q as Map))],
      photos = [for (final p in j['photos'] as List) SharedPhoto.fromJson(Map<String, dynamic>.from(p as Map))],
      timeline = [for (final t in j['timeline'] as List) ProjectStep.fromJson(Map<String, dynamic>.from(t as Map))];

  final ClientProject project;
  final List<ClientQuote> quotes;
  final List<SharedPhoto> photos;
  final List<ProjectStep> timeline;
}

class ProjectMessage {
  ProjectMessage.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      authorName = j['author_name'] as String? ?? '',
      fromClient = j['from_client'] == true,
      body = j['body'] as String? ?? '',
      createdAt = _dt(j['created_at']);

  final String id;
  final String authorName;
  final bool fromClient;
  final String body;
  final DateTime createdAt;
}

/// Fichier d'un projet vu par l'équipe (photos partagées ou non, PDF des devis).
class ProjectFile {
  ProjectFile.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      quoteVersionId = j['quote_version_id'] as String?,
      caption = j['caption'] as String? ?? '',
      sizeBytes = j['size_bytes'] as int? ?? 0,
      visibleToClient = j['visible_to_client'] == true,
      createdAt = _dt(j['created_at']);

  final String id;
  final String kind;
  final String? quoteVersionId;
  final String caption;
  final int sizeBytes;
  final bool visibleToClient;
  final DateTime createdAt;
}

/// Accès réseau de l'espace client et des fonctions de partage de l'équipe.
class ClientSpaceApi {
  ClientSpaceApi(this.api);
  final ApiClient api;

  static List<Map<String, dynamic>> _list(Object? r) => [for (final x in r as List) Map<String, dynamic>.from(x as Map)];

  // --- compte client ---

  Future<List<ClientProject>> projects() async => _list(await api.get('/client/projects')).map(ClientProject.fromJson).toList();

  Future<ClientProjectDetail> project(String id) async =>
      ClientProjectDetail.fromJson(Map<String, dynamic>.from(await api.get('/client/projects/$id') as Map));

  // --- messagerie (client ou équipe selon [asClient]) ---

  String _messagesPath(String projectId, bool asClient) =>
      asClient ? '/client/projects/$projectId/messages' : '/projects/$projectId/messages';

  Future<List<ProjectMessage>> messages(String projectId, {required bool asClient}) async =>
      _list(await api.get(_messagesPath(projectId, asClient))).map(ProjectMessage.fromJson).toList();

  Future<ProjectMessage> postMessage(String projectId, String body, {required bool asClient}) async =>
      ProjectMessage.fromJson(Map<String, dynamic>.from(await api.post(_messagesPath(projectId, asClient), {'body': body}) as Map));

  // --- fichiers ---

  /// Contenu d'un fichier, par un lien signé de courte durée demandé juste avant.
  Future<Uint8List> fileBytes(String fileId) async {
    final link = Map<String, dynamic>.from(await api.get('/files/$fileId/link') as Map);
    return api.download(link['url'] as String);
  }

  Future<List<ProjectFile>> projectFiles(String projectId) async =>
      _list(await api.get('/files/project/$projectId')).map(ProjectFile.fromJson).toList();

  Future<ProjectFile> uploadPhoto(String projectId, Uint8List bytes, {String caption = '', bool visibleToClient = true}) async =>
      ProjectFile.fromJson(
        Map<String, dynamic>.from(
          await api.upload(
                '/files',
                fields: {'project_id': projectId, 'kind': 'photo', 'caption': caption, 'visible_to_client': '$visibleToClient'},
                bytes: bytes,
                filename: 'photo.jpg',
              )
              as Map,
        ),
      );

  Future<ProjectFile> uploadQuotePdf(String projectId, String quoteId, Uint8List bytes) async => ProjectFile.fromJson(
    Map<String, dynamic>.from(
      await api.upload(
            '/files',
            fields: {'project_id': projectId, 'kind': 'quote_pdf', 'quote_version_id': quoteId},
            bytes: bytes,
            filename: 'devis.pdf',
          )
          as Map,
    ),
  );

  Future<void> setShared(String fileId, bool visible) => api.patch('/files/$fileId', {'visible_to_client': visible});
}
