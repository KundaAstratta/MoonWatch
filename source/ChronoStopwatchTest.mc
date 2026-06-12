import Toybox.Lang;
import Toybox.Test;

// Tests unitaires du chronographe (refactoring P3). Logique à temps injecté
// (epoch s) — déterministe, sans Storage ni horloge réelle.

(:test)
function chronoStartsFromZero(logger as Test.Logger) as Boolean {
    var c = new ChronoStopwatch();
    c.applyState(1, 1000);
    logger.debug("start: elapsed=" + c.elapsedSeconds(1000) + " running=" + c.isRunning());
    return c.elapsedSeconds(1000) == 0 && c.isRunning() && c.isActive();
}

(:test)
function chronoCountsElapsed(logger as Test.Logger) as Boolean {
    var c = new ChronoStopwatch();
    c.applyState(1, 1000);
    var e = c.elapsedSeconds(1042);
    logger.debug("elapsed @+42s = " + e);
    return e == 42;
}

(:test)
function chronoPauseFreezes(logger as Test.Logger) as Boolean {
    var c = new ChronoStopwatch();
    c.applyState(1, 1000);
    c.applyState(2, 1030); // pause à +30 s
    var e = c.elapsedSeconds(1100); // 70 s plus tard : doit rester figé à 30
    logger.debug("paused: elapsed=" + e + " running=" + c.isRunning() + " active=" + c.isActive());
    return e == 30 && !c.isRunning() && c.isActive();
}

(:test)
function chronoResetClears(logger as Test.Logger) as Boolean {
    var c = new ChronoStopwatch();
    c.applyState(1, 1000);
    c.applyState(0, 1050); // reset
    logger.debug("reset: elapsed=" + c.elapsedSeconds(1100) + " active=" + c.isActive());
    return c.elapsedSeconds(1100) == 0 && !c.isActive();
}

(:test)
function chronoOnShowIdempotent(logger as Test.Logger) as Boolean {
    // B1 : onShow ré-applique Running → ne doit PAS réinitialiser le chrono
    var c = new ChronoStopwatch();
    c.applyState(1, 1000);
    var changed = c.applyState(1, 1080); // même état, +80 s
    var e = c.elapsedSeconds(1080);
    logger.debug("idempotent: changed=" + changed + " elapsed=" + e + " (attendu false / 80)");
    return !changed && e == 80;
}

(:test)
function chronoResumeRestartsFromZero(logger as Test.Logger) as Boolean {
    // Transition Paused -> Running repart de 0 (sémantique du réglage actuel)
    var c = new ChronoStopwatch();
    c.applyState(1, 1000);
    c.applyState(2, 1030); // pause à 30 s
    c.applyState(1, 1050); // re-Running : repart de 0
    var e = c.elapsedSeconds(1055);
    logger.debug("resume: elapsed=" + e + " (attendu 5)");
    return e == 5;
}

(:test)
function chronoSurvivesLargeInterval(logger as Test.Logger) as Boolean {
    // B2 : base epoch → pas de rollover sur de grands intervalles
    var c = new ChronoStopwatch();
    c.applyState(1, 1700000000);
    var e = c.elapsedSeconds(1700000000 + 3661); // 1 h 01 min 01 s
    logger.debug("grand intervalle: elapsed=" + e + " (attendu 3661)");
    return e == 3661;
}
