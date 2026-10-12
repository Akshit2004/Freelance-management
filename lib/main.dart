import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:provider/provider.dart';

import 'ai.dart';
import 'ai_svg_animator.dart';
import 'cloud_backup.dart';
import 'clients.dart';
import 'docs.dart';
import 'downloads.dart';
import 'home.dart';
import 'intro.dart';
import 'log.dart';
import 'magic.dart';
import 'models.dart';
import 'motion.dart';
import 'projects.dart';
import 'state.dart';
import 'sub_menu.dart';
import 'ui.dart';
import 'voice_pack.dart';

void main() => runQuiet(_boot);

Future<void> _boot() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  try {
    await FlutterGemma.initialize();
  } catch (_) {}
  await store.load();
  try {
    await downloads.init(); // re-attaches to a model download that kept running while the app was closed
  } catch (_) {}
  await CloudBackup.load(); // the MongoDB connection string saved in Settings (encrypted storage), if any
  try {
    await voicePack.init();
  } catch (_) {}
  unawaited(Ai.warmUp()); // load the model while the intro plays, so the first Magic request isn't slow
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider<Store>.value(value: store),
      ChangeNotifierProvider<ModelDownloads>.value(value: downloads),
      ChangeNotifierProvider(create: (_) => NavController()),
    ],
    child: const App(),
  ));
}

/// The app-wide light theme (also used by widget tests).
ThemeData hustlerTheme() => ThemeData(
    brightness: Brightness.light,
    fontFamily: 'Grotesk',
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.light(
      primary: C.dark,
      onPrimary: C.textLight,
      secondary: C.orange,
      surface: C.card,
      onSurface: C.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: C.text),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.dark,
      contentTextStyle: const TextStyle(color: C.textLight, fontFamily: 'Grotesk', fontWeight: FontWeight.w600),
      actionTextColor: C.amberLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    visualDensity: VisualDensity.standard,
    splashFactory: InkRipple.splashFactory, // Pressable has no ink; the few Material buttons get a calm ripple (no sparkle shader)
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: C.orange,
      selectionColor: C.orange.withValues(alpha: .25),
      selectionHandleColor: C.orange,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      hintStyle: TextStyle(color: C.dim),
      errorStyle: TextStyle(color: C.red, fontWeight: FontWeight.w600),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.orange),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.text, minimumSize: const Size(64, 48), textStyle: const TextStyle(fontFamily: 'Grotesk', fontWeight: FontWeight.w700)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: C.border)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: C.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      headerBackgroundColor: C.dark,
      headerForegroundColor: C.textLight,
      todayForegroundColor: const WidgetStatePropertyAll(C.orangeDark),
      todayBorder: const BorderSide(color: C.orangeDark),
      confirmButtonStyle: TextButton.styleFrom(foregroundColor: C.orangeDark),
      cancelButtonStyle: TextButton.styleFrom(foregroundColor: C.muted),
    ),
  );

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  /// Coming back to the app after this long away replays the intro, like a fresh launch.
  static const awayFor = Duration(minutes: 5);
  bool intro = true;
  DateTime? leftAt;
  final navKey = GlobalKey<NavigatorState>();
  Timer? _backupTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _backupTimer = Timer.periodic(const Duration(minutes: 5), (_) => _autoBackup());
  }

  Future<void> _autoBackup() async {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return; // the leave-the-app backup covers the background
    if (!(await CloudBackup.instance?.autoBackUp(store) ?? false)) return;
    final ctx = navKey.currentContext;
    if (ctx != null && ctx.mounted) toast(ctx, 'Backed up to MongoDB');
  }

  @override
  void dispose() {
    _backupTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) store.flush();
    if (s == AppLifecycleState.paused) CloudBackup.instance?.autoBackUp(store);
    if (s == AppLifecycleState.paused) leftAt = DateTime.now();
    if (s == AppLifecycleState.resumed && leftAt != null && DateTime.now().difference(leftAt!) > awayFor && !intro) {
      setState(() => intro = true);
    }
    if (s == AppLifecycleState.resumed) leftAt = null;
    if (s == AppLifecycleState.resumed) downloads.refresh(); // a download may have finished while we were away
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hustler',
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      navigatorObservers: [NavLog()],
      theme: hustlerTheme(),
      builder: (context, child) => Stack(children: [
        child!,
        if (intro) Positioned.fill(child: IntroOverlay(onDone: () => setState(() => intro = false))),
      ]),
      home: const Shell(),
    );
  }
}

