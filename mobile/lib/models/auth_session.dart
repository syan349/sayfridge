import 'app_user.dart';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user
  });

  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final AppUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access_token'] as String, 
      tokenType: json['token_type'] as String, 
      expiresIn: json['expires_in'] as int, 
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}