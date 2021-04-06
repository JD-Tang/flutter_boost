import 'dart:async';
import 'package:flutter_boost/boost_container.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_boost/messages.dart';
import 'package:flutter_boost/boost_flutter_router_api.dart';
import 'package:flutter_boost/logger.dart';
import 'package:flutter_boost/boost_navigator.dart';
import 'package:flutter_boost/page_visibility.dart';
import 'package:flutter_boost/overlay_entry.dart';

typedef FlutterBoostAppBuilder = Widget Function(Widget home);
typedef FlutterBoostRouteFactory = Route<dynamic> Function(
    RouteSettings settings, String uniqueId);

class FlutterBoostApp extends StatefulWidget {
  const FlutterBoostApp(this.routeFactory,
      {FlutterBoostAppBuilder appBuilder, String initialRoute})
      : appBuilder = appBuilder ?? _materialAppBuilder,
        initialRoute = initialRoute ?? '/';

  final FlutterBoostRouteFactory routeFactory;
  final FlutterBoostAppBuilder appBuilder;
  final String initialRoute;

  static Widget _materialAppBuilder(Widget home) {
    return MaterialApp(home: home);
  }

  @override
  State<StatefulWidget> createState() => FlutterBoostAppState();
}

class FlutterBoostAppState extends State<FlutterBoostApp> {
  // 记录页面出栈入栈的完成事件
  final Map<String, Completer<Object>> _pendingResult =
      <String, Completer<Object>>{};
  // 页面容器集合
  List<BoostContainer> get containers => _containers;
  final List<BoostContainer> _containers = <BoostContainer>[];

  BoostContainer get topContainer => containers.last;
  // 页面路由Api（通过channel由native处理）
  NativeRouterApi get nativeRouterApi => _nativeRouterApi;
  NativeRouterApi _nativeRouterApi;
  // 承接来自channel的信息
  BoostFlutterRouterApi get boostFlutterRouterApi => _boostFlutterRouterApi;
  BoostFlutterRouterApi _boostFlutterRouterApi;
  // 页面路由工厂方法
  FlutterBoostRouteFactory get routeFactory => widget.routeFactory;
  final Set<int> _activePointers = <int>{};

  @override
  void initState() {
    _containers.add(_createContainer(PageInfo(pageName: widget.initialRoute)));
    _nativeRouterApi = NativeRouterApi();
    _boostFlutterRouterApi = BoostFlutterRouterApi(this);
    super.initState();

    // try to restore routes from host when hot restart.
    assert(() {
      _restoreStackForHotRestart();
      return true;
    }());
  }

  @override
  Widget build(BuildContext context) {
    return widget.appBuilder(WillPopScope(
        onWillPop: () async {
          final bool canPop = topContainer.navigator.canPop();
          if (canPop) {
            topContainer.navigator.pop();
            return true;
          }
          return false;
        },
        child: Listener(
            onPointerDown: _handlePointerDown,
            onPointerUp: _handlePointerUpOrCancel,
            onPointerCancel: _handlePointerUpOrCancel,
            child: Overlay(
              key: overlayKey,
              initialEntries: const <OverlayEntry>[],
            ))));
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
  }

  void _handlePointerUpOrCancel(PointerEvent event) {
    _activePointers.remove(event.pointer);
  }

  void _cancelActivePointers() {
    _activePointers.toList().forEach(WidgetsBinding.instance.cancelPointer);
  }

  void refresh() {
    refreshOverlayEntries(containers);

    // try to save routes to host.
    assert(() {
      _saveStackForHotRestart();
      return true;
    }());
  }

  String _createUniqueId(String pageName) {
    if (kReleaseMode) {
      return Uuid().v4();
    } else {
      return Uuid().v4() + '#$pageName';
    }
  }
  /// 创建一个页面容器管理类，实际页面是 BoostPage
  BoostContainer _createContainer(PageInfo pageInfo) {
    pageInfo.uniqueId ??= _createUniqueId(pageInfo.pageName);
    return BoostContainer(
        key: ValueKey<String>(pageInfo.uniqueId),
        pageInfo: pageInfo,
        routeFactory: widget.routeFactory);
  }

  Future<void> _saveStackForHotRestart() async {
    final StackInfo stack = StackInfo();
    stack.containers = <String>[];
    for (BoostContainer container in containers) {
      stack.containers.add(container.pageInfo.uniqueId);
      stack.routes = <String, List<Map<String, Object>>>{};
      final List<Map<String, Object>> params = <Map<String, Object>>[];
      for (BoostPage<dynamic> page in container.pages) {
        final Map<String, Object> param = <String, Object>{};
        param['pageName'] = page.pageInfo.pageName;
        param['uniqueId'] = page.pageInfo.uniqueId;
        param['arguments'] = page.pageInfo.arguments;
        params.add(param);
      }
      stack.routes[container.pageInfo.uniqueId] = params;
    }
    await nativeRouterApi.saveStackToHost(stack);
    Logger.log(
        '_saveStackForHotRestart, ${stack?.containers}, ${stack?.routes}');
  }

