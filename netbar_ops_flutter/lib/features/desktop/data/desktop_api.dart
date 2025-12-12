import '../../../core/network/api_client.dart';
import 'desktop_model.dart';

class DesktopApi {
  final ApiClient _client = ApiClient.instance;

  Future<List<DesktopLayout>> getLayouts() async {
    final res = await _client.get('/desktop-layouts');
    final list = res.data as List? ?? [];
    return list.map((e) => DesktopLayout.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<DesktopLayout> createLayout(DesktopLayout layout) async {
    final res = await _client.post('/desktop-layouts', data: layout.toJson());
    return DesktopLayout.fromJson(res.data as Map<String, dynamic>);
  }

  Future<DesktopLayout> updateLayout(DesktopLayout layout) async {
    if (layout.id == null) return createLayout(layout);
    final res = await _client.put('/desktop-layouts/${layout.id}', data: layout.toJson());
    return DesktopLayout.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteLayout(int id) async {
    await _client.delete('/desktop-layouts/$id');
  }
}
