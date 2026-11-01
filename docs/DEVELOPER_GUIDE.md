# Guide du développeur — LAMAALAM

Architecture : [`ARCHITECTURE.md`](ARCHITECTURE.md). Schéma : [`DATABASE_SCHEMA.md`](DATABASE_SCHEMA.md). Parcours et critères d'acceptation : [`USER_FLOWS.md`](USER_FLOWS.md).

## 1. Règles du projet

- **Open Source uniquement**, chaque dépendance inscrite au [registre des licences](../OPEN_SOURCE_LICENSE_REGISTER.md) **avant** son ajout. Aucune API propriétaire, aucun service payant, aucun changement de licence sans accord écrit de Group LAMAALAM.
- Jamais de secret dans le dépôt (`.env` est ignoré par Git).
- Interface en français ; montants en **centimes entiers**, arrondi au demi supérieur (`round_half_up` côté serveur ≡ `.round()` côté Dart) ; pourcentages en points de base.
- Toute règle de calcul existe deux fois (application et serveur) et est vérifiée par les **cas partagés** `shared/metre_cases.json` et `shared/quote_cases.json` : modifier un calcul = modifier ces cas.
- Une fonction n'est terminée que testée ; une correction de bogue commence par un test qui échoue.

## 2. Dépôt

```
lib/            application Flutter
  domain/       modèles, calculs (métré, devis, tableau de bord) : fonctions pures
  data/         état (AppState), stockage local, espace client (API)
  sync/         moteur de synchronisation (envoi, réception, conflits, restauration)
  session/      client HTTP, jetons, session
  services/     PDF, partage
  ui/           écrans
test/           tests Flutter ; test/integration : bout en bout contre un vrai serveur
backend/app/    API FastAPI (routes/, models.py, security.py, cli.py…)
backend/migrations/  Alembic (une migration par lot, réversible)
backend/tests/  tests serveur sur PostgreSQL réel, sans superutilisateur (la RLS s'applique)
shared/         cas de calcul partagés application ↔ serveur
deploy/         Caddyfile, rôle PostgreSQL, scripts deploy / backup / restore
tool/           test de bout en bout, exercice de restauration
```

## 3. Environnement

```bash
# Serveur
cd backend && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements-dev.txt
# Base de test : rôle SANS superutilisateur (sinon la sécurité au niveau des lignes n'est pas testée)
createuser lamaalam_test --pwprompt && createdb -O lamaalam_test lamaalam_test
export LAMAALAM_TEST_DATABASE_URL=postgresql+psycopg://lamaalam_test:…@localhost:5432/lamaalam_test
python -m pytest -q

# Application (Flutter ≥ 3.41.6)
flutter pub get && flutter analyze && flutter test
```

## 4. Tests

| Commande | Ce qu'elle vérifie |
| --- | --- |
| `cd backend && python -m pytest -q` | API, sécurité, RLS, calculs, migrations (base effacée à chaque lancement) |
| `cd backend && alembic check` | modèles et migrations cohérents |
| `flutter test` | calculs, écrans (téléphone 360 × 740 points : un débordement fait échouer), session, synchronisation |
| `tool/integration_test.sh` | application ↔ vrai serveur (deux téléphones, conflits, devis, espace client) ; **efface la base indiquée** |
| `tool/restore_drill.sh` | pile Docker complète : installation, sauvegarde, destruction, restauration, vérification ; **machine d'essai uniquement** |

La CI (GitHub Actions) lance tout à chaque envoi : jobs `serveur`, `bout-en-bout`, `exploitation` (exercice de restauration sur machine neuve) et `verifier-et-construire` (analyse, tests, deux APK de test).

## 5. Modifier la base

```bash
cd backend
# modifier app/models.py, puis
alembic revision -m "objet" --rev-id 00NN     # écrire upgrade() ET downgrade()
alembic upgrade head && alembic downgrade -1 && alembic upgrade head   # aller-retour
alembic check
```

- Toute table métier porte `organization_id` et une politique RLS (`ENABLE` + `FORCE`).
- Contraintes nommées (sinon `downgrade` échoue).
- Tester la migration **sur une base remplie** : une base vide ne révèle ni les données orphelines ni les effets de la RLS forcée (voir la migration 0007).
- Une table synchronisée reçoit `version`, `sync_seq` (déclencheur `assign_sync_seq`) et un traitement dans `routes/sync.py` (ordre d'envoi `ORDER`).

## 6. Synchronisation (rappel)

- Envoi : `POST /sync/push`, une fiche = `{entity, id, base_version, deleted, data}` ; verrou optimiste sur la version ; refus détaillé par fiche.
- Réception : `GET /sync/pull?cursor=` dans l'ordre de `sync_seq`.
- Avant tout envoi, le téléphone consulte `GET /sync/epoch` : une époque différente = serveur restauré, synchronisation suspendue (voir `RESTORE.md` § 4). Une version reçue plus ancienne que celle du téléphone devient un conflit, jamais un écrasement.

## 7. Sécurité à respecter

- Nouvelle route : protégée par défaut (dépendance `get_context` / `require_staff` / `require_admin` / `require_client`) ; une route publique doit être ajoutée à `PUBLIC_ROUTES` dans `main.py` avec sa justification, sinon le test de sécurité des routes échoue.
- Un compte client ne doit **jamais** recevoir un déboursé, une marge, une ligne détaillée ou une photo non partagée ; toute ressource d'un autre client répond 404.
- Rien de sensible dans les journaux ni dans `audit_logs` (pas de mot de passe, jeton, code).

## 8. Livrer

Une branche par lot, des commits descriptifs (en français), la CI verte, puis une demande de fusion. Les APK de test sont produits par la CI ; **aucune publication sur un magasin d'applications** sans accord.
