import 'package:capman_host/di/auth_module.dart';
import 'package:capman_host/di/env.dart';
import 'package:capman_host/logging/network_log_interceptor.dart';
import 'package:capman_host/shared_data/networking/api_client/api_client.dart';
import 'package:capman_host/shared_data/networking/api_client/api_client_impl.dart';
import 'package:capman_host/shared_data/networking/interceptor/debug_network_interceptor.dart';
import 'package:capman_host/shared_data/networking/interceptor/demo_mock_interceptor.dart';
import 'package:capman_host/shared_data/networking/interceptor/device_auth_interceptor.dart';
import 'package:capman_host/shared_data/networking/interceptor/error_logger_interceptor.dart';
import 'package:capman_host/shared_data/networking/interceptor/modify_by_interceptor.dart';
import 'package:capman_host/shared_data/networking/interceptor/restaurant_interceptor.dart';
import 'package:capman_host/shared_data/networking/interceptor/user_auth_interceptor.dart';
import 'package:capman_host/shared_data/networking/interceptor/version_header_interceptor.dart';
import 'package:capman_host/shared_domain/services/error_logging_service.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

const Auth0 = Named('Auth0');
const UserAuthClient = Named('UserAuthClient');
const DeviceAuthClient = Named('DeviceAuthClient');
const PublicAuthClient = Named('PublicAuthClient');
const BookingDomain = Named('BookingDomain');
const timeout = Duration(seconds: 10);

@module
abstract class NetworkingModule {
  @LazySingleton()
  @development
  @BookingDomain
  String provideDevBaseUrl() => 'https://ws-dev.eng.toastteam.com/';

  @LazySingleton()
  @staging
  @testEnvironment
  @BookingDomain
  String provideStageBaseUrl() => 'https://ws-preprod.eng.toasttab.com/';

  @LazySingleton()
  @production
  @BookingDomain
  String provideProdBaseUrl() => 'https://ws-api.toasttab.com/';

  @LazySingleton()
  @demo
  @BookingDomain
  String provideDemoBaseUrl() => 'http://localhost';

  // ── Non-demo Dio clients (unchanged from original) ────────────────────────

