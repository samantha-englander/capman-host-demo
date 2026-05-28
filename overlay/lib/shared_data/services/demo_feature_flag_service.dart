import 'package:capman_host/shared_domain/services/feature_flag_service.dart';

// No-op implementation for demo — avoids the LaunchDarkly network call that
// blocks restaurant selection when LD returns 404 in the demo environment.
class DemoFeatureFlagService implements FeatureFlagService {
  @override
  Future<void> init({required String? restaurantGuid, required String? managementGroupGuid}) async {}

  @override
  Future<void> identify({required String? restaurantGuid, required String? managementGroupGuid}) async {}

  @override
  Stream<bool> isEnabledStream(BoolFlag flag) => Stream.value(true);

  @override
  Stream<String> stringVariationStream(StringFlag flag, {required String defaultValue}) =>
      Stream.value(defaultValue);
}
