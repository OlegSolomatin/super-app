// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

User _$UserFromJson(Map<String, dynamic> json) => User(
  id: (json['id'] as num).toInt(),
  email: json['email'] as String,
  username: json['username'] as String,
  avatarUrl: json['avatar_url'] as String?,
  bio: json['bio'] as String?,
  roles: json['roles'] == null
      ? null
      : User._parseRoles(json['roles']),
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'id': instance.id,
  'email': instance.email,
  'username': instance.username,
  'avatar_url': instance.avatarUrl,
  'bio': instance.bio,
  'roles': instance.roles,
};
