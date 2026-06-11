import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class MoonWatchDelegate extends WatchUi.WatchFaceDelegate {

    function initialize() {
        WatchFaceDelegate.initialize();
    }

    // Appelé par le système si onUpdate dépasse le budget d'exécution alloué
    // (surtout en AOD). Sonde de diagnostic pour la phase P5 (budget énergie) :
    // visible dans la console du simulateur et les logs de l'app.
    function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("MoonWatch power budget exceeded: avg=" + powerInfo.executionTimeAverage
                       + " limit=" + powerInfo.executionTimeLimit);
    }

}
