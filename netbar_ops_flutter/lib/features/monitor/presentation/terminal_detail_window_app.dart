import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'terminal_detail_page.dart';

class TerminalDetailWindowApp extends ConsumerWidget {
  final int terminalId;
  final int windowId;
  final String initialTab;

  const TerminalDetailWindowApp({
    super.key,
    required this.terminalId,
    required this.windowId,
    required this.initialTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Terminal Detail',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.iosBlue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.iosBg,
      ),
      home: TerminalDetailPage(
        terminalId: terminalId,
        isStandaloneWindow: true,
        windowId: windowId,
        initialTab: initialTab,
      ),
    );
  }
}

