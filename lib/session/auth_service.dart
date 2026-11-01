import 'api_client.dart';

/// Profil de l'utilisateur connecté (réponse de /auth/me).
class UserProfile {
  const UserProfile({
    required this.id,
    required this.organizationId,
    required this.email,
    required this.fullName,
    required this.roles,
    required this.totpEnabled,
  });

  final String id;
  final String organizationId;
  final String email;
  final String fullName;
  final List<String> roles;
  final bool totpEnabled;

  bool get isAdmin => roles.contains('admin');
  bool get isStaff => isAdmin || roles.contains('collaborator');

  String get roleLabel => isAdmin
      ? 'Administrateur'
      : roles.contains('collaborator')
          ? 'Collaborateur'
          : 'Client';

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        email: j['email'] as String,
        fullName: j['full_name'] as String,
        roles: (j['roles'] as List).cast<String>(),
        totpEnabled: j['totp_enabled'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'email': email,
        'full_name': fullName,
        'roles': roles,
        'totp_enabled': totpEnabled,
      };
}

/// Résultat de la première étape de connexion (mot de passe).
sealed class LoginStep {
  const LoginStep();
}

class LoginDone extends LoginStep {
  const LoginDone();
}

class LoginNeedsCode extends LoginStep {
  const LoginNeedsCode(this.mfaToken);
  final String mfaToken;
}

class LoginNeedsMfaSetup extends LoginStep {
  const LoginNeedsMfaSetup(this.mfaToken);
  final String mfaToken;
}

class MfaSetupInfo {
  const MfaSetupInfo(this.secret, this.otpauthUri);
  final String secret;
  final String otpauthUri;
}

/// Opérations d'authentification auprès de l'API LAMAALAM.
class AuthService {
  AuthService(this.api);
  final ApiClient api;

  static const _device = 'Application mobile';

  Future<LoginStep> login(String email, String password) async {
    final r = Map<String, dynamic>.from(await api.postPublic('/auth/login', {
      'email': email.trim(),
      'password': password,
      'device_label': _device,
    }) as Map);
    if (r['tokens'] != null) {
      await api.saveTokens(Map<String, dynamic>.from(r['tokens'] as Map));
      return const LoginDone();
    }
    if (r['mfa_required'] == true) return LoginNeedsCode(r['mfa_token'] as String);
    if (r['mfa_setup_required'] == true) return LoginNeedsMfaSetup(r['mfa_token'] as String);
    throw const ApiException('Réponse inattendue du serveur.', status: 0);
  }

  Future<MfaSetupInfo> mfaSetup(String mfaToken) async {
    final r = await api.postPublic('/auth/mfa/setup', {'mfa_token': mfaToken}) as Map;
    return MfaSetupInfo(r['secret'] as String, r['otpauth_uri'] as String);
  }

  /// Active la double authentification. Renvoie les codes de secours (affichés une seule fois).
  Future<List<String>> mfaConfirm(String mfaToken, String code) async {
    final r = await api.postPublic('/auth/mfa/confirm', {
      'mfa_token': mfaToken,
      'code': code.trim(),
      'device_label': _device,
    }) as Map;
    await api.saveTokens(Map<String, dynamic>.from(r['tokens'] as Map));
    return (r['backup_codes'] as List).cast<String>();
  }

  Future<void> mfaVerify(String mfaToken, {String? code, String? backupCode}) async {
    final r = await api.postPublic('/auth/mfa/verify', {
      'mfa_token': mfaToken,
      if (code != null) 'code': code.trim(),
      if (backupCode != null) 'backup_code': backupCode.trim(),
      'device_label': _device,
    });
    await api.saveTokens(Map<String, dynamic>.from(r as Map));
  }

  Future<UserProfile> me() async => UserProfile.fromJson(Map<String, dynamic>.from(await api.get('/auth/me') as Map));

  Future<void> acceptInvitation(String token, String password) =>
      api.postPublic('/invitations/accept', {'token': token, 'password': password});

  Future<void> acceptPasswordReset(String token, String password) =>
      api.postPublic('/password-reset/accept', {'token': token, 'password': password});

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } on ApiException {
      // Hors connexion : la session sera refusée par le serveur à expiration.
    }
    await api.clearTokens();
  }
}

/// Lien de nouveau mot de passe (`https://…/reinitialisation#JETON`) plutôt qu'invitation.
bool isPasswordResetLink(String input) => input.contains('/reinitialisation#');

/// Extrait le jeton d'un lien d'invitation (`https://…/invitation#JETON`) ou d'un jeton collé seul.
String? invitationTokenFrom(String input) {
  final text = input.trim();
  final token = text.contains('#') ? text.substring(text.indexOf('#') + 1) : text;
  return RegExp(r'^[A-Za-z0-9_-]{20,200}$').hasMatch(token) ? token : null;
}
