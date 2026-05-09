import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
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
      // i18n delegates：与主窗口保持一致；flutter_quill 11.x 在子窗口编辑备注必需。
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en'),
      ],
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

