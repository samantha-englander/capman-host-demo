import 'package:capman_host/shared_domain/services/feature_flag_service.dart';

// No-op FeatureFlagService for demo — avoids the LaunchDarkly network call.
// Only enables flags that are confirmed production; beta flags default to false
// so the demo mirrors production rather than Testflight/pre-prod.
class DemoFeatureFlagService implements FeatureFlagService {
  // Explicit allowlist of flag keys we want ON in the demo. Anything else
  // returns false. Listed verbatim (not enum-derived) so a new flag shipped
  // by capman-host doesn't get silently disabled OR silently enabled — it
  // hits the catch-all `false` until someone reviews it intentionally.
  //
  // Reviewed against capman-host @develop FeatureFlag enum (7 BoolFlags).
  static const _productionFlags = {
    'nv1-waitlist-v2',
    'nv1-guest-on-site-indicator',
    'nv1-combined-floor-plan-view',
    'nv1-home-tab-redesign',
    // Theme picker in drawer Settings — polished low-risk demo moment.
    'nv1-app-theme-selection',
  };
  // Flags we explicitly leave OFF:
  //   nv1-ticketed-events-host-app  (not in demo narrative — would show an
  //                                   empty events surface)
  //   nv1-in-app-notifications      (WIP server-side; would show empty UI)

  @override
  Future<void> init({required String? restaurantGuid, required String? managementGroupGuid}) async {}

  @override
  Future<void> identify({required String? restaurantGuid, required String? managementGroupGuid}) async {}

  @override
  Stream<bool> isEnabledStream(BoolFlag flag) =>
      Stream.value(_productionFlags.contains(flag.key));

  @override
  Stream<String> stringVariationStream(StringFlag flag, {required String defaultValue}) {
    // nv1-v1-home-tab-forced-upgrade-date returns a date string; if any
    // caller passes a past date as defaultValue we'd trigger a forced-
    // upgrade modal mid-demo. Override to empty so the upgrade check
    // never fires regardless of what the call site defaults to.
    if (flag.key == 'nv1-v1-home-tab-forced-upgrade-date') return Stream.value('');
    return Stream.value(defaultValue);
  }
}
