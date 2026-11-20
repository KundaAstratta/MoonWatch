import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

// Tests unitaires des calculs astronomiques purs (refactoring P2).
// Lancer : ./build.sh --tests
//          monkeydo bin/MoonWatch-fenix847mm-test.prg fenix847mm -t
//
// Les temps sont des epochs Unix UTC en dur (déterministes, sans dépendance au
// fuseau du simulateur). Les valeurs attendues sont des repères astronomiques
// connus ; les tolérances couvrent la basse précision des algorithmes.
//
// Ancres lunaires : instants DE421 des syzygies/quartiers (éclipses = syzygies
// exactes). Le modèle Schlyter de AstroCalc.moonPhase reste à <= ~0.4°, soit
// <= ~45 min : tolérance de test 0.002 cycle (~1.4 h).

// Toybox.Math n'expose pas abs() : valeur absolue locale pour les Float de test.
function _absf(x as Float) as Float {
    return (x < 0.0f) ? -x : x;
}

(:test)
function sunLongitudeJuneSolstice(logger as Test.Logger) as Boolean {
    // 2024-06-21 00:00 UTC → longitude écliptique ≈ 90°
    var lon = AstroCalc.sunEclipticLongitude(1718928000);
    logger.debug("solstice juin: lon=" + lon + " (attendu ~90)");
    return lon > 88.0 && lon < 92.0;
}

(:test)
function sunLongitudeDecemberSolstice(logger as Test.Logger) as Boolean {
    // 2024-12-21 12:00 UTC → longitude écliptique ≈ 270°
    var lon = AstroCalc.sunEclipticLongitude(1734782400);
    logger.debug("solstice déc: lon=" + lon + " (attendu ~270)");
    return lon > 268.0 && lon < 272.0;
}

(:test)
function sunLongitudePre2000AndNegativeD(logger as Test.Logger) as Boolean {
    // 1990-06-13 12:00 UTC (d < 0) → λ☉ ≈ 82.3° (Almanach USNO noons : ~82.4)
    var lon = AstroCalc.sunEclipticLongitude(645278400);
    logger.debug("pre-2000: lon=" + lon + " (attendu ~82.3)");
    return lon > 81.5 && lon < 83.0;
}

(:test)
function constellationPiscesWrapsZero(logger as Test.Logger) as Boolean {
    // PSC va de 351° à 29° en franchissant 0°
    var r0   = AstroCalc.constellationForLongitude(0.0d);
    var r355 = AstroCalc.constellationForLongitude(355.0d);
    var r10  = AstroCalc.constellationForLongitude(10.0d);
    var prog = r0[1] as Float;
    logger.debug("PSC wrap: 0=" + (r0[0] as String) + " 355=" + (r355[0] as String) + " 10=" + (r10[0] as String) + " prog0=" + prog);
    return (r0[0] as String).equals("PSC")
        && (r355[0] as String).equals("PSC")
        && (r10[0] as String).equals("PSC")
        && prog >= 0.0 && prog < 1.0;
}

(:test)
function constellationProgressMidRange(logger as Test.Logger) as Boolean {
    // ARI : 29°→53°, milieu ≈ 41° → progress ≈ 0.5
    var r = AstroCalc.constellationForLongitude(41.0d);
    var prog = r[1] as Float;
    logger.debug("ARI 41°: " + (r[0] as String) + " progress=" + prog);
    return (r[0] as String).equals("ARI") && prog > 0.4 && prog < 0.6;
}

(:test)
function sunConstellationDecemberIsSagittarius(logger as Test.Logger) as Boolean {
    // 2024-12-21 12:00 UTC, lon ≈ 270° → SGR (266°→299°)
    var r = AstroCalc.sunConstellation(1734782400);
    logger.debug("21 déc: " + (r[0] as String));
    return (r[0] as String).equals("SGR");
}

(:test)
function sunConstellationOphiuchusNovember(logger as Test.Logger) as Boolean {
    // 2024-11-30 12:00 UTC, lon ≈ 248.6° → OPH (247°→266°, fenêtre de 19°)
    var r = AstroCalc.sunConstellation(1732968000);
    logger.debug("30 nov (marée Ophiuchus): " + (r[0] as String));
    return (r[0] as String).equals("OPH");
}

(:test)
function eotFebruaryMinimum(logger as Test.Logger) as Boolean {
    var eot = AstroCalc.equationOfTimeForDay(44); // ~13 février
    logger.debug("EoT N44=" + eot + " (attendu ~-14)");
    return eot > -16.0 && eot < -13.0;
}

(:test)
function eotNovemberMaximum(logger as Test.Logger) as Boolean {
    var eot = AstroCalc.equationOfTimeForDay(307); // ~3 novembre
    logger.debug("EoT N307=" + eot + " (attendu ~+16)");
    return eot > 14.0 && eot < 18.0;
}

(:test)
function eotAprilZeroCrossing(logger as Test.Logger) as Boolean {
    var eot = AstroCalc.equationOfTimeForDay(105); // ~15 avril
    logger.debug("EoT N105=" + eot + " (attendu ~0)");
    return eot > -1.5 && eot < 1.5;
}

