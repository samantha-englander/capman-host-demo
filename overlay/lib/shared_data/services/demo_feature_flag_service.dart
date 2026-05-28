import 'package:capman_host/shared_domain/services/feature_flag_service.dart';

// No-op FeatureFlagService for demo — avoids the LaunchDarkly network call.
// Only enables flags that are confirmed production; beta flags default to false
// so the demo mirrors production rather than Testflight/pre-prod.
class DemoFeatureFlagService implements FeatureFlagService {
  static const _productionFlags = {
    'nv1-waitlist-v2',
    'nv1-guest-on-site-indicator',
    'nv1-combined-floor-plan-view',
  };

  @override
  Future<void> init({required String? restaurantGuid, required String? managementGroupGuid}) async {}

  @override
  Future<void> identify({required String? restaurantGuid, required String? managementGroupGuid}) async {}

  @override
  Stream<bool> isEnabledStream(BoolFlag flag) =>
      Stream.value(_productionFlags.contains(flag.key));

  @override
  Stream<String> stringVariationStream(StringFlag flag, {required String defaultValue}) =>
      Stream.value(defaultValue);
}
