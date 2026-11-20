import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Calculs astronomiques purs, à temps injecté (secondes epoch Unix), donc
// déterministes et testables hors rendu. Extraits de MoonWatchView (refactoring P2).
// Voir les tests dans source/AstroCalcTest.mc.
//
// Validité : formules basse précision destinées à l'affichage (cadran).
//   - Soleil : algorithme de l'Astronomical Almanac, écart vérifié contre
//     l'éphéméride DE421 sur 2024 : max 0.008° (=> dates d'entrée en
//     constellation exactes à ~10 min près).
//   - Lune : série de Schlyter (6 termes en longitude), élongation vérifiée
//     contre DE421 sur 2024 : médiane 0.15°, max 0.37° (<= ~45 min de retard
//     d'événement), contre 1.3 h à 15 h pour le modèle linéaire au mois
//     synodique moyen (voir moonPhaseMean, conservé pour régression).
//
// Limite plateforme : Number est un entier signé 32 bits — Time.now().value()
// sature le 2038-01-19 03:14:07 UTC (problème Y2K38 du runtime Connect IQ,
// indépendant de ce module).
module AstroCalc {

    const DEG2RAD = 0.017453292519943295;

    // Référence J2000.0 : 2000-01-01 12:00 UTC (= 10957.5 j Unix exactement)
    const J2000_EPOCH = 946728000;
    // Mois synodique moyen (s, 29.530588854 j) et nouvelle lune de référence
    // (1970-01-07 20:35:00 UTC). Utilisés par moonPhaseMean seulement.
    const LUNAR_CYCLE_S = 2551442.877;
    const NEW_MOON_REF  = 592500;

    // Bornes IAU des 13 constellations zodiacales (Ophiuchus inclus), en degrés
    // de longitude écliptique. Déclarées au niveau module → allouées une seule
    // fois, au lieu de l'être à chaque appel comme dans l'ancienne version.
    // NB : bornes mesurées sur l'écliptique J2000 ; la précession décale la
    // longitude de ~1.4°/siècle => dates de traversée dérivant ~1 j/70 ans.
    const CON_STARTS = [351.0, 29.0, 53.0, 90.0, 118.0, 138.0, 174.0, 218.0, 241.0, 247.0, 266.0, 299.0, 327.0] as Array<Double>;
    const CON_ENDS   = [ 29.0, 53.0, 90.0, 118.0, 138.0, 174.0, 218.0, 241.0, 247.0, 266.0, 299.0, 327.0, 351.0] as Array<Double>;
    const CON_ABBRS  = ["PSC", "ARI", "TAU", "GEM", "CNC", "LEO", "VIR", "LIB", "SCO", "OPH", "SGR", "CAP", "AQR"] as Array<String>;

