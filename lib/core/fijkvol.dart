//MIT License
//
//Copyright (c) [2019] [Befovy]
//
//Permission is hereby granted, free of charge, to any person obtaining a copy
//of this software and associated documentation files (the "Software"), to deal
//in the Software without restriction, including without limitation the rights
//to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//copies of the Software, and to permit persons to whom the Software is
//furnished to do so, subject to the following conditions:
//
//The above copyright notice and this permission notice shall be included in all
//copies or substantial portions of the Software.
//
//THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//SOFTWARE.

part of core;

/// [vol] is the value of volume, and has been mapped into range [0.0, 1.0]
/// true value of [sui] indicates that Android/iOS system volume changed UI is shown for this volume change event
/// [type] shows track\stream type for this volume change, this value is always [FijkVolume.STREAM_MUSIC] in this version
@immutable
class FijkVolumeVal {
  final double vol;
  final bool sui;
  final int type;

  const FijkVolumeVal({
    @required this.vol,
    @required this.sui,
    @required this.type,
  })  : assert(vol != null),
        assert(sui != null),
        assert(type != null);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FijkVolumeVal &&
          vol != 0.0 &&
          vol != 1.0 &&
          hashCode == other.hashCode);

  @override
  int get hashCode => hashValues(vol, sui, type);
}

class _VolumeValueNotifier extends ValueNotifier<FijkVolumeVal> {
  _VolumeValueNotifier(FijkVolumeVal value) : super(value);
}

/// Fijk System Volume Manger
class FijkVolume {
  FijkVolume._();

  static const int STREAM_VOICE_CALL = 0;
  static const int STREAM_SYSTEM = 1;
  static const int STREAM_RING = 2;
  static const int STREAM_MUSIC = 3;
  static const int STREAM_ALARM = 4;

  /// show system volume changed UI if no playable player
  /// hide system volume changed UI if some players are in playable state
  static const int hideUIWhenPlayable = 0;

  /// show system volume changed UI if no start state player
  /// hide system volume changed UI if some players are in start state
  static const int hideUIWhenPlaying = 1;

  /// never show system volume changed UI
  static const int neverShowUI = 2;

  /// always show system volume changed UI
  static const int alwaysShowUI = 3;

  static FijkVolume _instance = FijkVolume._();

  static _VolumeValueNotifier _notifer =
      _VolumeValueNotifier(FijkVolumeVal(vol: 0, sui: false, type: 0));

  static const double _defaultStep = 1.0 / 16.0;

  /// Mute system volume
  /// return system volume after mute
  static Future<double> mute() {
    return FijkPlugin._channel.invokeMethod("volumeMute");
  }

  /// set system volume to [vol]
  /// the range of [vol] is [0.0, 1,0]
  /// return the system volume value after set
  static Future<double> setVol(double vol) {
    if (vol == null) {
      return Future.error(ArgumentError.notNull("vol"));
    } else {
      return FijkPlugin._channel
          .invokeMethod("volumeSet", <String, dynamic>{'vol': vol});
    }
  }

  /// increase system volume by step
  /// return the system volume value after increase
  static Future<double> up({double step = _defaultStep}) {
    return FijkPlugin._channel
        .invokeMethod("volumeUp", <String, dynamic>{'step': step});
  }

  /// decrease system volume by step
  /// return the system volume value after decrease
  static Future<double> down({double step = _defaultStep}) {
    return FijkPlugin._channel
        .invokeMethod("volumeDown", <String, dynamic>{'step': step});
  }

  /// update the ui mode when system volume changed
  /// mode can be one of
  /// {[hideUIWhenPlayable], [hideUIWhenPlaying], [neverShowUI], [alwaysShowUI]}
  static Future<void> setUIMode(int mode) {
    if (mode == null)
      return Future.error(ArgumentError.notNull("mode"));
    else
      return FijkPlugin._channel
          .invokeMethod("volUiMode", <String, dynamic>{'mode': mode});
  }

  void _onVolCallback(double vol, bool ui) {
    _notifer.value = FijkVolumeVal(vol: vol, sui: ui, type: STREAM_MUSIC);
  }

  static void addListener(VoidCallback listener) {
    FijkPlugin._onLoad("vol");
    _notifer.addListener(listener);
  }

  static void removeListener(VoidCallback listener) {
    _notifer.removeListener(listener);
  }

  static get value => _notifer.value;
}

/// Volume changed callback func.
///
/// See [FijkVolumeVal]
/// [vol] is the value of volume, and has been mapped into range [0.0, 1.0]
/// true value of [ui] indicates that Android/iOS system volume changed UI is shown for this volume change event
/// [streamType] shows track\stream type for this volume change, this value is always [FijkVolume.STREAM_MUSIC] in this version
typedef FijkVolumeCallback = void Function(FijkVolumeVal value);

/// stateful widget that watching system volume, no ui widget
/// when system volume changed, [watcher] will be invoked.
class FijkVolumeWatcher extends StatefulWidget {
  /// volume changed callback
  final FijkVolumeCallback watcher;

  /// child widget, must be non-null
  final Widget child;

  /// whether show default volume changed toast, default value is false.
  ///
  /// The default toast ui insert an OverlayEntry to current context's overlay
  final bool showToast;

  FijkVolumeWatcher({
    @required this.watcher,
    @required this.child,
    bool showToast = false,
  })  : assert(child != null),
        showToast = showToast;

  @override
  _FijkVolumeWatcherState createState() => _FijkVolumeWatcherState();
}

class _FijkVolumeWatcherState extends State<FijkVolumeWatcher> {
  OverlayEntry _entry;
  Timer _timer;

  @override
  void initState() {
    super.initState();
    FijkVolume.addListener(volChanged);
    FijkVolume.setUIMode(FijkVolume.hideUIWhenPlayable);
  }

  void volChanged() {
    FijkVolumeVal value = FijkVolume.value;

    if (widget.watcher != null) {
      widget.watcher(value);
    }
    if (widget.showToast && !value.sui) {
      showVolToast(value.vol);
    }
  }

  /// reference https://www.kikt.top/posts/flutter/toast/oktoast/
  void showVolToast(double vol) {
    bool active = _timer?.isActive;
    _timer?.cancel();
    Widget widget = defaultFijkVolumeToast();
    if (active == null || active == false) {
      _entry = OverlayEntry(builder: (_) => widget);
      Overlay.of(context).insert(_entry);
    }
    _timer = Timer(const Duration(milliseconds: 1000), () {
      _entry?.remove();
    });
  }

  @override
  void dispose() {
    super.dispose();
    FijkVolume.removeListener(volChanged);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
