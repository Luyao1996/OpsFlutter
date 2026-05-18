import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show PlatformMessageResponseCallback;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'webrtc_crash_logger.dart';

/// 透明包装 Flutter 默认 BinaryMessenger，仅对 WebRTC 相关 channel 做同步日志记录。
///
/// 记录时机：
/// 1. Dart → native 发送请求前（同步写日志再转发）
/// 2. native → Dart 回调到达时（setMessageHandler 收到消息时同步打日志）
///
/// 只对 channel 名中包含 "webrtc"（大小写不敏感）的消息做解码和打印，
/// 其他 channel 完全透传，避免影响其余通道性能与行为。
class LoggingBinaryMessenger extends BinaryMessenger {
  LoggingBinaryMessenger(this._inner);

  final BinaryMessenger _inner;

  static const MethodCodec _codec = StandardMethodCodec();
  static const StringCodec _stringCodec = StringCodec();

  /// 已知高频噪音 method（统计 / 枚举类），不写日志，避免日志量在
  /// 机械硬盘上压垮 UI 线程。注：具体方法名取决于所用 webrtc 插件版本，
  /// 写漏只是少砍点量、不影响崩溃定位安全性，可按实际插件方法名增删。
  static const Set<String> _noisyMethods = {
    'getStats',
    'getStatsForTrack',
    'peerConnectionGetStats',
    'getRtpSenders',
    'getRtpReceivers',
    'getTransceivers',
    'mediaStreamTrackGetSettings',
    'captureFrame',
  };

  /// 同 (channel|op|method) 组合最近一次记录时间戳(ms)，节流防错误/信令风暴。
  final Map<String, int> _lastLogMs = {};

  bool _isWebRtcChannel(String channel) {
    final lc = channel.toLowerCase();
    return lc.contains('webrtc') || lc.contains('flutterwebrtc');
  }

  /// 取 ByteData 的头 [headLen] 与尾 [tailLen] 字节做 hex dump，便于崩溃时回溯协议形态。
  /// 长度不足时降级：bytes.length <= headLen 全部头部输出且不带尾部；
  /// bytes.length 介于 headLen 与 headLen+tailLen 之间时不输出尾部，避免与头部重叠。
  String _hexDump(ByteData m, {int headLen = 64, int tailLen = 32}) {
    final bytes = m.buffer.asUint8List(m.offsetInBytes, m.lengthInBytes);
    String hex(List<int> b) =>
        b.map((v) => v.toRadixString(16).padLeft(2, '0')).join(' ');
    if (bytes.length <= headLen) return hex(bytes);
    if (bytes.length <= headLen + tailLen) return hex(bytes.sublist(0, headLen));
    final head = hex(bytes.sublist(0, headLen));
    final tail = hex(bytes.sublist(bytes.length - tailLen));
    return '$head ... $tail';
  }

  String _describeMessage(String channel, ByteData? message) {
    if (message == null) return 'null_message';
    try {
      final call = _codec.decodeMethodCall(message);
      final argStr = WebRtcCrashLogger.I.jsonOrString(call.arguments);
      return 'method=${call.method} args=$argStr';
    } catch (_) {}
    try {
      final s = _stringCodec.decodeMessage(message);
      return 'strMsg=${WebRtcCrashLogger.I.truncate(s)}';
    } catch (_) {}
    return 'rawBytesLen=${message.lengthInBytes} hex=${_hexDump(message)}';
  }

  String _describeResult(ByteData? reply) {
    if (reply == null) return 'null_reply';
    try {
      final decoded = _codec.decodeEnvelope(reply);
      return 'result=${WebRtcCrashLogger.I.jsonOrString(decoded)}';
    } catch (e) {
      return 'replyBytesLen=${reply.lengthInBytes} decodeErr=$e hex=${_hexDump(reply)}';
    }
  }

  /// 从 MethodCall 消息中尽力取出 method 名；非 MethodCall 返回 null。
  String? _tryMethod(ByteData? message) {
    if (message == null) return null;
    try {
      return _codec.decodeMethodCall(message).method;
    } catch (_) {
      return null;
    }
  }

