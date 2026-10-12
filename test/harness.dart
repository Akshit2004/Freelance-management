export 'dart:ui' show Size;
export 'package:flutter_test/flutter_test.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freelance_os/downloads.dart';
import 'package:freelance_os/main.dart' show hustlerTheme;
import 'package:freelance_os/models.dart';
import 'package:freelance_os/state.dart';
import 'package:provider/provider.dart';

bool _fontsLoaded = false;

/// Loads the real app fonts (the default test font is much wider and reports overflows that don't exist on a phone).
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await l.load();
  }

  await load('Grotesk', ['SpaceGrotesk-Regular.ttf', 'SpaceGrotesk-Bold.ttf']);
  await load('Syne', ['Syne-ExtraBold.ttf']);
  _fontsLoaded = true;
}

/// Empties the global store (no file attached, so nothing touches disk). Call at the start of every test.
void resetStore() {
  store.debugReset();
  store
    ..clients = []
    ..projects = []
    ..docs = []
    ..activity = []
    ..profile = Profile();
  store.baseline();
}

/// Pumps [screen] inside the real theme and providers at a phone size. Use small sizes and big text scales to catch overflows:
/// `pumpScreen(t, w, size: const Size(320, 568), textScale: 1.5)`. Any RenderFlex overflow fails the test via tester.takeException().
Future<void> pumpScreen(WidgetTester t, Widget screen, {Size size = const Size(360, 800), double textScale = 1.0}) async {
  await loadAppFonts();
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<Store>.value(value: store),
      ChangeNotifierProvider<ModelDownloads>.value(value: downloads),
      ChangeNotifierProvider(create: (_) => NavController()),
    ],
    child: MaterialApp(
      theme: hustlerTheme(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      home: screen,
    ),
  ));
  await settle(t);
}

/// The app has endlessly repeating animations, so pumpAndSettle would never return. Advances time instead.
Future<void> settle(WidgetTester t, [Duration d = const Duration(seconds: 2)]) async {
  await t.pump();
  await t.pump(d);
  await t.pump(const Duration(milliseconds: 100));
}
