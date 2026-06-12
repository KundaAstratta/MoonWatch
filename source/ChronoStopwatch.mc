import Toybox.Lang;
import Toybox.Application.Storage;

// Chronographe piloté par le réglage chronoState (Garmin Connect).
//
// Base de temps : epoch Unix en secondes, injecté par l'appelant — pas de
// rollover 32 bits ni de remise à zéro au reboot, contrairement à
// System.getTimer() (P3/B2). L'affichage chrono est de toute façon à la
// seconde, donc la résolution epoch suffit.
//
// L'état est persisté dans Application.Storage pour survivre au changement de
// cadran et au redémarrage (P3/B3). La logique d'état est sans effet de bord
// (hors save/load) et à temps injecté → testable, voir ChronoStopwatchTest.mc.
class ChronoStopwatch {

    // Valeurs du réglage chronoState
    enum {
        STATE_RESET   = 0, // aiguille à 12h, secondes d'horloge reprennent
        STATE_RUNNING = 1, // balaye depuis 0, tachymètre lisible
        STATE_PAUSED  = 2  // figé sur la dernière valeur
    }

    private var _running as Boolean = false;
    private var _startEpoch as Number = 0;   // epoch (s) du dernier départ (si _running)
    private var _accumulated as Number = 0;  // secondes figées avant la pause courante
    private var _lastState as Number = -1;   // dernier état appliqué (idempotence)

    function initialize() {
    }

    // Applique l'état chronoState à l'instant donné (epoch s).
    // Idempotent : ré-appliquer le même état ne réinitialise pas un chrono en
    // marche — corrige onShow qui faisait repartir l'aiguille de zéro (P3/B1).
    // Retourne true si l'état a changé (→ l'appelant peut persister).
    function applyState(state as Number, nowEpoch as Number) as Boolean {
        if (state == _lastState) {
            return false;
        }
        _lastState = state;
        if (state == STATE_RUNNING) {
            // Départ depuis 0 — l'aiguille part de 12h pour lire le tachymètre.
            _accumulated = 0;
            _startEpoch = nowEpoch;
            _running = true;
        } else if (state == STATE_PAUSED) {
            if (_running) {
                _accumulated += nowEpoch - _startEpoch;
            }
            _running = false;
        } else {
            // RESET (0) ou valeur inconnue.
            _running = false;
            _accumulated = 0;
            _startEpoch = 0;
        }
        return true;
    }

    // Secondes totales écoulées.
    function elapsedSeconds(nowEpoch as Number) as Number {
        if (_running) {
            return _accumulated + (nowEpoch - _startEpoch);
        }
        return _accumulated;
    }

    // En marche, ou figé sur une valeur > 0 (≠ reset).
    function isActive() as Boolean {
        return _running || _accumulated > 0;
    }

    function isRunning() as Boolean {
        return _running;
    }

    // --- Persistance (Application.Storage) ---

    function save() as Void {
        Storage.setValue("chronoRunning", _running ? 1 : 0);
        Storage.setValue("chronoStart", _startEpoch);
        Storage.setValue("chronoAccum", _accumulated);
        Storage.setValue("chronoLast", _lastState);
    }

    function load() as Void {
        var r = Storage.getValue("chronoRunning");
        var s = Storage.getValue("chronoStart");
        var a = Storage.getValue("chronoAccum");
        var l = Storage.getValue("chronoLast");
        _running     = (r instanceof Number) && (r == 1);
        _startEpoch  = (s instanceof Number) ? s : 0;
        _accumulated = (a instanceof Number) ? a : 0;
        _lastState   = (l instanceof Number) ? l : -1;
    }
}
