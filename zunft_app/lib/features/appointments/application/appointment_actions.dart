import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/external_actions.dart';

/// Tests override this with a fake.
final externalActionsProvider = Provider<ExternalActions>((ref) => PlatformExternalActions());
