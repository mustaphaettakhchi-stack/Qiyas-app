# Sécurité et confidentialité — LAMAALAM

Version 0.1 — 1er novembre 2026 — statut : **PROPOSITION, à valider**

Les données traitées sont sensibles : identité et coordonnées des clients, adresses, **photos et scans de l'intérieur de domiciles**, montants financiers. Une fuite exposerait les clients à des risques concrets (repérage pour cambriolage). Le niveau de sécurité est dimensionné en conséquence.

## 1. Signaler une vulnérabilité

Écrire à l'adresse de sécurité de Groupe LAMAALAM (**à définir**, voir PHASE0_DECISIONS D-08). Ne pas ouvrir de ticket public. Accusé de réception sous 72 h.

## 2. Modèle de menace

| Menace | Exemple | Mesure principale |
| --- | --- | --- |
| Accès d'un client aux données d'un autre client | Modification d'un identifiant dans une URL | Contrôle d'accès serveur systématique + RLS PostgreSQL + tests automatisés d'isolation |
| Vol de téléphone d'un collaborateur | Téléphone perdu sur chantier | Verrouillage de l'app, jeton révocable à distance, données dans le stockage privé |
| Vol d'identifiants | Hameçonnage, mot de passe réutilisé | Argon2id, 2FA TOTP obligatoire pour les comptes internes, limitation des tentatives |
| Interception réseau | Wi-Fi public | HTTPS uniquement (TLS 1.2+), HSTS |
| Fuite de fichiers | Lien de photo partagé publiquement | Aucun fichier public ; URL signées à durée courte (≤ 15 min), liées à l'utilisateur |
| Compromission du serveur | Faille d'une dépendance | Mises à jour, conteneurs non privilégiés, pare-feu, secrets hors dépôt, journal d'audit |
| Perte de données | Panne disque, rançongiciel | Sauvegardes chiffrées, hors ligne, restauration testée |
| Manipulation d'un devis envoyé | Modification a posteriori | Versions figées, empreinte SHA-256 du PDF enregistrée, journal d'audit |

## 3. Authentification

Hypothèse retenue sous réserve de la décision D-05 :

- Identifiant : adresse e-mail. Mot de passe ≥ 12 caractères, vérifié contre une liste locale de mots de passe courants (aucun appel à un service tiers).
- Hachage **Argon2id** (argon2-cffi), paramètres recalibrés sur le serveur cible (objectif ≈ 250 ms par vérification).
- **2FA TOTP** obligatoire pour les rôles administrateur et collaborateur ; codes de secours à usage unique (hachés). Optionnelle pour les clients.
- Jeton d'accès JWT signé, durée **15 minutes** ; jeton de rafraîchissement opaque, rotatif, durée 30 jours, stocké haché en base (`auth_sessions`) et dans `flutter_secure_storage` sur le téléphone. Réutilisation d'un jeton de rafraîchissement déjà consommé = révocation de toute la session (détection de vol).
- Verrouillage progressif après 5 échecs (délai exponentiel), journalisé.
- Comptes clients créés **uniquement par invitation** (lien à usage unique valable 72 h). Pas d'inscription libre.
- L'application peut exiger le déverrouillage biométrique du téléphone à l'ouverture (paramètre organisation). *Le plugin nécessaire sera inscrit au registre des licences avant intégration.*
- Le code de démonstration fixe de Qiyas (`482913`) est **supprimé** ; aucun compte par défaut n'existe en production. Le premier administrateur est créé par une commande en ligne sur le serveur.

## 4. Autorisations

- Trois rôles : `admin`, `collaborator`, `client` (matrice détaillée dans `docs/DATABASE_SCHEMA.md` §4).
- Chaque route de l'API déclare explicitement le rôle et la portée requis ; une route sans déclaration fait échouer les tests.
- Toute requête métier est filtrée par `organization_id` (RLS PostgreSQL, rôle applicatif sans `BYPASSRLS`) puis, pour un client, par la liste de ses projets ; pour un collaborateur restreint, par ses projets.
- Un client ne voit jamais : prix d'achat, déboursés, marges, coefficients, notes internes, éléments non marqués `visible_to_client`.
- Les identifiants sont des UUID (non devinables), mais **la sécurité ne repose jamais sur ce caractère non devinable**.
- Tests obligatoires : pour chaque route, un test « client A tente d'accéder à la ressource du client B » qui doit renvoyer 404 (et non 403, pour ne pas révéler l'existence).

## 5. Fichiers

