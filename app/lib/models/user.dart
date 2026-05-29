import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@JsonSerializable()
class User {
  final String id;
  final String email;
  final String username;

  @JsonKey(name: 'avatar_url')
  final String? avatarUrl;

  final String? bio;

  @JsonKey(name: 'roles', fromJson: _parseRoles, toJson: _rolesToJson)
  final List<String>? roles;

  const User({
    required this.id,
    required this.email,
    required this.username,
    this.avatarUrl,
    this.bio,
    this.roles,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  Map<String, dynamic> toJson() => _$UserToJson(this);

  static List<String>? _parseRoles(dynamic roles) {
    if (roles == null) return null;
    if (roles is List) {
      return roles.map((r) {
        if (r is String) return r;
        if (r is Map) return r['name'] as String? ?? '';
        return r.toString();
      }).toList();
    }
    return null;
  }

  static dynamic _rolesToJson(List<String>? roles) => roles;
}
