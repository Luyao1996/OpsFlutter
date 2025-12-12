import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/storage/token_store.dart';
import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'app/router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化存储
  await TokenStore.init();

  // 设置 401 回调
  ApiClient.onUnauthorized = () {
    TokenStore.clearAuth();
    // 路由跳转在 router 的 redirect 中处理
  };

  runApp(const ProviderScope(child: NetbarOpsApp()));
}

class NetbarOpsApp extends ConsumerWidget {
  const NetbarOpsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Netbar Ops Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.iosBlue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.iosBg,
        fontFamily: null, // 使用系统字体
      ),
      routerConfig: router,
    );
  }
}
