/// Libellés français des valeurs partagées avec le serveur.
const kProjectTypes = {
  'renovation': 'Rénovation',
  'new_build': 'Construction neuve',
  'extension': 'Extension',
  'interior': 'Aménagement intérieur',
  'exterior': 'Aménagement extérieur',
  'commercial': 'Local commercial',
};

const kPropertyKinds = {
  'apartment': 'Appartement',
  'house': 'Maison',
  'villa': 'Villa',
  'land': 'Terrain',
  'commercial': 'Local commercial',
  'other': 'Autre',
};

const kProjectStatuses = {
  'prospect': 'Prospect',
  'visit_planned': 'Visite prévue',
  'estimating': 'Chiffrage en cours',
  'estimate_sent': 'Devis envoyé',
  'won': 'Accepté',
  'in_progress': 'Travaux en cours',
  'delivered': 'Livré',
  'lost': 'Perdu',
  'archived': 'Archivé',
};

const kClientTypes = {'individual': 'Particulier', 'company': 'Entreprise'};

/// Texte de consentement présenté au client (version Client.currentConsentVersion).
/// À faire valider juridiquement (loi 09-08, RGPD le cas échéant).
const kConsentText =
    'Le client accepte que Group LAMAALAM conserve ses coordonnées, les mesures et les photos de son bien '
    'pour établir le devis et suivre les travaux. Ces données ne sont pas publiées et ne servent à aucune '
    'publicité sans un accord écrit distinct.';
