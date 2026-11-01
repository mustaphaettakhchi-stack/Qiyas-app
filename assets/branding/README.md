# Identité visuelle — fichiers du logo

Logo de référence désigné par Groupe LAMAALAM le 1er novembre 2026 (remplace la maquette 3D transmise plus tôt le même jour, retirée du dépôt et conservée dans l'historique Git).

| Fichier | Rôle | Origine |
| --- | --- | --- |
| `logo_lamaalam_original.jpg` | **Fichier de référence, octets identiques au fichier transmis.** Ne jamais le modifier. | 536 × 578 px, JPEG. SHA-256 `3ee094c9e26797088887e41071272c55aebf432e081bc5369565057f095eb6e9`. Métadonnées : appareil Android, 24/10/2026, aucune géolocalisation. |
| `logo_lamaalam_original.png` | Même image au nom imposé par le cahier des charges | Pixels décodés du JPEG enregistrés en PNG (sans perte, sans métadonnées) |
| `logo_lamaalam_sans_telephone.png` | Variante d'usage : **numéro de téléphone retiré à la demande de LAMAALAM** | Lignes 10 à 490 du fichier original (le numéro occupe les lignes 495 à 535), centrées sur un carré de 536 px complété avec la couleur de fond d'origine (gris #EFEFEF). Rien n'est redessiné ni recoloré. |
| `logo_lamaalam_sans_telephone_512.png` | Même variante en 512 px | Réduction Lanczos |
| `logo_lamaalam_corrige.png` et `_512.png` | **Logo utilisé par l'application** : nom corrigé en « Group LAMAALAM », sans téléphone, **à la demande de Group LAMAALAM (1er novembre 2026)** | Variante sans téléphone dont seule la ligne de texte (lignes 428 à 520) est effacée et réécrite ; vérifié par programme : le reste de l'image est identique au pixel près. Police Arimo (OFL 1.1), graisse 560, couleur #3C2E2A relevée sur l'original. Script : `tool/branding/corriger_texte_logo.py`. |
| `logo_lamaalam_corrige_minuscules.png` et `_512.png` | Variante « group lamaalam » en minuscules, comme le logo d'origine | Même procédé |

Comparaison : `docs/logo_correction_comparaison.png` (original, « Group LAMAALAM », « group lamaalam »).

Le logo garde son fond gris clair : dans l'application (fond noir), il est affiché sur une tuile aux coins arrondis plutôt que détouré, car un détourage automatique d'un JPEG altérerait les contours des lettres.

## Réserves à lever par Groupe LAMAALAM

1. **Orthographe — corrigée.** Le logo d'origine écrit « group lamaalm ». Sur instruction de Group LAMAALAM, le texte a été recomposé en « Group LAMAALAM ». **C'est une correction provisoire faite par programme, pas un travail de graphiste** : la police d'origine (inconnue, proche d'Helvetica) est remplacée par une police libre de dessin voisin, et la correction en majuscules oblige à réduire le corps du texte pour tenir dans la largeur. Un graphiste devrait reprendre le logo en vectoriel.
2. **Résolution insuffisante pour l'impression.** 536 px de large en JPEG compressé (artefacts visibles autour des lettres) : correct à l'écran, flou sur un devis imprimé en A4. Il faut le fichier source (vectoriel SVG, PDF ou AI, ou PNG d'au moins 2 000 px).
3. **Couleur.** L'orange du logo mesure environ #F88000, légèrement différent de l'orange de la charte #F28C00. Écart faible à l'écran ; à harmoniser dans le fichier source si possible.
4. **Nom retenu : « Group LAMAALAM »** (décision du 1er novembre 2026). La forme juridique exacte (SARL, etc.) et la raison sociale inscrite au registre du commerce, obligatoires sur les devis, restent à confirmer.
5. **Droits** : confirmer que Groupe LAMAALAM détient les droits d'exploitation de ce logo.
