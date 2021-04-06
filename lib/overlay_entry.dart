import 'package:flutter/widgets.dart';
import 'package:flutter_boost/boost_container.dart';

final GlobalKey<OverlayState> overlayKey = GlobalKey<OverlayState>();
List<_ContainerOverlayEntry> _lastEntries;
// 刷新 Overlay 实例
void refreshOverlayEntries(List<BoostContainer> containers) {
  final OverlayState overlayState = overlayKey.currentState;
  if (overlayState == null) {
    return;
  }
  // 将 _lastEntries 中的实例全部移除
  if (_lastEntries != null && _lastEntries.isNotEmpty) {
    for (_ContainerOverlayEntry entry in _lastEntries) {
      entry.remove();
    }
  }
  // 然后重新创建
  _lastEntries = containers
      .map<_ContainerOverlayEntry>(
          (BoostContainer container) => _ContainerOverlayEntry(container))
      .toList(growable: false);
  // 显示
  overlayState.insertAll(_lastEntries);
}

class _ContainerOverlayEntry extends OverlayEntry {
  _ContainerOverlayEntry(BoostContainer container)
      : super(
            builder: (BuildContext ctx) => container,
            opaque: true,
            maintainState: true);
  bool _removed = false;

  @override
  void remove() {
    assert(!_removed);

    if (_removed) {
      return;
    }

    _removed = true;
    super.remove();
  }
}
