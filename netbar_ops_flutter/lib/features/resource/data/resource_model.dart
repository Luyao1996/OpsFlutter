import 'package:freezed_annotation/freezed_annotation.dart';

part 'resource_model.freezed.dart';
part 'resource_model.g.dart';

@freezed
class Resource with _$Resource {
  const factory Resource({
    required int id,
    required String name,
    required String path,
    @JsonKey(name: 'is_directory') required bool isDirectory,
    required String type,
    required int size,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    String? content,
  }) = _Resource;

  factory Resource.fromJson(Map<String, Object?> json) =>
      _ResourceFromJson(json);
}