  @LazySingleton()
  @development
  @staging
  @production
  @testEnvironment
  @UserAuthClient
  Dio provideUserAuthDio(
    UserAuthInterceptor userAuthInterceptor,
    ModifyByInterceptor modifyByInterceptor,
    NetworkLogInterceptor logInterceptor,
    VersionHeaderInterceptor versionInterceptor,
    ErrorLoggerInterceptor errorLoggerInterceptor,
    @BookingDomain String baseUrl,
  ) =>
      Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: timeout,
            sendTimeout: timeout,
            receiveTimeout: timeout,
          ),
        )
        ..interceptors.add(userAuthInterceptor)
        ..interceptors.add(modifyByInterceptor)
        ..interceptors.add(versionInterceptor)
        ..interceptors.add(logInterceptor)
        ..interceptors.add(errorLoggerInterceptor);

  @LazySingleton()
  @development
  @staging
  @production
  @testEnvironment
  @DeviceAuthClient
  Dio provideDeviceAuthDio(
    DeviceAuthInterceptor deviceAuthInterceptor,
    ModifyByInterceptor modifyByInterceptor,
    RestaurantInterceptor restaurantInterceptor,
    NetworkLogInterceptor logInterceptor,
    VersionHeaderInterceptor versionInterceptor,
    ErrorLoggerInterceptor errorLoggerInterceptor,
    DebugNetworkInterceptor debugNetworkInterceptor,
    @BookingDomain String baseUrl,
  ) =>
      Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: timeout,
            sendTimeout: timeout,
            receiveTimeout: timeout,
          ),
        )
        ..interceptors.add(deviceAuthInterceptor)
        ..interceptors.add(modifyByInterceptor)
        ..interceptors.add(restaurantInterceptor)
        ..interceptors.add(versionInterceptor)
        ..interceptors.add(logInterceptor)
        ..interceptors.add(errorLoggerInterceptor)
        ..interceptors.add(debugNetworkInterceptor);

  @LazySingleton()
  @development
  @staging
  @production
  @testEnvironment
  @Auth0
  Dio provideAuth0Dio(
    @AuthDomain String authDomain,
    NetworkLogInterceptor logInterceptor,
    VersionHeaderInterceptor versionInterceptor,
    ErrorLoggerInterceptor errorLoggerInterceptor,
  ) =>
      Dio(
          BaseOptions(
            baseUrl: 'https://$authDomain/',
            connectTimeout: timeout,
            sendTimeout: timeout,
            receiveTimeout: timeout,
            contentType: Headers.formUrlEncodedContentType,
          ),
        )
        ..interceptors.add(versionInterceptor)
        ..interceptors.add(logInterceptor)
        ..interceptors.add(errorLoggerInterceptor);

  @LazySingleton()
  @development
  @staging
  @production
  @testEnvironment
  @PublicAuthClient
  Dio providePublicAuthDio(
    NetworkLogInterceptor logInterceptor,
    VersionHeaderInterceptor versionInterceptor,
    ErrorLoggerInterceptor errorLoggerInterceptor,
    @BookingDomain String baseUrl,
  ) =>
      Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: timeout,
            sendTimeout: timeout,
            receiveTimeout: timeout,
          ),
        )
        ..interceptors.add(versionInterceptor)
        ..interceptors.add(logInterceptor)
        ..interceptors.add(errorLoggerInterceptor);

  // ── Demo Dio clients (all requests resolved by DemoMockInterceptor) ───────

  @LazySingleton()
  @demo
  @UserAuthClient
  Dio provideDemoUserAuthDio(DemoMockInterceptor mockInterceptor) =>
      Dio(BaseOptions(baseUrl: 'http://localhost'))
        ..interceptors.add(mockInterceptor);

  @LazySingleton()
  @demo
  @DeviceAuthClient
  Dio provideDemoDeviceAuthDio(DemoMockInterceptor mockInterceptor) =>
      Dio(BaseOptions(baseUrl: 'http://localhost'))
        ..interceptors.add(mockInterceptor);

  @LazySingleton()
  @demo
  @Auth0
  Dio provideDemoAuth0Dio(DemoMockInterceptor mockInterceptor) =>
      Dio(BaseOptions(baseUrl: 'http://localhost'))
        ..interceptors.add(mockInterceptor);

  @LazySingleton()
  @demo
  @PublicAuthClient
  Dio provideDemoPublicAuthDio(DemoMockInterceptor mockInterceptor) =>
      Dio(BaseOptions(baseUrl: 'http://localhost'))
        ..interceptors.add(mockInterceptor);

  // ── ApiClient wrappers (shared across all environments) ───────────────────

  @LazySingleton()
  @UserAuthClient
  ApiClient provideUserAuthApiClient(@UserAuthClient Dio dio) => ApiClientImpl(dio);

  @LazySingleton()
  @DeviceAuthClient
  ApiClient provideDeviceAuthApiClient(@DeviceAuthClient Dio dio) => ApiClientImpl(dio);

  @LazySingleton()
  @Auth0
  ApiClient provideAuth0ApiClient(@Auth0 Dio dio) => ApiClientImpl(dio);

  @LazySingleton()
  @PublicAuthClient
  ApiClient providePublicAuthApiClient(@PublicAuthClient Dio dio) => ApiClientImpl(dio);

  @LazySingleton()
  NetworkLogInterceptor provideLogInterceptor() => NetworkLogInterceptor();

  @LazySingleton()
  ErrorLoggerInterceptor errorLogInterceptor(ErrorLoggingService errorLoggingService) =>
      ErrorLoggerInterceptor(errorLoggingService);
}
