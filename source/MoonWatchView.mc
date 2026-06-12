import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;

class MoonWatchView extends WatchUi.WatchFace {

    private var _centerX as Number = 0;
    private var _centerY as Number = 0;
    private var _radius as Number = 0;
    private var _isInSleepMode as Boolean = false;

    // Colors
    private var _colorBezel as Number = 0x222222;
    private var _colorTicks as Number = Graphics.COLOR_WHITE;
    private var _colorHandMain as Number = Graphics.COLOR_WHITE;
    private var _colorLume as Number = 0xccff00;
    private var _colorLogo as Number = Graphics.COLOR_LT_GRAY;

    // Chronograph State
    private var _chrono as ChronoStopwatch = new ChronoStopwatch();

    // Per-frame cache
    private var _cachedMoonPhase as Float = 0.0f;
    private var _moonPhaseHour as Number = -1;
    private var _cachedSunConst as String = "---";
    private var _cachedSunProgress as Float = 0.0f;
    private var _sunCacheDay as Number = -1;
    private var _cachedEqTime as Float = 0.0f;
    private var _eqTimeCacheDay as Number = -1;

    function initialize() {
        WatchFace.initialize();
        _chrono.load(); // restaure l'état chrono persisté (survit reboot / changement de cadran)
    }

    // Applies the chronoState setting from Garmin Connect
    // 0 = Reset  : hand returns to 12h, clock seconds resume
    // 1 = Running : hand sweeps from 0, tachymeter readable
    // 2 = Paused  : hand freezes on last value, tachymeter still readable
    public function applyChronoSettings() as Void {
        var val = Application.Properties.getValue("chronoState");
        var state = (val instanceof Number) ? val as Number : 0;
        if (_chrono.applyState(state, Time.now().value())) {
            _chrono.save(); // persiste seulement si l'état a réellement changé
        }
    }

    // Load your resources here
    function onLayout(dc as Dc) as Void {
        _centerX = dc.getWidth() / 2;
        _centerY = dc.getHeight() / 2;
        _radius = (_centerX < _centerY ? _centerX : _centerY);
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
        applyChronoSettings();
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        // Refresh caches once per hour (moon) / once per day (sun constellation)
        var clockNow = System.getClockTime();
        var currentHour = clockNow.hour;
        if (currentHour != _moonPhaseHour) {
            _cachedMoonPhase = AstroCalc.moonPhase(Time.now().value());
            _moonPhaseHour = currentHour;
        }
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var currentDay = info.day;
        if (currentDay != _sunCacheDay) {
            var sunData = AstroCalc.sunConstellation(Time.now().value());
            _cachedSunConst    = sunData[0] as String;
            _cachedSunProgress = sunData[1] as Float;
            _sunCacheDay = currentDay;
        }
        if (currentDay != _eqTimeCacheDay) {
            _cachedEqTime    = AstroCalc.equationOfTime(Time.now().value());
            _eqTimeCacheDay  = currentDay;
        }

        // Clear screen to black
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (!_isInSleepMode) {
            // High Power Mode: Draw everything
            // Draw Background (Event Horizon style)
            drawConcentricBackground(dc);
            drawStarField(dc);
    
            drawBezelAndTicks(dc, false);
            drawTachymeter(dc);
            drawSubdials(dc, false);
            drawBranding(dc, false);
            drawHands(dc);    // Heures et minutes (chacune avec son disque)
            drawSeconds(dc);  // Secondes + sommet du moyeu, au premier plan
        } else {
            // Sleep Mode (AOD): Anti burn-in — éléments atténués
            drawSleepBackground(dc);
            drawBezelAndTicks(dc, true);
            drawSubdials(dc, true);
            drawBranding(dc, true);
            drawHands(dc);
            drawHubTop(dc); // sommet du moyeu (pas de trotteuse en veille)
        }
    }

