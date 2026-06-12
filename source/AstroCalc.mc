import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Calculs astronomiques purs, à temps injecté (secondes epoch Unix), donc
// déterministes et testables hors rendu. Extraits de MoonWatchView (refactoring P2).
// Voir les tests dans source/AstroCalcTest.mc.
module AstroCalc {

    // Référence J2000.0 : 2000-01-01 12:00 UTC
    const J2000_EPOCH = 946728000;
    // Mois synodique moyen (s) et nouvelle lune de référence (1970-01-07 20:35 UTC)
    const LUNAR_CYCLE_S = 2551442.877;
    const NEW_MOON_REF  = 592500;

    // Bornes IAU des 13 constellations zodiacales (Ophiuchus inclus), en degrés
    // de longitude écliptique. Déclarées au niveau module → allouées une seule
    // fois, au lieu de l'être à chaque appel comme dans l'ancienne version.
    const CON_STARTS = [351.0, 29.0, 53.0, 90.0, 118.0, 138.0, 174.0, 218.0, 241.0, 247.0, 266.0, 299.0, 327.0] as Array<Double>;
    const CON_ENDS   = [ 29.0, 53.0, 90.0, 118.0, 138.0, 174.0, 218.0, 241.0, 247.0, 266.0, 299.0, 327.0, 351.0] as Array<Double>;
    const CON_ABBRS  = ["PSC", "ARI", "TAU", "GEM", "CNC", "LEO", "VIR", "LIB", "SCO", "OPH", "SGR", "CAP", "AQR"] as Array<String>;

    // Jours par mois (index 1..12) pour le jour de l'année (ignore les bissextiles)
    const DAYS_IN_MONTH = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] as Array<Number>;

    // Longitude écliptique du Soleil en degrés [0, 360). Algorithme basse
    // précision (~0.01°), ne dépend que de la date. Modulo manuel (Double % Float
    // non supporté).
    function sunEclipticLongitude(unixSeconds as Number) as Float {
        var d = (unixSeconds - J2000_EPOCH).toDouble() / 86400.0;

        var L = 280.46 + 0.9856474 * d;
        L = L - 360.0 * Math.floor(L / 360.0);

        var g = 357.528 + 0.9856003 * d;
        g = g - 360.0 * Math.floor(g / 360.0);

        var gRad  = g * Math.PI / 180.0;
        var g2Rad = 2.0 * gRad;

        var lambda = L + 1.915 * Math.sin(gRad) + 0.020 * Math.sin(g2Rad);
        lambda = lambda - 360.0 * Math.floor(lambda / 360.0);

        return lambda.toFloat();
    }

    // Constellation IAU pour une longitude écliptique donnée.
    // Retourne [abbr as String, progress as Float], progress 0.0=entrée 1.0=sortie.
    function constellationForLongitude(lon as Double) as Array {
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
        return ["---", 0.0f] as Array; // ne devrait jamais arriver
    }

    // Constellation traversée par le Soleil à l'instant donné.
    function sunConstellation(unixSeconds as Number) as Array {
        return constellationForLongitude(sunEclipticLongitude(unixSeconds).toDouble());
    }

    // Jour de l'année (1..365) — ignore les bissextiles (acceptable pour l'EoT).
    function dayOfYear(day as Number, month as Number) as Number {
        var n = day;
        for (var m = 1; m < month; m++) {
            n += DAYS_IN_MONTH[m];
        }
        return n;
    }

    // Équation du temps (minutes signées) pour un jour de l'année donné.
    // Approximation de Spencer (1971), précision ~30 s. Min ≈ −14 (mi-février),
    // max ≈ +16 (début novembre), deux passages à zéro par an.
    function equationOfTimeForDay(n as Number) as Float {
        var B = 2.0 * Math.PI * (n - 81).toDouble() / 364.0;
        var eot = 9.87 * Math.sin(2.0 * B)
                - 7.53 * Math.cos(B)
                - 1.5  * Math.sin(B);
        return eot.toFloat();
    }

    // Équation du temps à l'instant donné (date locale, comme l'affichage).
    function equationOfTime(unixSeconds as Number) as Float {
        var info = Gregorian.info(new Time.Moment(unixSeconds), Time.FORMAT_SHORT);
        return equationOfTimeForDay(dayOfYear(info.day as Number, info.month as Number));
    }

    // Phase lunaire [0.0, 1.0) : 0=nouvelle, 0.25=premier quartier, 0.5=pleine,
    // 0.75=dernier quartier. Âge lunaire fractionnaire depuis NEW_MOON_REF.
    function moonPhase(unixSeconds as Number) as Float {
        var totalCycles = (unixSeconds - NEW_MOON_REF).toDouble() / LUNAR_CYCLE_S;
        var phase = totalCycles - totalCycles.toLong();
        if (phase < 0) { phase += 1.0; }
        return phase.toFloat();
    }
}
