import 'dart:io';

import 'package:capman_host/di/env.dart';
import 'package:capman_host/di/networking_module.dart';
import 'package:capman_host/features/session/data/auth_service_oauth.dart';
import 'package:capman_host/features/session/data/auth_service_windows.dart';
import 'package:capman_host/features/session/data/demo_auth_service.dart';
import 'package:capman_host/features/session/data/int_test_auth_service.dart';
import 'package:capman_host/features/session/domain/auth_service.dart';
import 'package:capman_host/shared_data/networking/api_client/api_client.dart';
import 'package:capman_host/shared_domain/services/error_logging_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart' as flutter_appauth;
import 'package:injectable/injectable.dart';

const AuthDomain = Named('AuthDomain');
const ClientId = Named('ClientId');
const CallbackUrl = Named('CallbackUrl');

@module
abstract class AuthModule {
  @development
  @staging
  @production
  @LazySingleton()
  AuthService provideOAuthService({
    @ClientId required String clientId,
    @AuthDomain required String authDomain,
    @CallbackUrl required String callbackUrl,
    required ErrorLoggingService errorLoggingService,
  }) => Platform.isWindows
      ? AuthServiceWindows(
          errorLoggingService,
          clientId: clientId,
          authDomain: authDomain,
          callbackUrl: callbackUrl,
        )
      : AuthServiceOAuth(
          const flutter_appauth.FlutterAppAuth(),
          errorLoggingService,
          clientId: clientId,
          authDomain: authDomain,
          callbackUrl: callbackUrl,
        );

  @testEnvironment
  @LazySingleton()
  AuthService provideIntTestAuthService(@Auth0 ApiClient apiClient) =>
      IntTestAuthService(apiClient);

  @demo
  @LazySingleton()
  AuthService provideDemoAuthService() => DemoAuthService();

  @LazySingleton()
  @development
  @AuthDomain
  String provideAuthDomainDevelopment() => 'auth.v2.dev.eng.toastteam.com';

  @LazySingleton()
  @staging
  @testEnvironment
  @AuthDomain
  String provideAuthDomainStaging() => 'auth.preprod.eng.toasttab.com';

  @LazySingleton()
  @production
  @AuthDomain
  String provideAuthDomainProduction() => 'auth.toasttab.com';

  @LazySingleton()
  @demo
  @AuthDomain
  String provideAuthDomainDemo() => 'auth.v2.dev.eng.toastteam.com';

  @LazySingleton()
  @development
  @ClientId
  String provideClientIdDevelopment() => 'B2ylyK6zZoPxpGPuho9AVtEj46wuxfxB';

  @LazySingleton()
  @staging
  @testEnvironment
  @ClientId
  String provideClientIdStaging() => 'MmjYTPtMarRMFnnQUdgn4gSTLqydFxqF';

  @LazySingleton()
  @production
  @ClientId
  String provideClientIdProduction() => 'ltBFhEb8s3VvSqgx9xYcAjcpFrhFNj96';

  @LazySingleton()
  @demo
  @ClientId
  String provideClientIdDemo() => 'B2ylyK6zZoPxpGPuho9AVtEj46wuxfxB';

  @LazySingleton()
  @development
  @CallbackUrl
  String provideCallbackUrlDevelopment() {
    if (kIsWeb) {
      return 'http://localhost:3000/callback';
    }
    if (Platform.isAndroid) {
      return 'com.toasttab.tos.capmanhost://toast-pos.toast-dev.auth0.com/android/com.toastlab.pos.capman_host.development/callback';
    }
    return 'com.toastlab.pos.capmanHost://toast-pos.toast-dev.auth0.com/ios/com.toastlab.pos.capmanHost.development/callback';
  }

  @LazySingleton()
  @staging
  @testEnvironment
  @CallbackUrl
  String provideCallbackUrlStaging() {
    if (kIsWeb) {
      return 'http://localhost:3000/callback';
    }
    if (Platform.isAndroid) {
      return 'com.toasttab.tos.capmanhost://preproduction-toast-pos.toasttab.auth0.com/android/com.toastlab.pos.capman_host.preprod/callback';
    }
    return 'com.toastlab.pos.capmanHost://preproduction-toast-pos.toasttab.auth0.com/ios/com.toastlab.pos.capmanHost.preprod/callback';
  }

  @LazySingleton()
  @production
  @CallbackUrl
  String provideCallbackUrlProduction() {
    if (kIsWeb) {
      return 'http://localhost:3000/callback';
    }
    if (Platform.isAndroid) {
      return 'com.toasttab.tos.capmanhost://toast-pos.toasttab.auth0.com/android/com.toastlab.pos.capman_host/callback';
    }
    return 'com.toastlab.pos.capmanHost://toast-pos.toasttab.auth0.com/ios/com.toastlab.pos.capmanHost/callback';
  }

  @LazySingleton()
  @demo
  @CallbackUrl
  String provideCallbackUrlDemo() => 'http://localhost:3000/callback';
}