class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavController>();
    final slot = nav.slot;
    final page = switch (slot) {
      NavController.projects => const ProjectsTab(),
      NavController.docs => const DocsTab(),
      NavController.clients => const ClientsTab(),
      _ => const HomeTab(),
    };
    final dir = slot >= nav.from ? 1.0 : -1.0; // tabs slide the way you're travelling

    return PopScope(
      canPop: slot == NavController.home,
      onPopInvokedWithResult: (didPop, _) => didPop ? null : nav.go(NavController.home),
      child: Stack(children: [
        const Positioned.fill(child: ColoredBox(color: C.bg)),
        const Positioned.fill(child: Backdrop()),
        Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          resizeToAvoidBottomInset: false, // tab pages have no text fields; dialogs and pushed screens handle the keyboard themselves
          // The bar floats over the body (extendBody), so the tab content gets the bar's height as bottom padding: the last
          // item of every list can be scrolled fully above it (only the raised Magic button overlaps that margin).
          body: MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: Padding(
              padding: EdgeInsets.only(bottom: HustlerNavBar.bodyInset(context)),
              child: SafeArea(
                bottom: false,
                child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : 420.ms,
              switchInCurve: const Cubic(.2, .9, .25, 1),
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, a) {
                final incoming = child.key == ValueKey(slot);
                final shift = Tween(begin: Offset((incoming ? dir : -dir) * .14, 0), end: Offset.zero);
                return FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: shift.animate(a),
                    child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(a), child: child),
                  ),
                );
              },
              child: KeyedSubtree(key: ValueKey(slot), child: page),
                ),
              ),
            ),
          ),
          bottomNavigationBar: const HustlerNavBar(),
        ),
      ]),
    );
  }
}

/// Four tabs with the Magic Scratchpad button raised in the middle. The pill behind the active icon springs between tabs.
class HustlerNavBar extends StatelessWidget {
  const HustlerNavBar({super.key});

  static const _barHeight = 80.0, _lift = 26.0;

  /// Bottom of the screen covered by the bar apart from the raised Magic button: tab content stops here.
  static double bodyInset(BuildContext context) => _barHeight + MediaQuery.paddingOf(context).bottom;

