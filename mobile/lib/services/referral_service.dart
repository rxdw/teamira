import '../models/referral.dart';
import 'api_client.dart';

/// Talks to GET /referrals/status (backend/app/routers/referrals.py) —
/// the one endpoint behind both the home screen's "Пригласи друга" card
/// and the "Мои приглашения" screen. See that router's own docstring:
/// each call also (re)verifies this account's own pending invitees, so
/// there's no separate refresh/verify action to wire up here.
class ReferralService {
  final ApiClient _client;
  ReferralService(this._client);

  Future<ReferralStatus> status() async {
    final json = await _client.get('/referrals/status') as Map<String, dynamic>;
    return ReferralStatus.fromJson(json);
  }
}
