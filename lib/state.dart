import 'package:flutter/foundation.dart';

import 'log.dart';

/// Which bottom-bar tab is showing. Provided at the root so any screen can switch tabs
/// (`context.read<NavController>().go(1)`) without callbacks being passed down.
class NavController extends ChangeNotifier {
  static const home = 0, projects = 1, docs = 2, clients = 3;

  static const _names = ['Home', 'Projects', 'Docs', 'Clients'];

  int slot = home;
  int from = home; // previous tab, so the transition slides the way you're travelling

  void go(int i) {
    if (i == slot || i < home || i > clients) return; // unknown tab ids are ignored
    Log.nav('tab   ${_names[slot]} -> ${_names[i]}');
    from = slot;
    slot = i;
    notifyListeners();
  }
}
