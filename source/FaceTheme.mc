import Toybox.Lang;

// Paramètres partagés du cadran : valeurs qui pilotent la composition à
// plusieurs endroits du rendu (refactoring P4). Les nuances de gris purement
// locales au modelé 3D restent en place dans leur fonction — les centraliser
// ici n'apporterait pas de lisibilité.
module FaceTheme {

    // --- Disposition des subdials (fraction du rayon du cadran) ---
    const SUBDIAL_RADIUS_RATIO  = 0.25;  // rayon d'un subdial
    const SUBDIAL_OFFSET_RATIO  = 0.55;  // distance centre → subdials 9h / 3h
    const SUBDIAL_OFFSET6_RATIO = 0.75;  // fraction de l'offset pour le subdial 6h

    // --- Moyeu central : cône dégradé concentrique, heures (Ø max, foncé) →
    //     secondes (Ø min, clair). Empilé heures sous minutes sous secondes. ---
    const HUB_HOUR_COLOR   = 0x555555;
    const HUB_HOUR_RADIUS  = 16;
    const HUB_MIN_COLOR    = 0x888888;
    const HUB_MIN_RADIUS   = 12;
    const HUB_SEC_COLOR    = 0xCCCCCC;
    const HUB_SEC_RADIUS   = 8;
    const HUB_PIVOT_RADIUS = 4;          // pivot central (couleur DK_GRAY)
}
