import Toybox.Lang;
import Toybox.Test;

// Tests unitaires des calculs astronomiques purs (refactoring P2).
// Lancer : ./build.sh --tests
//          monkeydo bin/MoonWatch-fenix847mm-test.prg fenix847mm -t
//
// Les temps sont des epochs Unix UTC en dur (déterministes, sans dépendance au
// fuseau du simulateur). Les valeurs attendues sont des repères astronomiques
// connus ; les tolérances couvrent la basse précision des algorithmes.

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
function dayOfYearMatchesKnownDates(logger as Test.Logger) as Boolean {
    var jan1  = AstroCalc.dayOfYear(1, 1);
    var feb13 = AstroCalc.dayOfYear(13, 2);  // 31 + 13 = 44
    var dec31 = AstroCalc.dayOfYear(31, 12); // 365 (sans bissextile)
    logger.debug("jan1=" + jan1 + " feb13=" + feb13 + " dec31=" + dec31);
    return jan1 == 1 && feb13 == 44 && dec31 == 365;
}

(:test)
function moonPhaseNewMoonJan2024(logger as Test.Logger) as Boolean {
    // Nouvelle lune : 2024-01-11 11:57 UTC → phase ≈ 0
    var p = AstroCalc.moonPhase(1704974220);
    logger.debug("nouvelle lune: phase=" + p + " (attendu ~0)");
    return p < 0.06 || p > 0.94;
}

(:test)
function moonPhaseFullMoonJan2024(logger as Test.Logger) as Boolean {
    // Pleine lune : 2024-01-25 17:54 UTC → phase ≈ 0.5
    var p = AstroCalc.moonPhase(1706205240);
    logger.debug("pleine lune: phase=" + p + " (attendu ~0.5)");
    return p > 0.44 && p < 0.56;
}