  Future<void> _restoreStackForHotRestart() async {
    final StackInfo stack = await nativeRouterApi.getStackFromHost();
    if (stack != null && stack.containers != null) {
      for (String uniqueId in stack.containers) {
        bool withContainer = true;
        final List<Object> routeList = stack.routes[uniqueId];
        if (routeList != null) {
          for (Map<Object, Object> route in routeList) {
            push(route['pageName'] as String,
                uniqueId: route['uniqueId'] as String,
                arguments: Map<String, dynamic>.from(
                    route['arguments'] ?? <String, dynamic>{}),
                withContainer: withContainer);
            withContainer = false;
          }
        }
      }
    }
    Logger.log(
        '_restoreStackForHotRestart, ${stack?.containers}, ${stack?.routes}');
  }

  Future<T> pushWithResult<T extends Object>(String pageName,
      {String uniqueId, Map<String, dynamic> arguments, bool withContainer}) {
    final Completer<T> completer = Completer<T>();
    assert(uniqueId == null);
    uniqueId = _createUniqueId(pageName);
    if (withContainer) {
      final CommonParams params = CommonParams()
        ..pageName = pageName
        ..uniqueId = uniqueId
        ..arguments = arguments ?? <String, dynamic>{};
      nativeRouterApi.pushFlutterRoute(params);
    } else {
      push(pageName,
          uniqueId: uniqueId, arguments: arguments, withContainer: false);
    }
    _pendingResult[uniqueId] = completer;
    return completer.future;
  }

  void push(String pageName,
      {String uniqueId, Map<String, dynamic> arguments, bool withContainer}) {
    _cancelActivePointers();
    final BoostContainer existed = _findContainerByUniqueId(uniqueId);
    if (existed != null) {
      // 当前push的页面已经存在dart栈中
      if (topContainer?.pageInfo?.uniqueId != uniqueId) {
        /**
         * 即将push的页面是不在栈顶
         * 移除栈中的页面
         * 将即将显示的页面添加在最后
         * 刷新显示
         * */
        containers.remove(existed);
        containers.add(existed);
        refresh();
        // 传递页面生命周期事件
        PageVisibilityBinding.instance
            .dispatchPageShowEvent(_getCurrentPageRoute());
        if (_getPreviousPageRoute() != null) {
          PageVisibilityBinding.instance
              .dispatchPageHideEvent(_getPreviousPageRoute());
        }
      } else {
        // 如果即将push的页面就在栈顶，无需其他操作，只传递pageOnShow 即可
        PageVisibilityBinding.instance
            .dispatchPageShowEvent(_getCurrentPageRoute());
      }
    } else
      {
      // 当前push的页面不在栈中
      final PageInfo pageInfo = PageInfo(
          pageName: pageName,
          uniqueId: uniqueId ?? _createUniqueId(pageName),
          arguments: arguments,
          withContainer: withContainer);
      // withContainer 是否新起一个native页面，还是在当前dart容器中路由
      if (withContainer) {
        containers.add(_createContainer(pageInfo));
        // The observer can't receive the 'pageshow' message indeed，
        // because the observer is not yet registed at the moment.
        //
        // See PageVisibilityBinding#addObserver for the solution.
        PageVisibilityBinding.instance
            .dispatchPageShowEvent(_getCurrentPageRoute());
        if (_getPreviousPageRoute() != null) {
          PageVisibilityBinding.instance
              .dispatchPageHideEvent(_getPreviousPageRoute());
        }
      } else {
        topContainer.pages
            .add(BoostPage.create(pageInfo, topContainer.routeFactory));
      }
      refresh();
    }
    Logger.log(
        'push page, uniqueId=$uniqueId, existed=$existed, withContainer=$withContainer, arguments:$arguments, $containers');
  }

  void popWithResult<T extends Object>([T result]) {
    final String uniqueId = topContainer?.topPage?.pageInfo?.uniqueId;
    if (_pendingResult.containsKey(uniqueId)) {
      _pendingResult[uniqueId].complete(result);
    }
    pop();
  }

  Future<void> pop({String uniqueId, Map<String, dynamic> arguments}) async {
    BoostContainer container;
    if (uniqueId != null) {
      container = _findContainerByUniqueId(uniqueId);
      if (container == null) {
        Logger.error('uniqueId=$uniqueId not find');
        return;
      }
      // pop 的不是最顶层页面，
      if (container != topContainer) {
        _removeContainer(container);
        return;
      }
    } else {
      // 如果未传 uniqueId，默认pop最顶层页面
      container = topContainer;
    }

    final bool handled = await container?.navigator?.maybePop();
    if (handled != null && !handled) {
      assert(container.pageInfo.withContainer);
      final CommonParams params = CommonParams()
        ..pageName = container.pageInfo.pageName
        ..uniqueId = container.pageInfo.uniqueId
        ..arguments = arguments ?? <String, dynamic>{};
      _nativeRouterApi.popRoute(params);
    }
    _pendingResult.remove(uniqueId);

    Logger.log(
        'pop container, uniqueId=$uniqueId, arguments:$arguments, $container');
  }
  /// 移除 container，同时如果当前container 是新起的独立页面，通过channel 传给native
  void _removeContainer(BoostContainer page) {
    containers.remove(page);
    if (page.pageInfo.withContainer) {
      Logger.log('_removeContainer ,  uniqueId=${page.pageInfo.uniqueId}');
      final CommonParams params = CommonParams()
        ..pageName = page.pageInfo.pageName
        ..uniqueId = page.pageInfo.uniqueId
        ..arguments = page.pageInfo.arguments;
      _nativeRouterApi.popRoute(params);
    }
  }

