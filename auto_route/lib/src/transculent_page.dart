import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

class _ModalScopeStatus extends InheritedWidget {
  const _ModalScopeStatus({
    required this.isCurrent,
    required this.canPop,
    required this.impliesAppBarDismissal,
    required this.route,
    required super.child,
  });

  final bool isCurrent;
  final bool canPop;
  final bool impliesAppBarDismissal;
  final Route<dynamic> route;

  @override
  bool updateShouldNotify(_ModalScopeStatus old) =>
      isCurrent != old.isCurrent ||
          canPop != old.canPop ||
          impliesAppBarDismissal != old.impliesAppBarDismissal ||
          route != old.route;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder description) {
    super.debugFillProperties(description);
    description.add(
      FlagProperty(
        'isCurrent',
        value: isCurrent,
        ifTrue: 'active',
        ifFalse: 'inactive',
      ),
    );
    description.add(FlagProperty('canPop', value: canPop, ifTrue: 'can pop'));
    description.add(
      FlagProperty(
        'impliesAppBarDismissal',
        value: impliesAppBarDismissal,
        ifTrue: 'implies app bar dismissal',
      ),
    );
  }
}

class _ModalScope<T> extends StatefulWidget {
  const _ModalScope({
    required this.route,
    super.key,
  });

  final ModalRoute<T> route;

  @override
  _ModalScopeState<T> createState() => _ModalScopeState<T>();
}

class _ModalScopeState<T> extends State<_ModalScope<T>> {
  // We cache the result of calling the route's buildPage, and clear the cache
  // whenever the dependencies change. This implements the contract described in
  // the documentation for buildPage, namely that it gets called once, unless
  // something like a ModalRoute.of() dependency triggers an update.
  Widget? _page;

  // This is the combination of the two animations for the route.
  late Listenable _listenable;