  /// 节流：同一 key 50ms 内最多放行一次，防错误 / 信令风暴打爆磁盘。
  bool _allowLog(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastLogMs[key];
    if (last != null && now - last < 50) return false;
    if (_lastLogMs.length > 256) _lastLogMs.clear();
    _lastLogMs[key] = now;
    return true;
  }

  /// 是否应记录该消息：噪音 method 丢弃，其余经 50ms 节流。
  bool _shouldLog(String channel, String op, ByteData? message) {
    final method = _tryMethod(message);
    if (method != null && _noisyMethods.contains(method)) return false;
    return _allowLog('$channel|$op|${method ?? '-'}');
  }

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    final isRtc = _isWebRtcChannel(channel);
    var logged = false;
    if (isRtc && _shouldLog(channel, 'send', message)) {
      logged = true;
      // 异步投递：不在 send 同步路径里写盘，UI 线程立即放行消息。
      scheduleMicrotask(() {
        WebRtcCrashLogger.I.log(
          'INFO',
          'mc',
          'send',
          '-',
          'ch=$channel ${_describeMessage(channel, message)}',
        );
      });
    }
    final future = _inner.send(channel, message);
    if (!isRtc || future == null) return future;
    return future.then((reply) {
      // send_reply 仅在对应 send 被记录时才记，保持请求 / 响应成对，
      // 噪音方法的 reply 同样被消除。
      if (logged) {
        scheduleMicrotask(() {
          WebRtcCrashLogger.I.log(
            'INFO',
            'mc',
            'send_reply',
            '-',
            'ch=$channel ${_describeResult(reply)}',
          );
        });
      }
      return reply;
    }, onError: (Object e, StackTrace s) {
      // 错误总是记录（ERROR 级别在 logger 内会立即 flush 落盘）。
      scheduleMicrotask(() {
        WebRtcCrashLogger.I.log(
          'ERROR',
          'mc',
          'send_error',
          '-',
          'ch=$channel error=$e',
        );
      });
      throw e;
    });
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    if (!_isWebRtcChannel(channel) || handler == null) {
      _inner.setMessageHandler(channel, handler);
      return;
    }
    _inner.setMessageHandler(channel, (ByteData? message) async {
      final logged = _shouldLog(channel, 'recv', message);
      if (logged) {
        scheduleMicrotask(() {
          WebRtcCrashLogger.I.log(
            'INFO',
            'mc',
            'recv',
            '-',
            'ch=$channel ${_describeMessage(channel, message)}',
          );
        });
      }
      try {
        final reply = await handler(message);
        if (logged) {
          scheduleMicrotask(() {
            WebRtcCrashLogger.I.log(
              'INFO',
              'mc',
              'recv_reply',
              '-',
              'ch=$channel ${_describeResult(reply)}',
            );
          });
        }
        return reply;
      } catch (e, s) {
        scheduleMicrotask(() {
          WebRtcCrashLogger.I.log(
            'ERROR',
            'mc',
            'recv_error',
            '-',
            'ch=$channel error=$e stack=${s.toString().split('\n').take(8).join(' | ')}',
          );
        });
        rethrow;
      }
    });
  }

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) {
    // ignore: deprecated_member_use
    return _inner.handlePlatformMessage(channel, data, callback);
  }
}

/// 自定义 WidgetsFlutterBinding 子类，override createBinaryMessenger
/// 返回包装过的 messenger。main() 开始处调用
/// [LoggingWidgetsFlutterBinding.ensureInitialized] 替代
/// [WidgetsFlutterBinding.ensureInitialized] 即可启用。
class LoggingWidgetsFlutterBinding extends WidgetsFlutterBinding {
  static WidgetsBinding ensureInitialized() {
    // 不能在这里访问 WidgetsBinding.instance 做判断：未初始化时访问会抛
    // "Null check operator used on a null value"。直接构造子类实例即可，
    // BindingBase 内部会完成注册。main() 内只调用一次，安全。
    LoggingWidgetsFlutterBinding();
    return WidgetsBinding.instance;
  }

  @override
  BinaryMessenger createBinaryMessenger() {
    final inner = super.createBinaryMessenger();
    if (kIsWeb) return inner; // Web 不需要
    return LoggingBinaryMessenger(inner);
  }
}
