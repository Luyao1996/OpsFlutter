import 'package:flutter/material.dart';

/// 全局 Navigator Key。
/// 由 router 注入到 GoRouter，更新弹窗用它作为 showDialog 的 context 来源，
/// 解决"启动期还没有 BuildContext"的问题。
final GlobalKey<NavigatorState> updateNavigatorKey =
    GlobalKey<NavigatorState>();
