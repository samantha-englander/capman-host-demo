import 'package:capman_host/di/env.dart';
import 'package:capman_host/shared_data/networking/services/analytics/toast_analytics_service.dart';
import 'package:capman_host/shared_data/services/demo_feature_flag_service.dart';
import 'package:capman_host/shared_data/services/feature_flag_analytics_sync_service.dart';
import 'package:capman_host/shared_data/services/feature_flag_service_launch_darkly.dart';
import 'package:capman_host/shared_data/services/overridable_feature_flag_service.dart';
import 'package:capman_host/shared_data/storage/preferences_storage.dart';
import 'package:capman_host/shared_domain/model/app_info.dart';
import 'package:capman_host/shared_domain/services/feature_flag_service.dart';
import 'package:capman_host/shared_ui/bloc/app_config/app_config_state.dart';
import 'package:injectable/injectable.dart';
import 'package:launchdarkly_flutter_client_sdk/launchdarkly_flutter_client_sdk.dart';

class LaunchDarklyKey {
  const LaunchDarklyKey(this.key);
  final String key;
}

@module
abstract class LaunchDarklyModule {
  @LazySingleton()
  LDConfig provideLDConfig(LaunchDarklyKey key) => LDConfig(key.key, AutoEnvAttributes.enabled);

  @LazySingleton()
  @testEnvironment
  LaunchDarklyKey provideTestAppVersionSuffix() => const LaunchDarklyKey('mob-f39a2fad-c8dc-4a8b-8f83-596b7c6fc376');

  @LazySingleton()
  @development
  LaunchDarklyKey provideDevelopmentLaunchDarklyKey() => const LaunchDarklyKey('mob-3015a75c-f3d3-49ba-9bdd-ae43707b6e33');

  @LazySingleton()
  @staging
  LaunchDarklyKey provideStagingAppVersionSuffix() => const LaunchDarklyKey('mob-f39a2fad-c8dc-4a8b-8f83-596b7c6fc376');

  @LazySingleton()
  @production
  LaunchDarklyKey provideProductionAppVersionSuffix() => const LaunchDarklyKey('mob-30e87101-c8ca-4252-84bf-a7115e4c4633');

  @LazySingleton()
  @demo
  LaunchDarklyKey provideDemoLaunchDarklyKey() => const LaunchDarklyKey('mob-f39a2fad-c8dc-4a8b-8f83-596b7c6fc376');

  @LazySingleton()
  @development
  @staging
  @production
  FeatureFlagService provideFeatureFlagService(
    LDConfig ldConfig,
    AppInfo appInfo,
    AppConfigState appConfig,
    PreferencesStorage preferencesStorage,
  ) {
    final ldService = FeatureFlagServiceLaunchDarkly(ldConfig, appInfo);
    return appConfig.debugFeaturesEnabled
        ? OverridableFeatureFlagService(ldService, storage: preferencesStorage)
        : ldService;
  }

  @LazySingleton()
  @demo
  FeatureFlagService provideDemoFeatureFlagService() => DemoFeatureFlagService();

  @LazySingleton()
  FeatureFlagAnalyticsSyncService provideFeatureFlagAnalyticsSyncService(
    FeatureFlagService featureFlagService,
    ToastAnalyticsService analyticsService,
  ) => FeatureFlagAnalyticsSyncService(featureFlagService, analyticsService, FeatureFlag.values);
}
