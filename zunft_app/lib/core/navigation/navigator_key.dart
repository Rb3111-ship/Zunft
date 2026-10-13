import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The navigator of the whole app: lets something that is not a screen (a tapped notification)
/// open a screen.
final navigatorKeyProvider = Provider<GlobalKey<NavigatorState>>((ref) => GlobalKey<NavigatorState>());