    private function drawSleepBackground(dc as Dc) as Void {
        // Fond concentrique — 80 anneaux, dégradé lissé
        var numRings  = 80;
        var maxRadius = _radius + 20;
        var startR = 0;    var startG = 0x40; var startB = 0x60;
        var endR   = 0;    var endG   = 0x05; var endB   = 0x10;
        for (var i = numRings - 1; i >= 0; i--) {
            var ratio = i.toFloat() / (numRings - 1);
            var r     = startR + (endR - startR) * ratio;
            var g     = startG + (endG - startG) * ratio;
            var b     = startB + (endB - startB) * ratio;
            var color = (r.toLong() << 16) | (g.toLong() << 8) | b.toLong();
            var ringRadius = maxRadius * (i + 1) / numRings;
            dc.setColor(color.toNumber(), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(_centerX, _centerY, ringRadius);
        }

        // Champ d'étoiles — 200 étoiles, tailles et luminosités variées
        var width  = dc.getWidth();
        var height = dc.getHeight();
        var seed   = 1;
        for (var i = 0; i < 200; i++) {
            seed = (seed * 1664525 + 1013904223) & 0x7FFFFFFF;
            var x = seed % width;
            seed = (seed * 1664525 + 1013904223) & 0x7FFFFFFF;
            var y = seed % height;
            seed = (seed * 1664525 + 1013904223) & 0x7FFFFFFF;
            var bright = seed % 3;
            var size   = (seed % 10 > 8) ? 2 : 1;
            if (bright == 2)      { dc.setColor(0xCCCCCC, Graphics.COLOR_TRANSPARENT); }
            else if (bright == 1) { dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT); }
            else                  { dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT); }
            dc.fillCircle(x, y, size);
        }
    }

    // Bezel + ticks + marqueurs heures — unifié pour les deux modes
    // isAod=true : couleurs atténuées anti burn-in, marqueurs simples
    // isAod=false : couleurs vives, marqueurs lume polygonaux
    private function drawBezelAndTicks(dc as Dc, isAod as Boolean) as Void {
        // Anneau bezel
        dc.setColor(_colorBezel, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(20);
        dc.drawCircle(_centerX, _centerY, _radius - 10);

        // Ticks 60 graduations
        var innerRad = _radius - 20;
        dc.setPenWidth(2);
        for (var i = 0; i < 60; i++) {
            var angle   = (i / 60.0) * Math.PI * 2;
            var c       = Math.cos(angle);
            var s       = Math.sin(angle);
            var tickLen = (i % 5 == 0) ? 10 : 5;
            if (isAod) {
                dc.setColor((i % 5 == 0) ? 0x666666 : 0x333333, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setColor(_colorTicks, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawLine(
                _centerX + (innerRad - tickLen) * c, _centerY + (innerRad - tickLen) * s,
                _centerX + innerRad * c,             _centerY + innerRad * s
            );
        }

        // Anneau de chapitre séparateur
        dc.setColor(isAod ? 0x444444 : 0x888888, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(_centerX, _centerY, innerRad - 12);

        // Marqueurs heures
        for (var i = 0; i < 12; i++) {
            var angle = (i / 12.0) * Math.PI * 2 - Math.PI / 2;
            var dist  = _radius - 27;
            var mcos  = Math.cos(angle);
            var msin  = Math.sin(angle);
            var mx    = _centerX + dist * mcos;
            var my    = _centerY + dist * msin;

            if (isAod) {
                // AOD : barres simples très atténuées
                if (i == 0) {
                    dc.setColor(0x3a3a3a, Graphics.COLOR_TRANSPARENT);
                    var barLen = 18.0; var barOff = 2.5;
                    for (var b = -1; b <= 1; b += 2) {
                        var bx = mx + b * barOff * (-msin);
                        var by = my + b * barOff * mcos;
                        dc.setPenWidth(1);
                        dc.drawLine(
                            (bx + (barLen*0.5)*mcos).toNumber(), (by + (barLen*0.5)*msin).toNumber(),
                            (bx - (barLen*0.5)*mcos).toNumber(), (by - (barLen*0.5)*msin).toNumber()
                        );
                    }
                } else {
                    dc.setColor(0x2e2e2e, Graphics.COLOR_TRANSPARENT);
                    dc.setPenWidth(3);
                    dc.drawLine(
                        (mx + 7.0*mcos).toNumber(), (my + 7.0*msin).toNumber(),
                        (mx - 7.0*mcos).toNumber(), (my - 7.0*msin).toNumber()
                    );
                }
            } else {
                // Mode actif : marqueurs lume polygonaux
                dc.setColor(_colorLume, Graphics.COLOR_TRANSPARENT);
                if (i == 0) {
                    var barLen = 18.0; var barHW = 1.0; var barOff = 2.5;
                    for (var b = -1; b <= 1; b += 2) {
                        var bx = mx + b * barOff * (-msin);
                        var by = my + b * barOff * mcos;
                        var bp1 = [(bx + (barLen*0.5)*mcos - barHW*msin).toNumber(), (by + (barLen*0.5)*msin + barHW*mcos).toNumber()];
                        var bp2 = [(bx + (barLen*0.5)*mcos + barHW*msin).toNumber(), (by + (barLen*0.5)*msin - barHW*mcos).toNumber()];
                        var bp3 = [(bx - (barLen*0.5)*mcos + barHW*msin).toNumber(), (by - (barLen*0.5)*msin - barHW*mcos).toNumber()];
                        var bp4 = [(bx - (barLen*0.5)*mcos - barHW*msin).toNumber(), (by - (barLen*0.5)*msin + barHW*mcos).toNumber()];
                        dc.fillPolygon([bp1, bp2, bp3, bp4]);
                    }
                } else {
                    var markerLen = 14.0; var hw = 3.0;
                    var p1 = [(mx + (markerLen*0.5)*mcos - hw*msin).toNumber(), (my + (markerLen*0.5)*msin + hw*mcos).toNumber()];
                    var p2 = [(mx + (markerLen*0.5)*mcos + hw*msin).toNumber(), (my + (markerLen*0.5)*msin - hw*mcos).toNumber()];
                    var p3 = [(mx - (markerLen*0.5)*mcos + hw*msin).toNumber(), (my - (markerLen*0.5)*msin - hw*mcos).toNumber()];
                    var p4 = [(mx - (markerLen*0.5)*mcos - hw*msin).toNumber(), (my - (markerLen*0.5)*msin + hw*mcos).toNumber()];
                    dc.fillPolygon([p1, p2, p3, p4]);
                }
            }
        }
    }

    private function drawSubdials(dc as Dc, isAod as Boolean) as Void {
        var subRadius = (_radius * 0.25).toNumber();
        var offset    = (_radius * 0.55).toNumber();

        var type9 = "SunConst";
        var type3 = "EqTime";
        // En AOD, le chrono n'est pas affiché — on garde SunConst/EqTime
        if (!isAod && _chrono.isActive()) {
            type9 = "ChronoMin";
            type3 = "ChronoSec";
        }

        var pos9 = getPolar(_centerX, _centerY, offset, 180);
        drawSubdial(dc, pos9[0], pos9[1], subRadius, type9, isAod);

        var pos3 = getPolar(_centerX, _centerY, offset, 0);
        drawSubdial(dc, pos3[0], pos3[1], subRadius, type3, isAod);

        var offset6 = (offset * 0.75).toNumber();
        var pos6    = getPolar(_centerX, _centerY, offset6, 90);
        drawSubdial(dc, pos6[0], pos6[1], subRadius, "Moon", isAod);
    }

    private function drawSubdial(dc as Dc, x as Number, y as Number, r as Number, type as String, isAod as Boolean) as Void {
        // Fond
        dc.setColor(isAod ? 0x080808 : 0x020202, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, isAod ? r : r + 2);
        dc.setColor(0x0e0e0e, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);

        if (!isAod) {
            // Biseau 3D — mode actif uniquement
            dc.setPenWidth(4);
            dc.setColor(0x000000, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(x, y, r, Graphics.ARC_CLOCKWISE, 0, 180);
            dc.setPenWidth(2);
            dc.drawArc(x, y, r, Graphics.ARC_CLOCKWISE, 270, 0);
            dc.setPenWidth(4);
            dc.setColor(0x484848, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(x, y, r, Graphics.ARC_COUNTER_CLOCKWISE, 0, 180);
            dc.setPenWidth(2);
            dc.setColor(0x707070, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(x, y, r, Graphics.ARC_COUNTER_CLOCKWISE, 90, 180);
            dc.setPenWidth(1);
            dc.setColor(0x1e1e1e, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(x, y, r - 2);

            // Icônes phases lunaires — mode actif uniquement
            if (type.equals("Moon")) {
                var iconRad = 6;
                var iconDist = r + 12;
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y - iconDist, iconRad);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(x, y - iconDist, iconRad);
                dc.fillCircle(x + iconDist, y, iconRad);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x + iconDist - iconRad, y - iconRad, iconRad, iconRad * 2);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(x + iconDist, y, iconRad);
                dc.fillCircle(x, y + iconDist, iconRad);
                dc.fillCircle(x - iconDist, y, iconRad);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x - iconDist, y - iconRad, iconRad, iconRad * 2);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(x - iconDist, y, iconRad);
            }

            // Ticks subdial — mode actif uniquement
            if (type.equals("EqTime")) {
                // Ticks personnalisés : 0, ±5, ±10, ±15 min
                // Mapping : 0 min → 12h, 1 min = 5° → ±15 min = ±75°
                // Valeurs en minutes à marquer
                var eotMarks  = [0, 5, -5, 10, -10, 15, -15] as Array<Number>;
                var markLong  = [true, false, false, false, false, true, true] as Array<Boolean>;
                dc.setPenWidth(1);
                for (var m = 0; m < eotMarks.size(); m++) {
                    // angle : 0 min → -π/2 (12h), +5 min → +25° dans le sens horaire
                    var markAngle = (eotMarks[m].toDouble() / 72.0) * Math.PI * 2 - Math.PI / 2;
                    var cosM = Math.cos(markAngle);
                    var sinM = Math.sin(markAngle);
                    var tickLen = markLong[m] ? 6 : 3;

                    if (eotMarks[m] == 0) {
                        // Repère 0 : triangle pointant vers l'intérieur (comme repère 12h standard)
                        dc.setColor(0x00CCFF, Graphics.COLOR_TRANSPARENT);
                        var pTA = [(x + (r-7) * cosM).toNumber(),              (y + (r-7) * sinM).toNumber()];
                        var pTL = [(x + (r-1) * cosM - 2.5 * sinM).toNumber(), (y + (r-1) * sinM + 2.5 * cosM).toNumber()];
                        var pTR = [(x + (r-1) * cosM + 2.5 * sinM).toNumber(), (y + (r-1) * sinM - 2.5 * cosM).toNumber()];
                        dc.fillPolygon([pTA, pTL, pTR]);
                    } else {
                        // ±5, ±10, ±15 : ticks proportionnels
                        dc.setColor(eotMarks[m] > 0 ? 0x00AACC : 0x0088AA, Graphics.COLOR_TRANSPARENT);
                        dc.drawLine(
                            (x + (r - tickLen) * cosM).toNumber(), (y + (r - tickLen) * sinM).toNumber(),
                            (x + r * cosM).toNumber(),             (y + r * sinM).toNumber()
                        );
                    }
                }

                // Label "EoT" sous le cadran
                dc.setColor(0x006688, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, y + r + 7, Graphics.FONT_XTINY, "EoT", Graphics.TEXT_JUSTIFY_CENTER);

            } else {
                // Ticks génériques pour les autres subdials
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
                for (var i = 0; i < 12; i++) {
                    var tAngle = (i / 12.0) * Math.PI * 2 - Math.PI / 2;
                    var cosT = Math.cos(tAngle);
                    var sinT = Math.sin(tAngle);
                    if (i == 0) {
                        var pTA = [(x + (r-7) * cosT).toNumber(),              (y + (r-7) * sinT).toNumber()];
                        var pTL = [(x + (r-1) * cosT - 2.5 * sinT).toNumber(), (y + (r-1) * sinT + 2.5 * cosT).toNumber()];
                        var pTR = [(x + (r-1) * cosT + 2.5 * sinT).toNumber(), (y + (r-1) * sinT - 2.5 * cosT).toNumber()];
                        dc.fillPolygon([pTA, pTL, pTR]);
                    } else {
                        var tickLen = (i % 3 == 0) ? 4 : 2;
                        dc.drawLine(x + (r-tickLen)*cosT, y + (r-tickLen)*sinT, x + r*cosT, y + r*sinT);
                    }
                }
            }
        } else {
            // AOD : anneau atténué uniquement
            dc.setColor(0x252525, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawCircle(x, y, r);
        }

        // Calcul de la valeur
        var val = 0.0;
        if (type.equals("SunConst")) {
            val = _cachedSunProgress;
            if (!isAod) {
                dc.setColor(0xFFCC44, Graphics.COLOR_TRANSPARENT); // doré solaire
                dc.drawText(x, y, Graphics.FONT_XTINY, _cachedSunConst, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        } else if (type.equals("EqTime")) {
            // Mapping centré : 0 min → 12h (val=0.0), 1 min = 5° (72 min = tour complet)
            val = _cachedEqTime / 72.0;
            if (!isAod) {
                var eotRounded = _cachedEqTime.toNumber();
                var eotStr = (eotRounded >= 0) ? "+" + eotRounded.toString() + "m" : eotRounded.toString() + "m";
                dc.setColor(0x00CCFF, Graphics.COLOR_TRANSPARENT); // cyan astronomique
                dc.drawText(x, y, Graphics.FONT_XTINY, eotStr, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        } else if (type.equals("Moon")) {
            val = _cachedMoonPhase;
        } else if (type.equals("ChronoMin")) {
            var elapsedSec = _chrono.elapsedSeconds(Time.now().value());
            val = ((elapsedSec / 60) % 60) / 60.0;
            if (!isAod) {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, y + r + 7, Graphics.FONT_XTINY, "MIN", Graphics.TEXT_JUSTIFY_CENTER);
            }
        } else if (type.equals("ChronoSec")) {
            var elapsedSec = _chrono.elapsedSeconds(Time.now().value());
            val = (elapsedSec % 60) / 60.0;
            if (!isAod) {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, y + r + 7, Graphics.FONT_XTINY, "SEC", Graphics.TEXT_JUSTIFY_CENTER);
            }
        }

        var angle = val * Math.PI * 2 - Math.PI / 2;
        var cos   = Math.cos(angle);
        var sin   = Math.sin(angle);

        if (isAod) {
            // AOD : aiguille simple ligne, dorée pour SunConst
            var aodColor = type.equals("SunConst") ? 0x664400
                         : type.equals("EqTime")   ? 0x004455
                         : 0x888888;
            dc.setColor(0x1a1a1a, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x, y, (x - (r*0.25)*cos).toNumber(), (y - (r*0.25)*sin).toNumber());
            dc.setColor(aodColor, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawLine(x, y, (x + (r*0.82)*cos).toNumber(), (y + (r*0.82)*sin).toNumber());
            dc.setColor(0x444444, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 2);
        } else {
            // Mode actif : aiguille needle avec contrepoids et cap
            var handLen = (r * 0.88).toFloat();
            var ctLen   = (r * 0.28).toFloat();
            var hw      = 1.5;
            var ctHW    = 2.5;
            var handColor = _colorHandMain;
            if (type.equals("SunConst")) {
                handColor = 0xFFAA00; // doré solaire
            } else if (type.equals("EqTime")) {
                handColor = 0x00CCFF; // cyan astronomique
            }
            var pCTip = [(x - ctLen*cos).toNumber(),  (y - ctLen*sin).toNumber()];
            var pCL   = [(x - ctHW*sin).toNumber(),   (y + ctHW*cos).toNumber()];
            var pCR   = [(x + ctHW*sin).toNumber(),   (y - ctHW*cos).toNumber()];
            dc.setColor(0x2a2a2a, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([pCTip, pCL, pCR]);
            var pNTip = [(x + handLen*cos).toNumber(), (y + handLen*sin).toNumber()];
            var pNL   = [(x - hw*sin).toNumber(),      (y + hw*cos).toNumber()];
            var pNR   = [(x + hw*sin).toNumber(),      (y - hw*cos).toNumber()];
            dc.setColor(handColor, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([pNTip, pNL, pNR]);
            dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([pNTip, [x, y], pNR]);
            dc.setColor(0x999999, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 4);
            dc.setColor(0x111111, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(x, y, 4);
            dc.setColor(0xDDDDDD, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x, y, 2);
        }
    }
    
    // Calculs astronomiques (Soleil, constellations, équation du temps, lune)
    // extraits dans le module pur AstroCalc — voir source/AstroCalc.mc (P2).


    private function getPolar(cx as Number, cy as Number, r as Number, angleDeg as Number) as Array<Number> {
        var angleRad = angleDeg * Math.PI / 180.0;
        var x = cx + r * Math.cos(angleRad);
        var y = cy + r * Math.sin(angleRad);
        return [x.toNumber(), y.toNumber()];
    }
    private function drawBranding(dc as Dc, isAod as Boolean) as Void {
        if (isAod) {
            // AOD : branding très atténué, anti burn-in
            dc.setColor(0x222222, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY - (_radius * 0.35).toNumber(),
                        Graphics.FONT_TINY, "MOON WATCH",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(0x181818, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY - (_radius * 0.24).toNumber(),
                        Graphics.FONT_XTINY, "AUTOMATIC",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.setColor(_colorLogo, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY - (_radius * 0.35).toNumber(),
                        Graphics.FONT_TINY, "MOON WATCH",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(0x888888, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_centerX, _centerY - (_radius * 0.24).toNumber(),
                        Graphics.FONT_XTINY, "AUTOMATIC",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    private function drawTachymeter(dc as Dc) as Void {
        // Tachymeter scale on the outer bezel ring (_radius-20 to _radius)
        var bezelOuter   = _radius - 2;
        var majorInner   = _radius - 13;  // long tick for labelled values
        var minorInner   = _radius - 8;   // short tick for intermediate values
        var labelR       = _radius - 18;  // text radius (inside bezel ring)

        // Major values (tick + label)
        var majorVals = [500, 400, 300, 200, 150, 125, 100, 90, 80, 70] as Array<Number>;
        // Minor values (tick only)
        var minorVals = [450, 350, 275, 250, 225, 175, 160, 140, 130, 120, 110, 95, 85, 75, 65] as Array<Number>;

        dc.setPenWidth(1);

        for (var i = 0; i < minorVals.size(); i++) {
            var val = minorVals[i];
            var screenRad = (21600.0 / val - 90.0) * Math.PI / 180.0;
            var cosA = Math.cos(screenRad);
            var sinA = Math.sin(screenRad);
            dc.setColor(0x777777, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(
                (_centerX + bezelOuter * cosA).toNumber(),
                (_centerY + bezelOuter * sinA).toNumber(),
                (_centerX + minorInner * cosA).toNumber(),
                (_centerY + minorInner * sinA).toNumber()
            );
        }

        for (var i = 0; i < majorVals.size(); i++) {
            var val = majorVals[i];
            var screenRad = (21600.0 / val - 90.0) * Math.PI / 180.0;
            var cosA = Math.cos(screenRad);
            var sinA = Math.sin(screenRad);
            // Major tick — brighter
            dc.setColor(0xCCCCCC, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(
                (_centerX + bezelOuter * cosA).toNumber(),
                (_centerY + bezelOuter * sinA).toNumber(),
                (_centerX + majorInner * cosA).toNumber(),
                (_centerY + majorInner * sinA).toNumber()
            );
            // Label
            dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
            dc.drawText(
                (_centerX + labelR * cosA).toNumber(),
                (_centerY + labelR * sinA).toNumber(),
                Graphics.FONT_XTINY, val.toString(),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER
            );
        }
    }
    private function drawHands(dc as Dc) as Void {
        var clockTime = System.getClockTime();
        var hour = clockTime.hour;
        var min = clockTime.min;

        var hourAngle = ((hour % 12) * 60 + min) / (12 * 60.0) * Math.PI * 2 - Math.PI / 2;
        var minAngle = min / 60.0 * Math.PI * 2 - Math.PI / 2;

        dc.setColor(_colorHandMain, Graphics.COLOR_TRANSPARENT);
        
        // Hour Hand
        drawBatonHand(dc, hourAngle, (_radius * 0.5).toNumber(), 9, 16, 0x555555);
        
        // Minute Hand
        drawBatonHand(dc, minAngle, (_radius * 0.75).toNumber(), 8, 12, 0x888888);
        
    }
    
    private function drawSeconds(dc as Dc) as Void {
        // Chrono ON → sweep from 0 (for tachymeter reading)
        // Chrono OFF → regular clock seconds
        var secFrac = 0.0;
        if (_chrono.isActive()) {
            var chronoSec = _chrono.elapsedSeconds(Time.now().value()) % 60;
            secFrac = chronoSec / 60.0;
        } else {
            secFrac = System.getClockTime().sec / 60.0;
        }
        var secAngle = secFrac * Math.PI * 2 - Math.PI / 2;

        var cos = Math.cos(secAngle);
        var sin = Math.sin(secAngle);

        var fwdLen  = (_radius * 0.78).toNumber();
        var tailLen = (_radius * 0.22).toNumber();

        // --- Contrepoids rouge (derrière le centre, dessiné en premier) ---
        var tw  = 3.5; // demi-largeur à la base du contrepoids
        var tw2 = 1.5; // demi-largeur à la pointe du contrepoids
        var pT1 = [(_centerX - tw  * sin).toNumber(), (_centerY + tw  * cos).toNumber()];
        var pT2 = [(_centerX + tw  * sin).toNumber(), (_centerY - tw  * cos).toNumber()];
        var pT3 = [(_centerX - tailLen * cos + tw2 * sin).toNumber(), (_centerY - tailLen * sin - tw2 * cos).toNumber()];
        var pT4 = [(_centerX - tailLen * cos - tw2 * sin).toNumber(), (_centerY - tailLen * sin + tw2 * cos).toNumber()];
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pT1, pT2, pT3, pT4]);

        // --- Aiguille fine blanche vers l'avant ---
        var xFwd = (_centerX + fwdLen * cos).toNumber();
        var yFwd = (_centerY + fwdLen * sin).toNumber();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(_centerX, _centerY, xFwd, yFwd);

        // --- Disque lollipop rouge (à ~63% du rayon) ---
        var discDist = (_radius * 0.63).toNumber();
        var xDisc = (_centerX + discDist * cos).toNumber();
        var yDisc = (_centerY + discDist * sin).toNumber();
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(xDisc, yDisc, 5);

        // Re-trace la ligne fine blanche par-dessus le disque
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(_centerX, _centerY, xFwd, yFwd);

        // Disque du moyeu de la trotteuse (sommet du cône) — au premier plan,
        // la trotteuse reste donc devant et solidaire de son cercle.
        drawHubTop(dc);
    }

    private function drawBatonHand(dc as Dc, angle as Float, length as Number, width as Number, capRadius as Number, capColor as Number) as Void {
        // Style "Baton" Speedmaster : largeur constante du moyeu à la pointe,
        // base pleine largeur de la couleur du moyeu (capColor) près du pivot,
        // corps blanc ombré 3D, pointe triangulaire biseautée.
        // Termine par son propre disque de moyeu (capRadius/capColor) pour que
        // l'aiguille paraisse solidaire de son cercle et s'empile proprement.
        var shadowColor = Graphics.COLOR_LT_GRAY;
        var mainColor   = _colorHandMain;

        var cos = Math.cos(angle);
        var sin = Math.sin(angle);

        var tailLen    = 4;                // talon caché sous le cap central
        var halfWidth  = width / 2.0;

        var baseEnd    = length * 0.30;    // fin de la base grise = départ du lume
        var taperStart = length * 0.87;    // début de la pointe

        // Formule de transformation locale → écran :
        //   x_screen = cx + lx·cos − ly·sin
        //   y_screen = cy + lx·sin + ly·cos

        // --- Points du fût (largeur constante : talon → début de pointe) ---
        var pBaseL  = [_centerX + (-tailLen)  * cos - (-halfWidth) * sin, _centerY + (-tailLen)  * sin + (-halfWidth) * cos];
        var pBaseR  = [_centerX + (-tailLen)  * cos - ( halfWidth) * sin, _centerY + (-tailLen)  * sin + ( halfWidth) * cos];
        var pMidL   = [_centerX +  baseEnd    * cos - (-halfWidth) * sin, _centerY +  baseEnd    * sin + (-halfWidth) * cos];
        var pMidR   = [_centerX +  baseEnd    * cos - ( halfWidth) * sin, _centerY +  baseEnd    * sin + ( halfWidth) * cos];
        var pMidC   = [_centerX +  baseEnd    * cos,                      _centerY +  baseEnd    * sin];
        var pTaperL = [_centerX +  taperStart * cos - (-halfWidth) * sin, _centerY +  taperStart * sin + (-halfWidth) * cos];
        var pTaperR = [_centerX +  taperStart * cos - ( halfWidth) * sin, _centerY +  taperStart * sin + ( halfWidth) * cos];
        var pTaperC = [_centerX +  taperStart * cos,                      _centerY +  taperStart * sin];
        var pTip    = [_centerX +  length.toFloat() * cos,                _centerY +  length.toFloat() * sin];

        // === Contours noirs ===
        var outlineW = 1.5;
        var oHW = halfWidth + outlineW;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);

        // Contour du fût (rectangle pleine largeur, talon → début de pointe)
        var obBaseL  = [_centerX + (-tailLen)  * cos - (-oHW) * sin, _centerY + (-tailLen)  * sin + (-oHW) * cos];
        var obBaseR  = [_centerX + (-tailLen)  * cos - ( oHW) * sin, _centerY + (-tailLen)  * sin + ( oHW) * cos];
        var obTaperL = [_centerX +  taperStart * cos - (-oHW) * sin, _centerY +  taperStart * sin + (-oHW) * cos];
        var obTaperR = [_centerX +  taperStart * cos - ( oHW) * sin, _centerY +  taperStart * sin + ( oHW) * cos];
        dc.fillPolygon([obTaperL, obTaperR, obBaseR, obBaseL]);

        // Contour de la pointe (triangle)
        var opTip = [_centerX + (length.toFloat() + outlineW) * cos, _centerY + (length.toFloat() + outlineW) * sin];
        dc.fillPolygon([opTip, obTaperL, obTaperR]);

        // === Base pleine largeur (talon → départ du lume) ===
        // Couleur du disque de moyeu pour que l'aiguille paraisse coulée dans son cercle.
        dc.setColor(capColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pBaseL, pBaseR, pMidR, pMidL]);

        // === Corps (rectangle pleine largeur) ===
        dc.setColor(mainColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pMidL, pMidR, pTaperR, pTaperL]);

        // Ombre moitié droite du corps
        dc.setColor(shadowColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pMidR, pMidC, pTaperC, pTaperR]);

        // === Pointe (triangle corps → pointe) — 3 facettes biseautées ===
        // Base : triangle complet en mainColor
        dc.setColor(mainColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pTip, pTaperL, pTaperR]);

        // Facette gauche (highlight) : arête lumineuse côté gauche
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pTip, pTaperL, pTaperC]);

        // Facette droite (ombre) : arête sombre côté droit
        dc.setColor(shadowColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pTip, pTaperR, pTaperC]);

        // Arête centrale brillante (filet de lumière)
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(pTaperC[0], pTaperC[1], pTip[0], pTip[1]);

        // Cap lume à la pointe — goutte effilée (teardrop)
        if (_isInSleepMode) {
            dc.setColor(_colorLume, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        }
        var gouteLen  = 5.0;                 // longueur de la goutte sous la pointe
        var gouteHalf = 2.0;                 // demi-largeur du bulbe
        var gouteBase = length.toFloat() - gouteLen;
        var pGouteL = [_centerX + gouteBase * cos - (-gouteHalf) * sin, _centerY + gouteBase * sin + (-gouteHalf) * cos];
        var pGouteR = [_centerX + gouteBase * cos - ( gouteHalf) * sin, _centerY + gouteBase * sin + ( gouteHalf) * cos];
        var pGouteC = [_centerX + gouteBase * cos,                      _centerY + gouteBase * sin];
        dc.fillPolygon([pTip, pGouteL, pGouteR]);             // corps effilé vers la pointe
        dc.fillCircle(pGouteC[0].toNumber(), pGouteC[1].toNumber(), gouteHalf.toNumber()); // bulbe arrondi

        // === Lume slot (30% → 82%, centré sur le corps) ===
        var lumeStart = length * 0.30;
        var lumeEnd   = length * 0.82;
        var lumeWidth = halfWidth * 0.5;

        var pL1 = [_centerX + lumeStart * cos - (-lumeWidth) * sin, _centerY + lumeStart * sin + (-lumeWidth) * cos];
        var pL2 = [_centerX + lumeEnd   * cos - (-lumeWidth) * sin, _centerY + lumeEnd   * sin + (-lumeWidth) * cos];
        var pL3 = [_centerX + lumeEnd   * cos - ( lumeWidth) * sin, _centerY + lumeEnd   * sin + ( lumeWidth) * cos];
        var pL4 = [_centerX + lumeStart * cos - ( lumeWidth) * sin, _centerY + lumeStart * sin + ( lumeWidth) * cos];

        dc.setColor(_colorLume, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pL1, pL2, pL3, pL4]);

        // Disque du moyeu propre à cette aiguille — dessiné juste après son corps
        // pour que l'aiguille paraisse solidaire de son cercle, et que l'aiguille
        // suivante (puis la trotteuse) s'empile correctement par-dessus.
        dc.setColor(capColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_centerX, _centerY, capRadius);
    }

    // Sommet du moyeu : petit disque clair des secondes + pivot, achevant le
    // dégradé heures (Ø max, foncé) → secondes (Ø min, clair). En mode actif il
    // est dessiné par la trotteuse (premier plan) ; en veille, après les aiguilles.
    private function drawHubTop(dc as Dc) as Void {
        dc.setColor(0xCCCCCC, Graphics.COLOR_TRANSPARENT);             // secondes (Ø min)
        dc.fillCircle(_centerX, _centerY, 8);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT); // pivot
        dc.fillCircle(_centerX, _centerY, 4);
    }

    private function drawConcentricBackground(dc as Dc) as Void {
        var numRings = 40; // Optimum pour le mode actif (redessine chaque seconde)
        var maxRadius = _radius + 20;

        // Opalin : centre plus clair, bords plus sombres
        var startR = 0;      // centre
        var startG = 0x40;
        var startB = 0x60;

        var endR = 0;        // bord extérieur
        var endG = 0x05;
        var endB = 0x10;

        // Draw concentric circles from largest (outer) to smallest (inner)
        for (var i = numRings - 1; i >= 0; i--) {
            var ratio = i.toFloat() / (numRings - 1);
            
            // Interpolate colors
            var r = startR + (endR - startR) * ratio;
            var g = startG + (endG - startG) * ratio;
            var b = startB + (endB - startB) * ratio;
            
            var color = (r.toLong() << 16) | (g.toLong() << 8) | b.toLong();
            
            var ringRadius = maxRadius * (i + 1) / numRings;
            
            dc.setColor(color.toNumber(), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(_centerX, _centerY, ringRadius);
        }
    }

    private function drawStarField(dc as Dc) as Void {
        var numStars = 200;
        var width    = dc.getWidth();
        var height   = dc.getHeight();
        var seed     = 1;

        for (var i = 0; i < numStars; i++) {
            seed = (seed * 1664525 + 1013904223) & 0x7FFFFFFF;
            var x = seed % width;
            seed = (seed * 1664525 + 1013904223) & 0x7FFFFFFF;
            var y = seed % height;
            seed = (seed * 1664525 + 1013904223) & 0x7FFFFFFF;
            var bright = seed % 3; // 0=dim, 1=mid, 2=bright
            var size   = (seed % 10 > 7) ? 2 : 1;
            if (bright == 2)      { dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT); }
            else if (bright == 1) { dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT); }
            else                  { dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT); }
            dc.fillCircle(x, y, size);
        }
    }

    // The user has just looked at their watch. Timers and animations may be started here.
    function onExitSleep() as Void {
        _isInSleepMode = false;
        WatchUi.requestUpdate();
    }

    // Terminate any active timers and prepare for slow updates.
    function onEnterSleep() as Void {
        _isInSleepMode = true;
        WatchUi.requestUpdate();
    }

}
