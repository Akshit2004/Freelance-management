import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Console output for `flutter run`. The app prints only four kinds of line, so the terminal stays readable:
///   [net]  a download / request starting, progressing, finishing or failing
///   [nav]  a page opening or closing, a tab switch
///   [db]   a read or write of the local database file
///   [err]  an uncaught error
///   [ai]   what the on-device model was asked to estimate and what it wrote
/// Everything else (package chatter, plugin debug prints, stray print() calls) is dropped by [quietConsole].
class Log {
  Log._();
  static void net(String message) => _out('net', message);
  static void nav(String message) => _out('nav', message);
  static void db(String message) => _out('db', message);
  static void err(String message) => _out('err', message);
  static void ai(String message) => _out('ai', message);

  static void _out(String tag, String message) => debugPrint('[$tag] $message');
}

const _tags = ['[net]', '[nav]', '[db]', '[err]', '[ai]'];
bool _ours(String line) => _tags.any(line.trimLeft().startsWith);

/// Runs [body] with the console limited to [Log] lines. Call it from `main()` and put everything, including `runApp`, inside.
/// Uncaught Flutter and async errors still show up, as `[err]` lines.
void runQuiet(Future<void> Function() body) {
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null && _ours(message)) original(message, wrapWidth: wrapWidth);
  };
  FlutterError.onError = (details) => Log.err('${details.exceptionAsString()}${details.stack == null ? '' : '\n${_top(details.stack!)}'}');
  PlatformDispatcher.instance.onError = (error, stack) {
    Log.err('$error\n${_top(stack)}');
    return true;
  };
  runZoned(
    () => unawaited(body()),
    zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
      if (_ours(line)) parent.print(zone, line);
    }),
  );
}

String _top(StackTrace s) => s.toString().split('\n').take(6).map((l) => '       $l').join('\n');

/// Logs pages opening and closing. Pages are named by their class (see `zoom()` in ui.dart).
class NavLog extends NavigatorObserver {
  static String _name(Route<dynamic>? r) {
    if (r == null) return 'none';
    final n = r.settings.name;
    if (n != null && n != '/') return n;
    return switch (r) { PopupRoute() => 'dialog or sheet', _ => n == '/' ? 'Home' : r.runtimeType.toString() };
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => Log.nav('open  ${_name(route)}  (from ${_name(previousRoute)})');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => Log.nav('close ${_name(route)}  (back to ${_name(previousRoute)})');

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => Log.nav('swap  ${_name(oldRoute)} -> ${_name(newRoute)}');
}
