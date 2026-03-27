import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'terminal_detail_page.dart';

class TerminalDetailWindowApp extends ConsumerWidget {
  final int terminalId;
  final int windowId;
  final String initialTab;
  final Uint8List? initialScreenshot;

  const TerminalDetailWindowApp({
    super.key,
    required this.terminalId,
    required this.windowId,
    required this.initialTab,
    this.initialScreenshot,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Terminal Detail',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: TerminalDetailPage(
        terminalId: terminalId,
        isStandaloneWindow: true,
        windowId: windowId,
        initialTab: initialTab,
        initialScreenshot: initialScreenshot,
      ),
    );
  }
}

