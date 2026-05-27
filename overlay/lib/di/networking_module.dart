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
  @demo
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

  // ── UserAuth Dio ──────────────────────────────────────────────────────────
  // @demo stacked on @development. DemoMockInterceptor (all-envs singleton)
  // short-circuits all requests when running as demo, passes through in dev.

  @LazySingleton()
  @development
  @demo
  @UserAuthClient
  Dio provideUserAuthDio(
    UserAuthInterceptor userAuthInterceptor,
    ModifyByInterceptor modifyByInterceptor,
    NetworkLogInterceptor logInterceptor,
    VersionHeaderInterceptor versionInterceptor,
    ErrorLoggerInterceptor errorLoggerInterceptor,
    DemoMockInterceptor demoMockInterceptor,
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
        ..interceptors.add(demoMockInterceptor) // first — short-circuits in demo
        ..interceptors.add(userAuthInterceptor)
        ..interceptors.add(modifyByInterceptor)
        ..interceptors.add(versionInterceptor)
        ..interceptors.add(logInterceptor)
        ..interceptors.add(errorLoggerInterceptor);

  @LazySingleton()
  @staging
  @production
  @testEnvironment
  @UserAuthClient
  Dio provideUserAuthDioNonDev(
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

  // ── DeviceAuth Dio ────────────────────────────────────────────────────────

  @LazySingleton()
  @development
  @demo
  @DeviceAuthClient
  Dio provideDeviceAuthDio(
    DeviceAuthInterceptor deviceAuthInterceptor,
    ModifyByInterceptor modifyByInterceptor,
    RestaurantInterceptor restaurantInterceptor,
    NetworkLogInterceptor logInterceptor,
    VersionHeaderInterceptor versionInterceptor,
    ErrorLoggerInterceptor errorLoggerInterceptor,
    DebugNetworkInterceptor debugNetworkInterceptor,
    DemoMockInterceptor demoMockInterceptor,
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
        ..interceptors.add(demoMockInterceptor) // first — short-circuits in demo
        ..interceptors.add(deviceAuthInterceptor)
        ..interceptors.add(modifyByInterceptor)
        ..interceptors.add(restaurantInterceptor)
        ..interceptors.add(versionInterceptor)
        ..interceptors.add(logInterceptor)
        ..interceptors.add(errorLoggerInterceptor)
        ..interceptors.add(debugNetworkInterceptor);

  @LazySingleton()
  @staging
  @production
  @testEnvironment
  @DeviceAuthClient
  Dio provideDeviceAuthDioNonDev(
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

  // ── Auth0 Dio ─────────────────────────────────────────────────────────────

  @LazySingleton()
  @development
  @demo
  @Auth0
  Dio provideAuth0Dio(
    @AuthDomain String authDomain,
    NetworkLogInterceptor logInterceptor,
    VersionHeaderInterceptor versionInterceptor,
    ErrorLoggerInterceptor errorLoggerInterceptor,
    DemoMockInterceptor demoMockInterceptor,
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
        ..interceptors.add(demoMockInterceptor) // first — short-circuits in demo
        ..interceptors.add(versionInterceptor)
        ..interceptors.add(logInterceptor)
        ..interceptors.add(errorLoggerInterceptor);

  @LazySingleton()
  @staging
  @production
  @testEnvironment
  @Auth0
  Dio provideAuth0DioNonDev(
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

  // ── PublicAuth Dio ────────────────────────────────────────────────────────

  @LazySingleton()
  @development
  @demo
  @PublicAuthClient
  Dio providePublicAuthDio(
    NetworkLogInterceptor logInterceptor,
    VersionHeaderInterceptor versionInterceptor,
    ErrorLoggerInterceptor errorLoggerInterceptor,
    DemoMockInterceptor demoMockInterceptor,
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
        ..interceptors.add(demoMockInterceptor) // first — short-circuits in demo
        ..interceptors.add(versionInterceptor)
        ..interceptors.add(logInterceptor)
        ..interceptors.add(errorLoggerInterceptor);

  @LazySingleton()
  @staging
  @production
  @testEnvironment
  @PublicAuthClient
  Dio providePublicAuthDioNonDev(
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
