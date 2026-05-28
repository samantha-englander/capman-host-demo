import 'package:capman_host/di/env.dart';
import 'package:capman_host/shared_domain/model/app_info.dart';
import 'package:capman_host/shared_ui/bloc/app_config/app_config_state.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

@module
abstract class AppConfigModule {
  @LazySingleton()
  @development
  AppConfigState provideDevelopment(AppInfo appInfo) => AppConfigState(
    isProduction: false,
    isStaging: false,
    debugFeaturesEnabled: kDebugMode,
    appVersion: appInfo.version.toString(),
  );

  @LazySingleton()
  @staging
  AppConfigState provideStaging(AppInfo appInfo) => AppConfigState(
    isProduction: false,
    isStaging: true,
    debugFeaturesEnabled: true,
    appVersion: appInfo.version.toString(),
  );

  @LazySingleton()
  @production
  AppConfigState provideProduction(AppInfo appInfo) => AppConfigState(
    isProduction: true,
    isStaging: false,
    debugFeaturesEnabled: kDebugMode,
    appVersion: appInfo.version.toString(),
  );

  @LazySingleton()
  @testEnvironment
  AppConfigState provideTest(AppInfo appInfo) => AppConfigState(
    isProduction: false,
    isStaging: true,
    debugFeaturesEnabled: true,
    appVersion: appInfo.version.toString(),
  );

  @LazySingleton()
  @demo
  AppConfigState provideDemo(AppInfo appInfo) => AppConfigState(
    isProduction: false,
    isStaging: false,
    debugFeaturesEnabled: false,
    appVersion: appInfo.version.toString(),
  );
}