    // Jours par mois (index 1..12) pour le jour de l'année (ignore les bissextiles)
    const DAYS_IN_MONTH = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] as Array<Number>;

    // Modulo réel sur [0, 360[, robuste pour x < 0 (Math.floor le gère).
    // Remplace le motif inline « x - 360*floor(x/360) » dupliqué 3 fois.
    // (Usage interne : API de module, préfixe "_" par convention.)
    function _mod360(x as Double) as Double {
        return x - 360.0 * Math.floor(x / 360.0);
    }

    // Longitude écliptique géocentrique apparente du Soleil, en degrés [0, 360).
    // Algorithme basse précision de l'Astronomical Almanac (~0.01°, validé
    // contre DE421 sur 2024 : max 0.008°). Valable raisonnablement de 1900 à
    // 2100 (la précision se dégrade lentement hors de cette fenêtre).
    function sunEclipticLongitude(unixSeconds as Number) as Float {
        var d = (unixSeconds - J2000_EPOCH).toDouble() / 86400.0;

        var L = _mod360(280.46 + 0.9856474 * d);   // longitude moyenne
        var g = _mod360(357.528 + 0.9856003 * d);  // anomalie moyenne

        // Équation du centre (2 harmoniques)
        var lambda = L + 1.915 * Math.sin(g * DEG2RAD)
                       + 0.020 * Math.sin(2.0 * g * DEG2RAD);
        return _mod360(lambda).toFloat();
    }

    // Constellation IAU pour une longitude écliptique donnée.
    // Retourne [abbr as String, progress as Float], progress 0.0=entrée 1.0=sortie.
    function constellationForLongitude(lon as Double) as Array {
        lon = _mod360(lon); // défensif : toute valeur finie est projetée dans [0, 360[

        for (var i = 0; i < CON_STARTS.size(); i++) {
            var start = CON_STARTS[i];
            var end   = CON_ENDS[i];

            if (start > end) {
                // Franchit 0° (PSC : 351→29)
                var span = (360.0 - start) + end;
                if (lon >= start || lon < end) {
                    var elapsed = (lon >= start) ? lon - start : (360.0 - start) + lon;
                    return [CON_ABBRS[i], (elapsed / span).toFloat()] as Array;
                }
            } else {
                if (lon >= start && lon < end) {
                    return [CON_ABBRS[i], ((lon - start) / (end - start)).toFloat()] as Array;
                }
            }
        }
        return ["---", 0.0f] as Array; // inaccessible : les 13 intervalles couvrent [0, 360[
    }

    // Constellation traversée par le Soleil à l'instant donné.
    function sunConstellation(unixSeconds as Number) as Array {
        return constellationForLongitude(sunEclipticLongitude(unixSeconds).toDouble());
    }

    // Jour de l'année (1..365) — ignore les bissextiles, convention de la
    // régression de Spencer (B = 2π(n−81)/364) : en année bissextile, l'EoT
    // est évaluée comme pour l'année standard, ce qui biaise l'EoT d'au plus
    // ~0.5 min après février (pente max de l'EoT ≈ 30 s/j).
    function dayOfYear(day as Number, month as Number) as Number {
        var n = day;
        for (var m = 1; m < month; m++) {
            n += DAYS_IN_MONTH[m];
        }
        return n;
    }

    // Équation du temps (minutes signées) pour un jour de l'année donné.
    // Série de Spencer (1971), convention EoT = temps solaire apparent −
    // temps solaire moyen. Précision ~30 s (modèle ~0.35 min) + ~0.5 min en
    // année bissextile après février. Min ≈ −14.6 min (mi-février),
    // max ≈ +16.5 min (fin octobre), zéros ~15 avr / 13 juin / 1 sept / 25 déc.
    function equationOfTimeForDay(n as Number) as Float {
        var B = 2.0 * Math.PI * (n - 81).toDouble() / 364.0;
        var eot = 9.87 * Math.sin(2.0 * B)
                - 7.53 * Math.cos(B)
                - 1.5  * Math.sin(B);
        return eot.toFloat();
    }

    // Équation du temps à l'instant donné (date locale, comme l'affichage).
    // Variante géocentrique/UTC vs date locale : effet <= ~15 s, négligeable.
    function equationOfTime(unixSeconds as Number) as Float {
        var info = Gregorian.info(new Time.Moment(unixSeconds), Time.FORMAT_SHORT);
        return equationOfTimeForDay(dayOfYear(info.day as Number, info.month as Number));
    }

    // Élongation géocentrique apparente Soleil–Lune, en degrés [0, 360).
    // 0 = conjonction (nouvelle lune), 90 = premier quartier, 180 = pleine,
    // 270 = dernier quartier (convention almanach : quartiers définis par
    // l'élongation en longitude, précision ≤ 0.4°, ancré sur éclipses 2023-24).
    // Série de Schlyter (éléments moyens dérivés de l'epoch 1999-12-31 00:00
    // TT = J2000.0 + 1.5 j ; UT≈TT admis, ΔT → erreur < 0.02° sur 55 ans).
    function moonElongation(unixSeconds as Number) as Float {
        var dJ = (unixSeconds - J2000_EPOCH).toDouble() / 86400.0;
        var ds = dJ + 1.5; // rebasage sur l'epoch de la série

        // Éléments moyens de la Lune (deg)
        var N   = _mod360(125.1228 - 0.0529538083 * ds); // nœud ascendant
        var w   = _mod360(318.0634 + 0.1643573223 * ds); // argument du périastre
        var Mm  = _mod360(115.3654 + 13.0649929509 * ds); // anomalie moyenne
        // Soleil (mêmes éléments que sunEclipticLongitude, en Double)
        var Lsm = _mod360(280.460 + 0.9856474 * dJ);
        var gs  = _mod360(357.528 + 0.9856003 * dJ);

        var Lmm = _mod360(N + w + Mm); // longitude moyenne de la Lune
        var D   = _mod360(Lmm - Lsm);  // élongation moyenne
        var F   = _mod360(w + Mm);     // argument de latitude moyen

        // Longitude perturbée : équation du centre + perturbations majeures
        // (évection, variation, équation annuelle, réduction à l'écliptique,
        // terme secondaire 2D−2M).
        var lonM = _mod360(Lmm
            + 6.28875 * Math.sin(Mm * DEG2RAD)
            - 1.27400 * Math.sin((Mm - 2.0 * D) * DEG2RAD)
            + 0.65830 * Math.sin(2.0 * D * DEG2RAD)
            - 0.18580 * Math.sin(gs * DEG2RAD)
            - 0.11430 * Math.sin(2.0 * F * DEG2RAD)
            + 0.05880 * Math.sin((2.0 * D - 2.0 * Mm) * DEG2RAD));

        // Soleil apparent (équation du centre, même noyau que sunEclipticLongitude)
        var lonS = _mod360(Lsm + 1.915 * Math.sin(gs * DEG2RAD)
                              + 0.020 * Math.sin(2.0 * gs * DEG2RAD));

        return _mod360(lonM - lonS).toFloat();
    }

    // Phase lunaire [0.0, 1.0) : 0=nouvelle, 0.25=premier quartier, 0.5=pleine,
    // 0.75=dernier quartier. Définie par l'élongation vraie (moonElongation/360),
    // donc alignée sur les instants réels des syzygies et quartiers.
    function moonPhase(unixSeconds as Number) as Float {
        return (moonElongation(unixSeconds).toDouble() / 360.0).toFloat();
    }

    // Ancien modèle linéaire (mois synodique moyen depuis 1970), conservé pour
    // régression/comparaison. Écart aux événements réels observé de 1 à 15 h
    // (modèle moyen : les intervalles réels NL→PL varient de ~13.9 à 15.6 j).
    function moonPhaseMean(unixSeconds as Number) as Float {
        var totalCycles = (unixSeconds - NEW_MOON_REF).toDouble() / LUNAR_CYCLE_S;
        var phase = totalCycles - totalCycles.toLong();
        if (phase < 0) { phase += 1.0; }
        return phase.toFloat();
    }
}
