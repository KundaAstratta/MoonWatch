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
    private var _isChronoRunning as Boolean = false;
    private var _chronoStartTime as Long = 0l;
    private var _chronoElapsedTime as Long = 0l;

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
    }

    // Applies the chronoState setting from Garmin Connect
    // 0 = Reset  : hand returns to 12h, clock seconds resume
    // 1 = Running : hand sweeps from 0, tachymeter readable
    // 2 = Paused  : hand freezes on last value, tachymeter still readable
    public function applyChronoSettings() as Void {
        var val = Application.Properties.getValue("chronoState");
        var state = (val instanceof Number) ? val as Number : 0;
        if (state == 1) {
            // Start / Restart — always resets elapsed so hand departs from 12h
            _chronoElapsedTime = 0l;
            _chronoStartTime = System.getTimer().toLong();
            _isChronoRunning = true;
        } else if (state == 2) {
            // Pause — capture elapsed, freeze hand on current tachymeter reading
            if (_isChronoRunning) {
                _chronoElapsedTime += System.getTimer().toLong() - _chronoStartTime;
            }
            _isChronoRunning = false;
            _chronoStartTime = 0l;
        } else {
            // Reset (state == 0) — clear everything, return to clock seconds
            _isChronoRunning = false;
            _chronoElapsedTime = 0l;
            _chronoStartTime = 0l;
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
            _cachedMoonPhase = getMoonPhase();
            _moonPhaseHour = currentHour;
        }
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var currentDay = info.day;
        if (currentDay != _sunCacheDay) {
            var sunData = getSunConstellation();
            _cachedSunConst    = sunData[0] as String;
            _cachedSunProgress = sunData[1] as Float;
            _sunCacheDay = currentDay;
        }
        if (currentDay != _eqTimeCacheDay) {
            _cachedEqTime    = getEquationOfTime();
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
            drawHands(dc);    // Heures et minutes en dessous
            drawSeconds(dc);  // Secondes tout en haut (convention horlogère)
        } else {
            // Sleep Mode (AOD): Anti burn-in — éléments atténués
            drawSleepBackground(dc);
            drawBezelAndTicks(dc, true);
            drawSubdials(dc, true);
            drawBranding(dc, true);
            drawHands(dc);
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
        // En AOD, le chrono n'est pas actif — on garde batterie/date
        if (!isAod && (_isChronoRunning || _chronoElapsedTime > 0)) {
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
            // Mapping centré : 0 min → 12h (val=0.0), plage ±20 min → ±100° sur le cadran
            // val = 0.5 + eot/72.0  (1 min = 5°, 20 min = 100° = 0.278 tour)
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
            var elapsed = _chronoElapsedTime;
            if (_isChronoRunning) { elapsed += System.getTimer().toLong() - _chronoStartTime; }
            val = ((elapsed / 1000) / 60 % 60) / 60.0;
            if (!isAod) {
                dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, y + r + 7, Graphics.FONT_XTINY, "MIN", Graphics.TEXT_JUSTIFY_CENTER);
            }
        } else if (type.equals("ChronoSec")) {
            var elapsed = _chronoElapsedTime;
            if (_isChronoRunning) { elapsed += System.getTimer().toLong() - _chronoStartTime; }
            val = ((elapsed / 1000) % 60) / 60.0;
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
    
    // Returns ecliptic longitude of the Sun in degrees [0, 360)
    // Low-precision algorithm (~0.01°), depends only on the date
    private function getSunEclipticLongitude() as Float {
        // Days since J2000.0 (2000-Jan-01 12:00 UTC = Unix 946728000)
        var d = (Time.now().value() - 946728000).toDouble() / 86400.0;

        // Mean longitude and mean anomaly (degrees) — modulo manuel (Double % Float non supporté)
        var L = 280.46 + 0.9856474 * d;
        L = L - 360.0 * Math.floor(L / 360.0);

        var g = 357.528 + 0.9856003 * d;
        g = g - 360.0 * Math.floor(g / 360.0);

        var gRad  = g  * Math.PI / 180.0;
        var g2Rad = 2.0 * gRad;

        // Equation of centre correction → ecliptic longitude
        var lambda = L + 1.915 * Math.sin(gRad) + 0.020 * Math.sin(g2Rad);
        lambda = lambda - 360.0 * Math.floor(lambda / 360.0);

        return lambda.toFloat();
    }

    // IAU zodiacal constellations traversed by the Sun (13, Ophiuchus included)
    // Returns [abbr, progress] where progress 0.0=entry 1.0=exit
    private function getSunConstellation() as Array {
        var lon = getSunEclipticLongitude().toDouble();

        // Séparation en 3 tableaux homogènes pour éviter les warnings de type
        var starts = [351.0, 29.0,  53.0,  90.0, 118.0, 138.0, 174.0, 218.0, 241.0, 247.0, 266.0, 299.0, 327.0] as Array<Double>;
        var ends   = [ 29.0, 53.0,  90.0, 118.0, 138.0, 174.0, 218.0, 241.0, 247.0, 266.0, 299.0, 327.0, 351.0] as Array<Double>;
        var abbrs  = ["PSC", "ARI", "TAU", "GEM", "CNC", "LEO", "VIR", "LIB", "SCO", "OPH", "SGR", "CAP", "AQR"] as Array<String>;

        for (var i = 0; i < starts.size(); i++) {
            var start = starts[i];
            var end   = ends[i];
            var abbr  = abbrs[i];

            var inConst = false;
            var progress = 0.0;

            if (start > end) {
                // Wraps through 0° (PSC: 351→29)
                var span = (360.0 - start) + end;
                if (lon >= start || lon < end) {
                    inConst = true;
                    var elapsed = (lon >= start) ? lon - start : (360.0 - start) + lon;
                    progress = elapsed / span;
                }
            } else {
                if (lon >= start && lon < end) {
                    inConst = true;
                    progress = (lon - start) / (end - start);
                }
            }

            if (inConst) {
                return [abbr, progress.toFloat()] as Array;
            }
        }

        // Fallback (should never happen)
        return ["---", 0.0f] as Array;
    }

    // Equation of Time — returns difference (true solar time − mean solar time) in minutes
    // Range: approx −14.3 min (early Feb) to +16.4 min (early Nov), two zero crossings per year
    // Algorithm: Spencer (1971) approximation, precision ~30 seconds
    private function getEquationOfTime() as Float {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);

        // Day of year (approx — ignores leap year, acceptable for EoT precision)
        var daysInMonth = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] as Array<Number>;
        var N = info.day;
        for (var m = 1; m < info.month; m++) {
            N += daysInMonth[m];
        }

        var B = 2.0 * Math.PI * (N - 81).toDouble() / 364.0;
        var eot = 9.87 * Math.sin(2.0 * B)
                - 7.53 * Math.cos(B)
                - 1.5  * Math.sin(B);

        return eot.toFloat(); // minutes, signed
    }

    // Calculates moon phase (0.0 to 0.99)
    // 0.0 = New Moon, 0.25 = First Quarter, 0.5 = Full Moon, 0.75 = Last Quarter
    private function getMoonPhase() as Float {
        var now = Time.now();
        
        // Known New Moon: January 6, 2000 at 12:24 UTC
        // Julian Date for Jan 6, 2000 is approx 2451550.1
        // Synodic Month = 29.530588853 days
        
        // Simpler approach: Use a reference date close to now or standard algorithm
        // Reference: 1970-01-07 20:35 UTC was a New Moon.
        
        // Algorithm (Conway's or simple elapsed days)
        // Let's use seconds since 1970 (Time.now().value())
        // Reference New Moon: Unix Timestamp 0 is 1970-01-01. 
        // 1970-01-07 20:35 UTC is approx 592500 seconds.
        
        var nowVal = now.value();
        var lunarCycle = 2551442.877; // 29.530588 * 24 * 3600
        var newMoonRef = 592500; // Early known new moon timestamp
        
        var diff = nowVal - newMoonRef;
        // if (diff < 0) { diff += lunarCycle; } // handled below

        // Manual modulo for floating point: a % n = a - (n * floor(a/n))
        // Or simpler: just get the fractional part of total cycles
        
        var totalCycles = diff.toDouble() / lunarCycle;
        var phase = totalCycles - totalCycles.toLong(); // Fractional part
        
        if (phase < 0) { phase += 1.0; }
        
        return phase.toFloat();
    }
    
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
        drawDauphineHand(dc, hourAngle, (_radius * 0.5).toNumber(), 9);
        
        // Minute Hand
        drawDauphineHand(dc, minAngle, (_radius * 0.75).toNumber(), 8);
        
    }
    
    private function drawSeconds(dc as Dc) as Void {
        // Chrono ON → sweep from 0 (for tachymeter reading)
        // Chrono OFF → regular clock seconds
        var secFrac = 0.0;
        if (_isChronoRunning || _chronoElapsedTime > 0) {
            var elapsed = _chronoElapsedTime;
            if (_isChronoRunning) { elapsed += System.getTimer().toLong() - _chronoStartTime; }
            var chronoSec = (elapsed / 1000) % 60;
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

        // --- Cap central argenté ---
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_centerX, _centerY, 5);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(_centerX, _centerY, 5);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_centerX, _centerY, 2);
    }

    private function drawDauphineHand(dc as Dc, angle as Float, length as Number, width as Number) as Void {
        // Style "Baïonnette" : corps pleine largeur jusqu'à 80%, puis section fine (40%) jusqu'à la pointe
        var shadowColor = Graphics.COLOR_LT_GRAY;
        var mainColor   = _colorHandMain;

        var cos = Math.cos(angle);
        var sin = Math.sin(angle);

        var tailLen    = 20;
        var halfWidth  = width / 2.0;

        // Épaule à 80%, section fine à 40% de largeur
        var xShoulder  = length * 0.8;
        var halfNarrow = halfWidth * 0.4;

        // Formule de transformation locale → écran :
        //   x_screen = cx + lx·cos − ly·sin
        //   y_screen = cy + lx·sin + ly·cos

        // --- Corps (−tailLen → épaule, pleine largeur) ---
        var pBaseL  = [_centerX + (-tailLen) * cos - (-halfWidth) * sin, _centerY + (-tailLen) * sin + (-halfWidth) * cos];
        var pBaseR  = [_centerX + (-tailLen) * cos - ( halfWidth) * sin, _centerY + (-tailLen) * sin + ( halfWidth) * cos];
        var pBaseC  = [_centerX + (-tailLen) * cos,                      _centerY + (-tailLen) * sin];
        var pShoulL = [_centerX +  xShoulder * cos - (-halfWidth) * sin, _centerY +  xShoulder * sin + (-halfWidth) * cos];
        var pShoulR = [_centerX +  xShoulder * cos - ( halfWidth) * sin, _centerY +  xShoulder * sin + ( halfWidth) * cos];
        var pShoulC = [_centerX +  xShoulder * cos,                      _centerY +  xShoulder * sin];

        // --- Section fine (épaule → pointe) ---
        var pNarrL  = [_centerX + xShoulder * cos - (-halfNarrow) * sin, _centerY + xShoulder * sin + (-halfNarrow) * cos];
        var pNarrR  = [_centerX + xShoulder * cos - ( halfNarrow) * sin, _centerY + xShoulder * sin + ( halfNarrow) * cos];
        var pTip    = [_centerX + length.toFloat() * cos,                _centerY + length.toFloat() * sin];

        // === Contours noirs ===
        var outlineW = 1.5;
        var oHW  = halfWidth  + outlineW;
        var oNar = halfNarrow + outlineW;

        // Contour du corps (rectangle)
        var opBaseL  = [_centerX + (-tailLen) * cos - (-oHW) * sin, _centerY + (-tailLen) * sin + (-oHW) * cos];
        var opBaseR  = [_centerX + (-tailLen) * cos - ( oHW) * sin, _centerY + (-tailLen) * sin + ( oHW) * cos];
        var opShoulL = [_centerX +  xShoulder * cos - (-oHW) * sin, _centerY +  xShoulder * sin + (-oHW) * cos];
        var opShoulR = [_centerX +  xShoulder * cos - ( oHW) * sin, _centerY +  xShoulder * sin + ( oHW) * cos];
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([opShoulL, opShoulR, opBaseR, opBaseL]);

        // Contour de la section fine (triangle)
        var opNarrL  = [_centerX + xShoulder * cos - (-oNar) * sin,           _centerY + xShoulder * sin + (-oNar) * cos];
        var opNarrR  = [_centerX + xShoulder * cos - ( oNar) * sin,           _centerY + xShoulder * sin + ( oNar) * cos];
        var opTip    = [_centerX + (length.toFloat() + outlineW) * cos,       _centerY + (length.toFloat() + outlineW) * sin];
        dc.fillPolygon([opTip, opNarrL, opNarrR]);

        // === Corps (rectangle pleine largeur) ===
        dc.setColor(mainColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pShoulL, pShoulR, pBaseR, pBaseL]);

        // Ombre moitié droite du corps
        dc.setColor(shadowColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pShoulR, pShoulC, pBaseC, pBaseR]);

        // === Section fine (triangle épaule → pointe) — 3 facettes biseautées ===
        // Base : triangle complet en mainColor
        dc.setColor(mainColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pTip, pNarrL, pNarrR]);

        // Facette gauche (highlight) : arête lumineuse côté gauche
        dc.setColor(0xFFFFFF, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pTip, pNarrL, pShoulC]);

        // Facette droite (ombre) : arête sombre côté droit
        dc.setColor(shadowColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pTip, pNarrR, pShoulC]);

        // Filet d'épaule (cran baïonnette) — plus marqué
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(pNarrL[0], pNarrL[1], pShoulL[0], pShoulL[1]);
        dc.drawLine(pNarrR[0], pNarrR[1], pShoulR[0], pShoulR[1]);

        // Cap lume à la pointe
        if (_isInSleepMode) {
            dc.setColor(_colorLume, Graphics.COLOR_TRANSPARENT);
        } else {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        }
        dc.fillCircle(pTip[0].toNumber(), pTip[1].toNumber(), 2);

        // === Lume slot (20% → épaule 80%) ===
        var lumeStart = length * 0.2;
        var lumeEnd   = xShoulder;
        var lumeWidth = halfWidth * 0.5;

        var pL1 = [_centerX + lumeStart * cos - (-lumeWidth) * sin, _centerY + lumeStart * sin + (-lumeWidth) * cos];
        var pL2 = [_centerX + lumeEnd   * cos - (-lumeWidth) * sin, _centerY + lumeEnd   * sin + (-lumeWidth) * cos];
        var pL3 = [_centerX + lumeEnd   * cos - ( lumeWidth) * sin, _centerY + lumeEnd   * sin + ( lumeWidth) * cos];
        var pL4 = [_centerX + lumeStart * cos - ( lumeWidth) * sin, _centerY + lumeStart * sin + ( lumeWidth) * cos];

        dc.setColor(_colorLume, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pL1, pL2, pL3, pL4]);

        // === Queue (contrepoids) — pleine largeur ===
        var pCentL = [(_centerX + halfWidth * sin).toNumber(), (_centerY - halfWidth * cos).toNumber()];
        var pCentR = [(_centerX - halfWidth * sin).toNumber(), (_centerY + halfWidth * cos).toNumber()];
        dc.setColor(shadowColor, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([pCentL, pCentR, pBaseR, pBaseL]);

        // === Cap central ===
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_centerX, _centerY, width * 0.8);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(_centerX, _centerY, width * 0.8);
        dc.fillCircle(_centerX, _centerY, 2);

        dc.setColor(_colorHandMain, Graphics.COLOR_TRANSPARENT);
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
