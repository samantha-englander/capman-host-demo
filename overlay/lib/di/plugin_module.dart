import 'dart:io';

import 'package:amplitude_flutter/amplitude.dart';
import 'package:amplitude_flutter/configuration.dart';
import 'package:capman_host/di/env.dart';
import 'package:capman_host/features/main/main/ui/tab/tab_bloc.dart';
import 'package:capman_host/shared_data/networking/services/analytics/no_op_toast_analytics_service.dart';
import 'package:capman_host/shared_data/networking/services/analytics/toast_analytics_service.dart';
import 'package:capman_host/shared_data/networking/services/analytics/toast_analytics_service_impl.dart';
import 'package:capman_host/shared_domain/model/app_info.dart';
import 'package:capman_host/shared_domain/model/app_version.dart';
import 'package:capman_host/shared_domain/services/current_restaurant_service.dart';
import 'package:capman_host/shared_ui/app_route_observer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:package_info_plus/package_info_plus.dart';

@module
abstract class PluginModule {
  @LazySingleton()
  Connectivity provideConnectivity() => Connectivity();

  @LazySingleton()
  @production
  ToastAnalyticsService toastAnalyticsServiceProd(
    CurrentRestaurantService currentRestaurantService,
    AppRouteObserver appRouteObserver,
    TabBloc tabBloc,
  ) => (!kIsWeb && Platform.isWindows)
      ? NoOpToastAnalyticsService()
      : ToastAnalyticsServiceImpl(
          Amplitude(Configuration(apiKey: '23cdb596a1df3ace4b6ac0bdb0423b76')),
          currentRestaurantService,
          appRouteObserver,
          tabBloc,
        );

  @LazySingleton()
  @staging
  @development
  @test
  ToastAnalyticsService toastAnalyticsServicePreProd(
    CurrentRestaurantService currentRestaurantService,
    AppRouteObserver appRouteObserver,
    TabBloc tabBloc,
  ) => (!kIsWeb && Platform.isWindows)
      ? NoOpToastAnalyticsService()
      : ToastAnalyticsServiceImpl(
          Amplitude(Configuration(apiKey: '403519ecc49a7e177d1d9b424a231fec')),
          currentRestaurantService,
          appRouteObserver,
          tabBloc,
        );

  @LazySingleton()
  @demo
  ToastAnalyticsService toastAnalyticsServiceDemo(
    CurrentRestaurantService currentRestaurantService,
    AppRouteObserver appRouteObserver,
    TabBloc tabBloc,
  ) => NoOpToastAnalyticsService();

  @LazySingleton()
  @preResolve
  Future<AppInfo> get appInfo => () async {
    return appInfoFromPackageInfo(await PackageInfo.fromPlatform());
  }();

  @LazySingleton()
  DeviceInfoPlugin get deviceInfoPlugin => DeviceInfoPlugin();
}

//for android flavors version looks like, X.X.X-flavor. for iOS it looks like X.X.X. That's why we split version by '-'
AppInfo appInfoFromPackageInfo(PackageInfo packageInfo) {
  final versionWithEnvSuffix = packageInfo.version;
  final version = versionWithEnvSuffix.split('-').first;

  return AppInfo(
    version: AppVersion.fromString(version),
    buildNumber: packageInfo.buildNumber,
  );
}