  final FocusScopeNode focusScopeNode = FocusScopeNode(debugLabel: '$_ModalScopeState Focus Scope');
  final ScrollController primaryScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final animations = <Listenable>[
      if (widget.route.animation != null) widget.route.animation!,
      if (widget.route.secondaryAnimation != null) widget.route.secondaryAnimation!,
    ];
    _listenable = Listenable.merge(animations);
  }

  @override
  void didUpdateWidget(_ModalScope<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(widget.route == oldWidget.route);
    _updateFocusScopeNode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _page = null;
    _updateFocusScopeNode();
  }

  void _updateFocusScopeNode() {
    final TraversalEdgeBehavior traversalEdgeBehavior;
    final route = widget.route;
    if (route.traversalEdgeBehavior != null) {
      traversalEdgeBehavior = route.traversalEdgeBehavior!;
    } else {
      traversalEdgeBehavior = route.navigator!.widget.routeTraversalEdgeBehavior;
    }
    focusScopeNode.traversalEdgeBehavior = traversalEdgeBehavior;
    if (route.isCurrent && _shouldRequestFocus) {
      route.navigator!.focusNode.enclosingScope?.setFirstFocus(focusScopeNode);
    }
  }

  void _forceRebuildPage() {
    setState(() {
      _page = null;
    });
  }

  @override
  void dispose() {
    focusScopeNode.dispose();
    super.dispose();
  }

  bool get _shouldIgnoreFocusRequest =>
      widget.route.animation?.status == AnimationStatus.reverse ||
          (widget.route.navigator?.userGestureInProgress ?? false);

  bool get _shouldRequestFocus => widget.route.navigator!.widget.requestFocus;

  // This should be called to wrap any changes to route.isCurrent, route.canPop,
  // and route.offstage.
  void _routeSetState(VoidCallback fn) {
    if (widget.route.isCurrent && !_shouldIgnoreFocusRequest && _shouldRequestFocus) {
      widget.route.navigator!.focusNode.enclosingScope?.setFirstFocus(focusScopeNode);
    }
    setState(fn);
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(
        animation: widget.route.restorationScopeId,
        builder: (context, child) {
          assert(child != null);
          return RestorationScope(
            restorationId: widget.route.restorationScopeId.value,
            child: child!,
          );
        },
        child: _ModalScopeStatus(
          route: widget.route,
          isCurrent: widget.route.isCurrent,
          // _routeSetState is called if this updates
          canPop: widget.route.canPop,
          // _routeSetState is called if this updates
          impliesAppBarDismissal: widget.route.impliesAppBarDismissal,
          child: Offstage(
            offstage: widget.route.offstage, // _routeSetState is called if this updates
            child: PageStorage(
              bucket: widget.route._storageBucket, // immutable
              child: Builder(
                builder: (context) =>
                    Actions(
                      actions: const <Type, Action<Intent>>{
                        // DismissIntent: _DismissModalAction(context),
                      },
                      child: PrimaryScrollController(
                        controller: primaryScrollController,
                        child: FocusScope(
                          node: focusScopeNode, // immutable
                          child: RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: _listenable, // immutable
                              builder: (context, child) =>
                                  widget.route.buildTransitions(
                                    context,
                                    widget.route.animation!,
                                    widget.route.secondaryAnimation!,
                                    // This additional AnimatedBuilder is include because if the
                                    // value of the userGestureInProgressNotifier changes, it's
                                    // only necessary to rebuild the IgnorePointer widget and set
                                    // the focus node's ability to focus.
                                    AnimatedBuilder(
                                      animation:
                                      widget.route.navigator?.userGestureInProgressNotifier ??
                                          ValueNotifier<bool>(false),
                                      builder: (context, child) {
                                        final ignoreEvents = _shouldIgnoreFocusRequest;
                                        focusScopeNode.canRequestFocus = !ignoreEvents;
                                        return IgnorePointer(
                                          ignoring: ignoreEvents,
                                          child: child,
                                        );
                                      },
                                      child: child,
                                    ),
                                  ),
                              child: _page ??= RepaintBoundary(
                                key: widget.route._subtreeKey, // immutable
                                child: Builder(
                                  builder: (context) =>
                                      widget.route.buildPage(
                                        context,
                                        widget.route.animation!,
                                        widget.route.secondaryAnimation!,
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ),
      );
}

abstract class ModalRoute<T> extends TransitionRoute<T> with LocalHistoryRoute<T> {
  ModalRoute({
    super.settings,
    this.traversalEdgeBehavior,
  });

  final TraversalEdgeBehavior? traversalEdgeBehavior;

  @optionalTypeArgs
  static ModalRoute<T>? of<T extends Object?>(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<_ModalScopeStatus>();
    return widget?.route as ModalRoute<T>?;
  }

  @protected
  void setState(VoidCallback fn) {
    if (_scopeKey.currentState != null) {
      _scopeKey.currentState!._routeSetState(fn);
    } else {
      fn();
    }
  }

  static RoutePredicate withName(String name) =>
          (route) => !route.willHandlePopInternally && route is ModalRoute && route.settings.name == name;

  Widget buildPage(BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,);

  Widget buildTransitions(BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,) =>
      child;

  @override
  void install() {
    super.install();
    _animationProxy = ProxyAnimation(super.animation);
    _secondaryAnimationProxy = ProxyAnimation(super.secondaryAnimation);
  }

  @override
  TickerFuture didPush() {
    if (_scopeKey.currentState != null && navigator!.widget.requestFocus) {
      navigator!.focusNode.enclosingScope?.setFirstFocus(_scopeKey.currentState!.focusScopeNode);
    }
    return super.didPush();
  }

  @override
  void didAdd() {
    if (_scopeKey.currentState != null && navigator!.widget.requestFocus) {
      navigator!.focusNode.enclosingScope?.setFirstFocus(_scopeKey.currentState!.focusScopeNode);
    }
    super.didAdd();
  }

  bool get semanticsDismissible => true;

  bool get maintainState;

  bool get offstage => _offstage;
  bool _offstage = false;

  set offstage(bool value) {
    if (_offstage == value) {
      return;
    }
    setState(() {
      _offstage = value;
    });
    _animationProxy!.parent = _offstage ? kAlwaysCompleteAnimation : super.animation;
    _secondaryAnimationProxy!.parent = _offstage ? kAlwaysDismissedAnimation : super.secondaryAnimation;
    changedInternalState();
  }

  BuildContext? get subtreeContext => _subtreeKey.currentContext;

  @override
  Animation<double>? get animation => _animationProxy;
  ProxyAnimation? _animationProxy;

  @override
  Animation<double>? get secondaryAnimation => _secondaryAnimationProxy;
  ProxyAnimation? _secondaryAnimationProxy;

  final List<WillPopCallback> _willPopCallbacks = <WillPopCallback>[];

  @override
  Future<RoutePopDisposition> willPop() async {
    final scope = _scopeKey.currentState;
    assert(scope != null);
    for (final callback in List<WillPopCallback>.of(_willPopCallbacks)) {
      if (await callback() != true) {
        return RoutePopDisposition.doNotPop;
      }
    }
    return super.willPop();
  }

  void addScopedWillPopCallback(WillPopCallback callback) {
    assert(
    _scopeKey.currentState != null,
    'Tried to add a willPop callback to a route that is not currently in the tree.',
    );
    _willPopCallbacks.add(callback);
  }

  void removeScopedWillPopCallback(WillPopCallback callback) {
    assert(
    _scopeKey.currentState != null,
    'Tried to remove a willPop callback from a route that is not currently in the tree.',
    );
    _willPopCallbacks.remove(callback);
  }

  @protected
  bool get hasScopedWillPopCallback => _willPopCallbacks.isNotEmpty;

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    super.didChangePrevious(previousRoute);
    changedInternalState();
  }

  @override
  void changedInternalState() {
    super.changedInternalState();
    setState(() {
      /* internal state already changed */
    });
    _modalScope.maintainState = maintainState;
  }

  @override
  void changedExternalState() {
    super.changedExternalState();
    if (_scopeKey.currentState != null) {
      _scopeKey.currentState!._forceRebuildPage();
    }
  }

  bool get canPop => hasActiveRouteBelow || willHandlePopInternally;

  bool get impliesAppBarDismissal => hasActiveRouteBelow;

  final GlobalKey<_ModalScopeState<T>> _scopeKey = GlobalKey<_ModalScopeState<T>>();
  final GlobalKey _subtreeKey = GlobalKey();
  final PageStorageBucket _storageBucket = PageStorageBucket();

  Widget? _modalScopeCache;

  Widget _buildModalScope(BuildContext context) =>
      _modalScopeCache ??= Semantics(
        sortKey: const OrdinalSortKey(0),
        child: _ModalScope<T>(
          key: _scopeKey,
          route: this,
          // _ModalScope calls buildTransitions() and buildChild(), defined above
        ),
      );

  late OverlayEntry _modalScope;

  @override
  Iterable<OverlayEntry> createOverlayEntries() =>
      <OverlayEntry>[
        _modalScope = OverlayEntry(builder: _buildModalScope, maintainState: maintainState),
      ];

  @override
  String toString() => '${objectRuntimeType(this, 'ModalRoute')}($settings)';
}

class TRoute<T> extends ModalRoute<T> {
  TRoute(TransculentPage<T> page) : super(settings: page);

  TransculentPage<T> get _page => settings as TransculentPage<T>;

  @override
  Widget buildPage(BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,) =>
      _page.child;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => true;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  bool get popGestureEnabled => true;
}

class TransculentPage<T> extends AutoRoutePage<T> {
  TransculentPage({
    required super.routeData, required super.child,
  });

  @override
  Route<T> createRoute(BuildContext context) => TRoute<T>(this);
}