(:test)
function eotExtremaMatchUSNO(logger as Test.Logger) as Boolean {
    // Repères USNO : min ≈ -14.25 min (~11-12 fév), max ≈ +16.42 min (~3 nov).
    // Tolérance 1 min couvre la précision de Spencer (~0.35 min).
    var eMin = AstroCalc.equationOfTimeForDay(42);  // ~11 février
    var eMax = AstroCalc.equationOfTimeForDay(303); // ~30 octobre
    logger.debug("EoT N42=" + eMin + " N303=" + eMax + " (USNO: -14.25 / +16.42)");
    return eMin > -15.25 && eMin < -13.25
        && eMax > 15.42 && eMax < 17.42;
}

(:test)
function dayOfYearMatchesKnownDates(logger as Test.Logger) as Boolean {
    var jan1  = AstroCalc.dayOfYear(1, 1);
    var feb13 = AstroCalc.dayOfYear(13, 2);  // 31 + 13 = 44
    var dec31 = AstroCalc.dayOfYear(31, 12); // 365 (sans bissextile)
    logger.debug("jan1=" + jan1 + " feb13=" + feb13 + " dec31=" + dec31);
    return jan1 == 1 && feb13 == 44 && dec31 == 365;
}

(:test)
function moonPhaseNewMoonJanuary2024(logger as Test.Logger) as Boolean {
    // Nouvelle lune : 2024-01-11 11:57 UTC → phase ≈ 0
    var p = AstroCalc.moonPhase(1704974220);
    logger.debug("nouvelle lune: phase=" + p + " (attendu ~0)");
    return p < 0.002 || p > 0.998;
}

(:test)
function moonPhaseFullMoonJanuary2024(logger as Test.Logger) as Boolean {
    // Pleine lune : 2024-01-25 17:54 UTC (DE421 : 17:54:00) → phase ≈ 0.5
    var p = AstroCalc.moonPhase(1706205240);
    logger.debug("pleine lune: phase=" + p + " (attendu ~0.5)");
    return _absf(p - 0.5f) < 0.002f;
}

(:test)
function moonPhaseEclipseAnchors2023and2024(logger as Test.Logger) as Boolean {
    // Syzygies exactes (éclipses), instants DE421 :
    //   NL 09/02/2024 22:59:10, NL éclipse 08/04/2024 18:21 UTC,
    //   PL 28/10/2023 20:24:02 → phases 0 / 0 / 0.5 à ~50 min près.
    var nlFeb = AstroCalc.moonPhase(1707519550);
    var nlApr = AstroCalc.moonPhase(1712600460);
    var plOct = AstroCalc.moonPhase(1698524642);
    logger.debug("NL fév=" + nlFeb + " NL avr=" + nlApr + " PL oct=" + plOct);
    return (nlFeb < 0.002f || nlFeb > 0.998f)
        && (nlApr < 0.002f || nlApr > 0.998f)
        && _absf(plOct - 0.5f) < 0.002f;
}

(:test)
function moonPhaseQuartersJanuary2024(logger as Test.Logger) as Boolean {
    // PQ (élongation 90°) : 2024-01-18 03:52:36 UTC ; DQ (270°) : 2024-01-04 03:30:27
    var fq = AstroCalc.moonPhase(1705549956);
    var dq = AstroCalc.moonPhase(1704339027);
    logger.debug("PQ=" + fq + " DQ=" + dq + " (attendu 0.25 / 0.75)");
    return _absf(fq - 0.25f) < 0.002f && _absf(dq - 0.75f) < 0.002f;
}

(:test)
function moonPhaseWaxingWaningOrdering(logger as Test.Logger) as Boolean {
    // La phase croît de 0 → 1 sur un cycle : phase(12 janv) < phase(17 janv) < phase(22 janv)
    var p1 = AstroCalc.moonPhase(1705068620); // 12/01/2024 14:10 UTC
    var p2 = AstroCalc.moonPhase(1705500620); // 17/01/2024 14:10 UTC
    var p3 = AstroCalc.moonPhase(1705932620); // 22/01/2024 14:10 UTC
    logger.debug("12jan=" + p1 + " 17jan=" + p2 + " 22jan=" + p3);
    return p1 < p2 && p2 < p3;
}

(:test)
function moonPhaseAgreesWithMeanModel(logger as Test.Logger) as Boolean {
    // Le modèle précis et le modèle linéaire doivent rester cohérents à ~±1 j
    // (dégradation attendue du modèle moyen), jamais diverger d'un demi-cycle.
    var samples = [1711111110, 1714680000, 1721000000, 1735000000];
    for (var i = 0; i < samples.size(); i++) {
        var d = _absf(AstroCalc.moonPhase(samples[i]) - AstroCalc.moonPhaseMean(samples[i]));
        if (d > 0.5f) {
            d = 1.0f - d; // distance circulaire
        }
        logger.debug("ts=" + samples[i] + " écart précis<>moyen=" + d);
        if (d > 0.035f) {
            return false;
        }
    }
    return true;
}
