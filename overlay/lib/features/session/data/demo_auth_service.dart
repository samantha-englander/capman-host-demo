import 'package:capman_host/features/session/domain/auth_service.dart';
import 'package:capman_host/shared_data/networking/result.dart';
import 'package:capman_host/shared_domain/model/auth_token.dart';

class DemoAuthService implements AuthService {
  @override
  Future<Result<AuthError, AuthToken>> login() async {
    return Result.success(
      AuthToken(
        accessToken: 'demo-access-token',
        refreshToken: 'demo-refresh-token',
      ),
    );
  }

  @override
  Future<void> logout({String? accessToken}) async {}
}
