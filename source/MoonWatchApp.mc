import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class MoonWatchApp extends Application.AppBase {

    private var _view as MoonWatchView?;

    function initialize() {
        AppBase.initialize();
        _view = null;
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Called when the user changes a setting in Garmin Connect
    function onSettingsChanged() as Void {
        if (_view != null) {
            (_view as MoonWatchView).applyChronoSettings();
        }
        WatchUi.requestUpdate();
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new MoonWatchView();
        _view = view;
        var delegate = new MoonWatchDelegate();
        return [view, delegate];
    }

}
