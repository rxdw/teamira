import '../models/profile_stats.dart';
import 'api_client.dart';

class AuthService {
  final ApiClient _client;
  AuthService(this._client);

  Future<void> register(String username, String password, {String? referralCode}) async {
    final code = referralCode?.trim();
    final json = await _client.post(
      '/auth/register',
      body: {
        'username': username,
        'password': password,
        if (code != null && code.isNotEmpty) 'referral_code': code,
      },
      auth: false,
    ) as Map<String, dynamic>;
    await _client.setToken(json['access_token'] as String);
  }

  Future<void> login(String username, String password) async {
    final json = await _client.post(
      '/auth/login',
      body: {'username': username, 'password': password},
      auth: false,
    ) as Map<String, dynamic>;
    await _client.setToken(json['access_token'] as String);
  }

  Future<void> logout() => _client.setToken(null);

  Future<SeenlyUser> me() async {
    final json = await _client.get('/auth/me') as Map<String, dynamic>;
    return SeenlyUser.fromJson(json);
  }
}
