import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/update_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});