  /// 一些app事件的传递
  void onForeground() {
    PageVisibilityBinding.instance
        .dispatchForegroundEvent(_getCurrentPageRoute());
  }
  void onBackground() {
    PageVisibilityBinding.instance
        .dispatchBackgroundEvent(_getCurrentPageRoute());
  }
  void onNativeViewShow() {
    PageVisibilityBinding.instance
        .dispatchPageHideEvent(_getCurrentPageRoute());
  }
  void onNativeViewHide() {
    PageVisibilityBinding.instance
        .dispatchPageShowEvent(_getCurrentPageRoute());
  }

  Route<dynamic> _getCurrentPageRoute() {
    return topContainer?.topPage?.route;
  }

  Route<dynamic> _getPreviousPageRoute() {
    if (topContainer != null) {
      assert(topContainer.pages != null);
      final int pageCount = topContainer.pages.length;
      if (pageCount > 1) {
        return topContainer.pages[pageCount - 2].route;
      } else {
        final int containerCount = containers.length;
        if (containerCount > 1) {
          return containers[containerCount - 2].pages.last.route;
        }
      }
    }
    return null;
  }
  /// 通过 uniqueId 找到对应的boostContainer
  BoostContainer _findContainerByUniqueId(String uniqueId) {
    return containers.singleWhere(
        (BoostContainer element) => element.pageInfo.uniqueId == uniqueId,
        orElse: () => null);
  }

  void remove(String uniqueId) {
    if (uniqueId == null) {
      return;
    }

    final BoostContainer container = _findContainerByUniqueId(uniqueId);
    Route<dynamic> _route;
    if (container != null) {
      // Gets the first internal route of the current container
      _route = container.pages.first.route;
      containers.removeWhere(
          (BoostContainer entry) => entry.pageInfo?.uniqueId == uniqueId);
    } else {
      for (BoostContainer container in containers) {
        final BoostPage<dynamic> _target = container.pages.firstWhere(
            (BoostPage<dynamic> entry) => entry.pageInfo?.uniqueId == uniqueId,
            orElse: () => null);
        _route = _target?.route;
        container.pages.removeWhere(
            (BoostPage<dynamic> entry) => entry.pageInfo?.uniqueId == uniqueId);
      }
    }
    refresh();
    PageVisibilityBinding.instance.dispatchPageDestoryEvent(_route);
    Logger.log('remove,  uniqueId=$uniqueId, $containers');
  }

  PageInfo getTopPageInfo() {
    return topContainer?.topPage?.pageInfo;
  }

  int pageSize() {
    int count = 0;
    for (BoostContainer container in containers) {
      count += container.size;
    }
    return count;
  }
}
/// 继承自抽象类Page
class BoostPage<T> extends Page<T> {
  BoostPage({LocalKey key, this.routeFactory, this.pageInfo})
      : super(key: key, name: pageInfo.pageName, arguments: pageInfo.arguments);

  final FlutterBoostRouteFactory routeFactory;
  final PageInfo pageInfo;

  static BoostPage<dynamic> create(
      PageInfo pageInfo, FlutterBoostRouteFactory routeFactory) {
    return BoostPage<dynamic>(
        key: UniqueKey(), pageInfo: pageInfo, routeFactory: routeFactory);
  }

  final List<Route<T>> _route = <Route<T>>[];
  Route<T> get route => _route.isEmpty ? null : _route.first;

  @override
  String toString() =>
      '${objectRuntimeType(this, 'BoostPage')}(name:$name, uniqueId:${pageInfo.uniqueId}, arguments:$arguments)';

  @override
  Route<T> createRoute(BuildContext context) {
    _route.clear();
    _route.add(routeFactory(this, pageInfo.uniqueId));
    return _route.first;
  }
}
/// 导航监听 继承自 NavigatorObserver
class BoostNavigatorObserver extends NavigatorObserver {
  BoostNavigatorObserver();

  @override
  void didPush(Route<dynamic> route, Route<dynamic> previousRoute) {
    //handle internal route
    if (previousRoute != null) {
      PageVisibilityBinding.instance.dispatchPageShowEvent(route);
      PageVisibilityBinding.instance.dispatchPageHideEvent(previousRoute);
    }
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic> previousRoute) {
    if (previousRoute != null) {
      PageVisibilityBinding.instance.dispatchPageHideEvent(route);
      PageVisibilityBinding.instance.dispatchPageShowEvent(previousRoute);
    }
    super.didPop(route, previousRoute);
  }
}
