import 'dart:convert';
import 'dart:typed_data';

import 'task_ws.dart';

/// wsbin 二进制帧（解析结果）。
///
/// 协议定义见《WebSocket 二进制通信协议（wsbin）》：
///   magic(4B 固定 0x7B 0x01 0x02 0x03) + payload_len(u32 LE)
///   + data_type(1B) + event_len(1B)+event + id_len(1B)+id
///   + data_len(u32 LE)+data
/// 所有多字节整数均为小端序。
class WsBinaryFrame {
  /// 0=JSON, 1=文本, 2=二进制
  final int dataType;

  /// 等同 peer 协议的 fun（如 "thumbnail"）
  final String event;

  /// 等同 peer 协议的 id，用于关联请求-响应
  final String id;

  /// 实际载荷（如 JPG 图片字节）
  final Uint8List data;

  const WsBinaryFrame({
    required this.dataType,
    required this.event,
    required this.id,
    required this.data,
  });
}

/// wsbin 帧编解码器。本项目只接收二进制响应（thumbnail 等），
/// 请求仍走现有 JSON peer 命令，故只实现 [parse]，不实现 build。
class WsBinary {
  static const List<int> _magic = [0x7B, 0x01, 0x02, 0x03];

  /// 解析一个 wsbin 帧。magic 不符 / 长度不足 / 越界 → 返回 null（由上层丢弃）。
  static WsBinaryFrame? parse(Uint8List frame) {
    if (frame.length < 8) return null;
    for (var i = 0; i < 4; i++) {
      if (frame[i] != _magic[i]) return null;
    }
    final bd = ByteData.sublistView(frame);
    final payloadLen = bd.getUint32(4, Endian.little);
    if (frame.length < 8 + payloadLen) return null;

    var pos = 8;
    if (pos + 1 > frame.length) return null;
    final dataType = frame[pos];
    pos += 1;

    if (pos + 1 > frame.length) return null;
    final eventLen = frame[pos];
    pos += 1;
    if (pos + eventLen > frame.length) return null;
    final event = utf8.decode(frame.sublist(pos, pos + eventLen));
    pos += eventLen;

    if (pos + 1 > frame.length) return null;
    final idLen = frame[pos];
    pos += 1;
    if (pos + idLen > frame.length) return null;
    final id = utf8.decode(frame.sublist(pos, pos + idLen));
    pos += idLen;

    if (pos + 4 > frame.length) return null;
    final dataLen = bd.getUint32(pos, Endian.little);
    pos += 4;
    if (pos + dataLen > frame.length) return null;
    final data = Uint8List.sublistView(frame, pos, pos + dataLen);

    return WsBinaryFrame(
      dataType: dataType,
      event: event,
      id: id,
      data: data,
    );
  }
}

/// 通过 wsbin 协议请求一张缩略图（300px JPG）。
///
/// 请求仍走现有 JSON peer 命令（`fun:'thumbnail'`），响应为 wsbin 二进制帧，
/// 由 [TaskWs] 实现层（[task_ws_client] 的 `_onBinaryFrame`）解析后以
/// [Uint8List] 完成 [TaskWs.request] 的 Future。
///
/// 失败 / 超时 / 解析失败时返回 null，调用方据此走各自的重试/降级逻辑。
Future<Uint8List?> requestThumbnail(
  TaskWs ws, {
  required String seatId,
  required int merchantId,
}) async {
  final res = await ws.request(
    fun: 'thumbnail',
    seat: seatId,
    merchantId: merchantId,
  );
  if (res is Uint8List) return res;
  if (res is List<int>) return Uint8List.fromList(res);
  return null;
}