  // (nav slot, outline icon, filled icon, label); the bar has 5 columns and column 2 belongs to Magic
  static const tabs = [
    (NavController.home, Icons.home_outlined, Icons.home_rounded, 'Home'),
    (NavController.projects, Icons.folder_outlined, Icons.folder_rounded, 'Projects'),
    (NavController.docs, Icons.description_outlined, Icons.description_rounded, 'Docs'),
    (NavController.clients, Icons.people_outline_rounded, Icons.people_rounded, 'Clients'),
  ];
  static int column(int slot) => slot < 2 ? slot : slot + 1;

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavController>();
    final inset = MediaQuery.paddingOf(context).bottom; // gesture / 3-button bar: the bar's background runs under it
    final still = MediaQuery.disableAnimationsOf(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3, // the labels sit in a fixed-height bar; beyond this they would not fit the columns
      child: SizedBox(
        height: _barHeight + _lift + inset,
        child: LayoutBuilder(builder: (_, box) {
          final w = box.maxWidth / 5;
          return Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _barHeight + inset,
              child: Container(
                decoration: BoxDecoration(color: C.bg.withValues(alpha: .97), border: const Border(top: BorderSide(color: C.border))),
              ),
            ),
            AnimatedPositioned(
              duration: still ? Duration.zero : 560.ms,
              curve: const Cubic(.3, 1.5, .5, 1), // springy overshoot, like framer-motion layoutId
              left: column(nav.slot) * w + (w - 56) / 2,
              top: _lift + 6,
              child: Container(
                width: 56,
                height: 32,
                decoration: BoxDecoration(color: C.orange.withValues(alpha: .14), borderRadius: BorderRadius.circular(16)),
              ),
            ),
            for (final (slot, outline, filled, label) in tabs)
              Positioned(
                left: column(slot) * w,
                width: w,
                top: _lift,
                height: _barHeight,
                child: Semantics(
                  selected: nav.slot == slot,
                  label: label,
                  child: Pressable(
                    onTap: () => nav.go(slot),
                    child: Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.only(top: 9),
                      child: Column(children: [
                        SizedBox(
                          height: 28,
                          child: Icon(nav.slot == slot ? filled : outline, size: 24, color: nav.slot == slot ? C.orange : C.dim)
                              .animate(target: nav.slot == slot ? 1 : 0)
                              .scaleXY(end: 1.18, duration: 380.ms, curve: Curves.easeOutBack)
                              .moveY(end: -1.5, duration: 380.ms, curve: Curves.easeOutBack),
                        ),
                        const SizedBox(height: 4),
                        ExcludeSemantics(
                          child: AnimatedDefaultTextStyle(
                            duration: still ? Duration.zero : 250.ms,
                            style: TextStyle(fontFamily: 'Grotesk', fontSize: 10.5, fontWeight: FontWeight.w600, color: nav.slot == slot ? C.orangeDark : C.muted),
                            child: Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            Positioned(left: 2 * w, width: w, top: 0, child: const _MagicButton()),
            Positioned(
              right: 12,
              top: _lift - 12,
              child: Semantics(
                button: true,
                label: 'Workspace Tools menu',
                child: Pressable(
                  onTap: () => openBottomSubMenu(context),
                  child: Container(
                    key: const Key('navbar-sub-menu-button'),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: C.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: C.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .06),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.widgets_outlined, size: 12, color: C.orange),
                        const SizedBox(width: 4),
                        Text(
                          'TOOLS',
                          style: mono(8.5, color: C.text, weight: FontWeight.w700, letterSpacing: 0.8),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.keyboard_arrow_up_rounded, size: 12, color: C.dim),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ]);
        }),
      ),
    );
  }
}

/// The raised centre button with GSAP-inspired AI SVG animations opening Magic Scratchpad.
class _MagicButton extends StatelessWidget {
  const _MagicButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Magic Scratchpad',
      child: Pressable(
        onTap: () {
          if (ModalRoute.of(context)?.isCurrent != true) return; // a quick double tap must not stack two Magic pages
          Navigator.push(context, zoom(const MagicPage()));
        },
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 70,
            height: 62,
            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFF2E2218), Color(0xFF181512), Color(0xFF0F0E0C)],
                    stops: [0.0, 0.7, 1.0],
                  ),
                  border: Border.all(color: C.orange.withValues(alpha: 0.5), width: 2.5),
                  boxShadow: [
                    BoxShadow(color: C.orange.withValues(alpha: .38), blurRadius: 18, offset: const Offset(0, 5)),
                  ],
                ),
                child: const Center(
                  child: AiSvgAnimator(
                    size: 56,
                    showGlow: true,
                    primaryColor: Color(0xFFFF5722),
                    secondaryColor: Color(0xFFFFB300),
                    accentColor: Color(0xFFFF8A65),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          const ExcludeSemantics(
            child: Text('Magic', maxLines: 1, style: TextStyle(fontFamily: 'Grotesk', fontSize: 10.5, fontWeight: FontWeight.w700, color: C.orangeDark)),
          ),
        ]),
      ),
    );
  }
}
