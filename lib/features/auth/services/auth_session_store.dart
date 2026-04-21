import 'package:hive/hive.dart';

import '../models/auth_models.dart';

class AuthSessionStore {
  static const _boxName = 'landbox';
  static const _tokenKey = 'auth_token';
  static const _userIdKey = 'auth_user_id';
  static const _firstNameKey = 'auth_first_name';
  static const _lastNameKey = 'auth_last_name';
  static const _emailKey = 'auth_email';
  static const _phoneKey = 'auth_phone';
  static const _fullNameKey = 'auth_name';
  static const _roleKey = 'auth_role';
  static const _isActiveKey = 'auth_is_active';
  static const _isVerifiedKey = 'auth_is_verified';
  static const _emailVerifiedAtKey = 'auth_email_verified_at';
  static const _createdAtKey = 'auth_created_at';

  Box get _box => Hive.box(_boxName);

  AuthSession read() {
    final token = _string(_box.get(_tokenKey));
    final email = _string(_box.get(_emailKey));
    final name = _string(_box.get(_fullNameKey));
    final userId = _string(_box.get(_userIdKey));

    AuthUser? user;
    if (email.isNotEmpty || name.isNotEmpty || userId.isNotEmpty) {
      final firstName = _string(_box.get(_firstNameKey));
      final lastName = _string(_box.get(_lastNameKey));
      user = AuthUser(
        id: userId,
        name: name.isNotEmpty ? name : [firstName, lastName].where((e) => e.isNotEmpty).join(' ').trim(),
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: _nullable(_box.get(_phoneKey)),
        role: _string(_box.get(_roleKey), fallback: 'user'),
        isActive: _box.get(_isActiveKey) as bool? ?? true,
        emailVerifiedAt: _nullable(_box.get(_emailVerifiedAtKey)),
        isVerified: _box.get(_isVerifiedKey) as bool? ?? false,
        createdAt: _nullable(_box.get(_createdAtKey)),
      );
    }

    return AuthSession(user: user, token: token);
  }

  Future<void> save(AuthSession session) async {
    final user = session.user;
    await _box.put(_tokenKey, session.token.trim());

    if (user == null) {
      await clearUserOnly();
      return;
    }

    await _box.put(_userIdKey, user.id);
    await _box.put(_firstNameKey, user.firstName);
    await _box.put(_lastNameKey, user.lastName);
    await _box.put(_fullNameKey, user.name);
    await _box.put(_emailKey, user.email);
    await _putNullable(_phoneKey, user.phone);
    await _box.put(_roleKey, user.role);
    await _box.put(_isActiveKey, user.isActive);
    await _box.put(_isVerifiedKey, user.isVerified);
    await _putNullable(_emailVerifiedAtKey, user.emailVerifiedAt);
    await _putNullable(_createdAtKey, user.createdAt);
  }

  Future<void> clear() async {
    await _box.delete(_tokenKey);
    await clearUserOnly();
  }

  Future<void> clearUserOnly() async {
    await _box.delete(_userIdKey);
    await _box.delete(_firstNameKey);
    await _box.delete(_lastNameKey);
    await _box.delete(_fullNameKey);
    await _box.delete(_emailKey);
    await _box.delete(_phoneKey);
    await _box.delete(_roleKey);
    await _box.delete(_isActiveKey);
    await _box.delete(_isVerifiedKey);
    await _box.delete(_emailVerifiedAtKey);
    await _box.delete(_createdAtKey);
  }

  String _string(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String? _nullable(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  Future<void> _putNullable(String key, String? value) async {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      await _box.delete(key);
      return;
    }
    await _box.put(key, normalized);
  }
}