- Stockés hors de la racine web, noms internes aléatoires, jamais le nom d'origine.
- Téléchargement uniquement via l'API (contrôle d'accès) ou une URL signée HMAC à durée courte.
- Contrôle du type réel (signature binaire) et de la taille à la réception ; métadonnées EXIF de géolocalisation **retirées** des copies partagées avec les clients (conservées dans l'original interne pour la traçabilité du chantier, sauf décision contraire).
- Volume de stockage chiffré (LUKS) sur le serveur.

## 6. Communications

- HTTPS uniquement via Caddy, certificats Let's Encrypt, HSTS, redirection HTTP → HTTPS.
- En-têtes : `Content-Security-Policy` stricte sur l'espace web éventuel, `X-Content-Type-Options`, `Referrer-Policy`.
- CORS fermé par défaut.
- Limitation de débit par IP et par compte sur l'authentification et le téléversement.

## 7. Sur le téléphone

- Données dans le dossier privé de l'application ; pas d'écriture dans la galerie publique sans action explicite de l'utilisateur.
- Jetons dans Keychain (iOS) / Keystore (Android) via `flutter_secure_storage`.
- Chiffrement de la base SQLite locale : **À EXAMINER** (SQLCipher) ; d'ici là, la protection repose sur le chiffrement de l'appareil et le verrouillage de l'app.
- Déconnexion à distance : la révocation de session côté serveur provoque l'effacement des données locales à la prochaine connexion réseau.
- Journaux applicatifs sans données personnelles.

## 8. Serveur

- Debian stable, mises à jour de sécurité automatiques, SSH par clé uniquement, pas de connexion root, pare-feu n'ouvrant que 22 (restreint), 80 et 443.
- Conteneurs non privilégiés, système de fichiers en lecture seule quand c'est possible, workers de traitement **sans accès réseau sortant**.
- Secrets (clé JWT, mot de passe base, clé de chiffrement TOTP) dans un fichier `.env` hors dépôt, droits `600` ; jamais dans Git. Analyse de secrets dans la CI.
- Dépendances : versions verrouillées, contrôle des vulnérabilités connues dans la CI (`pip-audit`, `flutter pub outdated`), mise à jour mensuelle.

## 9. Journalisation

Table `audit_logs` en insertion seule. Actions journalisées au minimum : connexion réussie et échouée, changement de mot de passe ou de 2FA, création / modification / suppression d'utilisateur ou de rôle, validation de métré, validation / envoi / acceptation / refus de devis, modification de prix, téléchargement de document par un client, partage d'un élément au client, export et effacement de données, restauration de sauvegarde.

Conservation : 12 mois en ligne, puis archivage chiffré (durée à fixer avec le conseil juridique de LAMAALAM).

## 10. Sauvegardes et restauration

- Quotidienne : `pg_dump` chiffré + fichiers (restic, dédupliqué, chiffré), vers un support **physiquement distinct** du serveur.
- Hebdomadaire : copie hors site (emplacement à décider ; tout service payant est soumis à accord).
- Rétention proposée : 7 quotidiennes, 4 hebdomadaires, 12 mensuelles.
- **Test de restauration mensuel** sur une machine vierge, consigné. Une sauvegarde non testée n'est pas considérée comme une sauvegarde.
- Procédures détaillées dans `BACKUP.md` et `RESTORE.md` (Phase 1).

## 11. Données personnelles (loi 09-08 et RGPD)

Ce paragraphe décrit des mesures techniques ; **il ne vaut pas avis juridique**. La conformité doit être validée par un juriste.

- **Loi marocaine 09-08** : déclaration ou demande d'autorisation auprès de la **CNDP** avant mise en production du traitement « gestion des clients et des chantiers » ; information des personnes ; un transfert de données hors du Maroc (hébergement, sauvegarde hors site) relève d'un régime spécifique à vérifier.
- **RGPD** : applicable si LAMAALAM traite les données de personnes situées dans l'Union européenne (par exemple des clients résidant en Europe qui rénovent un bien à Tanger). À faire confirmer.
- Minimisation : seules les données nécessaires au devis et au chantier sont demandées ; la géolocalisation précise est optionnelle.
- Consentement : horodaté et versionné (`clients.consent_at`, `consent_text_version`) pour la conservation des photos et leur réutilisation éventuelle dans le portfolio — **aucune photo de client n'entre dans le portfolio ou un montage publicitaire sans consentement spécifique**.
- Droits d'accès et de portabilité : export complet d'un client (JSON + fichiers) depuis l'administration.
- Droit à l'effacement : procédure d'effacement physique (données et fichiers), dans les limites des obligations de conservation comptable et fiscale (devis acceptés et factures), journalisée sans données personnelles.
- Politique de conservation proposée, **à valider** : prospects sans suite 3 ans après le dernier contact ; projets réalisés selon les obligations comptables ; journaux 12 mois en ligne.

## 12. Ce qui reste à décider

- Mode d'authentification (D-05) et service d'envoi d'e-mails (D-08).
- Lieu d'hébergement et de sauvegarde hors site (D-06).
- Chiffrement de la base locale du téléphone.
- Durées de conservation définitives et formalités CNDP.
