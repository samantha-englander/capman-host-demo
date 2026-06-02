import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:capman_host/di/bloc_factory.dart';
import 'package:capman_host/di/di.dart';
import 'package:capman_host/di/env.dart';
import 'package:capman_host/features/force_update/ui/force_update_bloc.dart';
import 'package:capman_host/features/force_update/ui/force_update_dialog.dart';
import 'package:capman_host/features/force_update/ui/force_update_state.dart';
import 'package:capman_host/features/main/booking_limit/ui/booking_limit_bloc.dart';
import 'package:capman_host/features/main/estimate_wait_time/ui/estimate_wait_time_bloc.dart';
import 'package:capman_host/features/main/feed/feed_bloc.dart';
import 'package:capman_host/features/main/main/ui/drawer/drawer_bloc.dart';
import 'package:capman_host/features/main/main/ui/drawer/settings/settings_bloc.dart';
import 'package:capman_host/features/main/main/ui/main_route.dart';
import 'package:capman_host/features/main/main/ui/tab/tab_bloc.dart';
import 'package:capman_host/features/main/messages/ui/bloc/sms/message_bloc.dart';
import 'package:capman_host/features/session/ui/bloc/session_bloc.dart';
import 'package:capman_host/features/session/ui/bloc/session_state.dart';
import 'package:capman_host/features/session/ui/bloc/theme_mode_bloc.dart';
import 'package:capman_host/features/session/ui/login_route.dart';
import 'package:capman_host/generated/l10n.dart';
import 'package:capman_host/highlight_flows/highlight_cubit.dart';
import 'package:capman_host/highlight_flows/highlight_steps.dart';
import 'package:capman_host/highlight_flows/highlight_widget.dart';
import 'package:capman_host/logging/bloc_logger.dart';
import 'package:capman_host/logging/log_output.dart';
import 'package:capman_host/logging/toast_logger.dart';
import 'package:capman_host/shared_data/app_restart_tracker.dart';
import 'package:capman_host/shared_data/networking/proxy/http_override.dart';
import 'package:capman_host/shared_data/networking/services/analytics/toast_analytics_service.dart';
import 'package:capman_host/shared_data/services/cloud_sync_performance_tracker.dart';
import 'package:capman_host/shared_data/services/feature_flag_analytics_sync_service.dart';
import 'package:capman_host/shared_data/storage/preferences_storage.dart';
import 'package:capman_host/shared_data/tap_detection/tap_detection_service.dart';
import 'package:capman_host/shared_domain/model/app_info.dart';
import 'package:capman_host/shared_domain/model/app_version.dart';
import 'package:capman_host/shared_domain/repository/booking_manager.dart';
import 'package:capman_host/shared_domain/repository/booking_repository.dart';
import 'package:capman_host/shared_domain/repository/done_bookings_records_store.dart';
import 'package:capman_host/shared_domain/repository/guest_repository.dart';
import 'package:capman_host/shared_domain/repository/restaurant_tags_repository.dart';
import 'package:capman_host/shared_domain/repository/sms_repository.dart';
import 'package:capman_host/shared_domain/services/current_restaurant_service.dart';
import 'package:capman_host/shared_domain/services/device_data_service.dart';
import 'package:capman_host/shared_domain/services/error_logging_service.dart';
import 'package:capman_host/shared_domain/services/feature_flag_service.dart';
import 'package:capman_host/shared_domain/services/share_logs_service.dart';
import 'package:capman_host/shared_domain/services/token_storage.dart';
import 'package:capman_host/shared_domain/use_case/first_app_launch_use_case.dart';
import 'package:capman_host/shared_domain/util/phone_util.dart';
import 'package:capman_host/shared_ui/app_route_observer.dart';
import 'package:capman_host/shared_ui/bloc/app_config/app_config_state.dart';
import 'package:capman_host/shared_ui/bloc/app_config/device_settings_service.dart';
import 'package:capman_host/shared_ui/bloc/business_day/business_day_bloc.dart';
import 'package:capman_host/shared_ui/bloc/done_bookings/done_bookings_cubit.dart';
import 'package:capman_host/shared_ui/bloc/main/main_bloc.dart';
import 'package:capman_host/shared_ui/bloc/table_switcher_bloc/table_switcher_bloc.dart';
import 'package:capman_host/shared_ui/provider/guest_enrichment.dart';
import 'package:capman_host/shared_ui/provider/restaurant_context_provider.dart';
import 'package:capman_host/shared_ui/util/phone_type_check.dart';
import 'package:capman_host/shared_ui/util/snack_bar_util.dart';
import 'package:capman_host/toast_ui/toast_ui.dart';
import 'package:capman_host/utils/perf_reporting.dart';
import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logger/logger.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_info2/system_info2.dart';
import 'package:timezone/data/latest_all.dart';

// TEMPORARY WORKAROUND for iPad iOS 26 double-tap issue
// https://github.com/flutter/flutter/issues/175606#issuecomment-3576240885
// This filters out pointer events with zero offset that cause double-tap recognition
// on iPad when in immersive mode. Remove this when Flutter framework issue is fixed.
bool _zeroOffsetPointerGuardInstalled = false;

void _installZeroOffsetPointerGuard() {
  if (_zeroOffsetPointerGuardInstalled) return;
  GestureBinding.instance.pointerRouter.addGlobalRoute(_absorbZeroOffsetPointerEvent);
  _zeroOffsetPointerGuardInstalled = true;
}

void _absorbZeroOffsetPointerEvent(PointerEvent event) {
  if (event.position == Offset.zero) {
    GestureBinding.instance.cancelPointer(event.pointer);
  }
}

Future<void> run(Env environment) async {
  runZonedGuardedWidget(() async => runApp(await appWrapper(environment)));
}

Future<void> runZonedGuardedWidget(Future<void> Function() body) async {
  return runZonedGuarded<Future<void>>(
    body,
    (error, stack) {
      ToastLogger('entrypoint').i('error: $error, stack: $stack');
      _safeGetErrorLoggingService()?.logRunZonedGuarded(error, stack);
    },
  );
}

Future<Widget> appWrapper(final Env environment) async {
  if (kReleaseMode && environment == Env.PRODUCTION) Logger.level = Level.off;

  // This is a hack. some code uses S.current before MaterialApp is built and initializes S on its own. This is used in multiple error
  // handling flows in blocs/stores that get created before the app. This code prevents those usages from throwing, but they still won't be
  // localized to the non-default locale specified here after we start adding l10n support... we will need to either refactor off of
  // S.current or copy the default locale lookup from MaterialApp here.
  await S.load(
    const Locale.fromSubtags(languageCode: 'en'),
  );

  Bloc.observer = BlocLogger();
  if (environment == Env.TEST) {
    // Binding already initialized by IntegrationTestWidgetsFlutterBinding
  } else if (kDebugMode) {
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

  // TEMPORARY WORKAROUND: Install pointer guard to prevent iPad iOS 26 double-tap issue
  // See: https://github.com/flutter/flutter/issues/175606#issuecomment-3576240885
  _installZeroOffsetPointerGuard();

  // Enable proxy for non-production environments so that network traffic
  // can be captured and inspected for debugging / QA purposes.
  if (kReleaseMode && environment != Env.PRODUCTION && !kIsWeb) {
    final httpOverrides = await ProxiedHttpOverrides.fromSystemProxy();
    HttpOverrides.global = httpOverrides;
  }
  initializeTimeZones();
  await configureDependencies(environment);
  getIt<TapDetectionService>().installGlobalListener();
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    _safeGetErrorLoggingService()?.logFlutterFrameworkErrors(details);
    originalOnError?.call(details);
  };

  // [TogglableFileOutput] initialization must occur after `WidgetsFlutterBinding.ensureInitialized()`
  if (environment == Env.STAGING && !kDebugMode) {
    // Logs before this point will not be logged to files
    final result = await TogglableFileOutput.enable();
    ToastLogger(
      'entrypoint - DebugFileLogOutput',
    ).i('File logging enabled: $result');
  }

  await getIt<FirstAppLaunchUseCase>().execute();
  await initializeDateFormatting();

  if (!kIsWeb && !Platform.isWindows) {
    await PhoneUtil.initPhoneNumberPlugin();
  }
  final reporter = getIt<ToastAnalyticsService>();
  await reporter.initialize();
  if (!kIsWeb) {
    startReportingResourceUsages(
      reporter: reporter,
      battery: Battery(),
      availablePhysicalMemory: SysInfo.getAvailablePhysicalMemory,
    );
  }

  getIt<AppRestartTracker>().trackStartupAndListenForExit();
  getIt<CloudSyncPerformanceTracker>().startTracking();

  final appInfo = getIt<AppInfo>();
  await SentryFlutter.init((options) {
    options.dsn = 'https://05a80025d5fb4cb7807a6e54fd7f5f04@o37442.ingest.sentry.io/4503903690162176';
    options.environment = (environment == Env.STAGING || environment == Env.TEST) ? 'preproduction' : environment.name;
    options.release = appInfo.version.toString();
  });

  Logger.addLogListener((log) {
    if (log.level.value >= Level.error.value) {
      final Object? message = log.message;
      _safeGetErrorLoggingService()?.log(log.error ?? message ?? 'UNKNOWN', stackTrace: log.stackTrace);
    }
  });

  final platformOriginalOnError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (e, st) {
    _safeGetErrorLoggingService()?.logPlatformError(e, st);
    return platformOriginalOnError?.call(e, st) ?? false;
  };

  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  if (getIt<DeviceSettingsService>().getSize().shortestSide <= mobileWidth) {
    getIt<DeviceSettingsService>().setPortraitMode();
  } else {
    getIt<DeviceSettingsService>().setLandscapeMode();
  }
  final forceUpdateBloc = getIt<ForceUpdateBloc>();
  final bookingLimitBloc = getIt<BookingLimitBloc>();
  final estimateWaitTimeBloc = getIt<EstimateWaitTimeBloc>();
  final tableSwitcherBloc = getIt<TableSwitcherBloc>();
  final businessDayBloc = getIt<BusinessDayBloc>();
  final sessionBloc = getIt<SessionBloc>();
  final mainBloc = getIt<MainBloc>();
  final settingsBloc = SettingsBlocImpl(
    getIt<SharedPreferences>(),
    getIt<FeatureFlagService>(),
    getIt<DeviceSettingsService>(),
    getIt<ToastAnalyticsService>(),
    businessDayBloc,
  )..init();
  await sessionBloc.init();

  getIt<FeatureFlagAnalyticsSyncService>().startSyncing();

  return MultiBlocProvider(
    providers: [
      BlocProvider(create: (context) => sessionBloc),
      BlocProvider(create: (context) => tableSwitcherBloc),
      BlocProvider(create: (context) => forceUpdateBloc),
      BlocProvider(create: (context) => bookingLimitBloc),
      BlocProvider(create: (context) => estimateWaitTimeBloc),
      BlocProvider(create: (context) => businessDayBloc),
      BlocProvider(create: (context) => mainBloc),
      BlocProvider<SettingsBloc>(create: (context) => settingsBloc),
      BlocProvider<ThemeModeBloc>(
        create: (context) => ThemeModeBlocImpl(
          getIt<PreferencesStorage>(),
          settingsBloc,
          setUserProperty: getIt<ToastAnalyticsService>().setUserProperty,
          getPlatformBrightness: () => PlatformDispatcher.instance.platformBrightness,
        ),
      ),
      Provider.value(value: getIt<AppConfigState>()),
      Provider.value(value: getIt<FeatureFlagService>()),
      BlocProvider(
        create: (context) => DoneBookingCubit(
          getIt<DoneBookingRecordsStore>(),
          getIt<BookingRepository>(),
          getIt<CurrentRestaurantService>(),
          getIt<BookingManager>(),
        ),
      ),
      BlocProvider.value(value: getIt<TabBloc>()),
      BlocProvider(
        create: (context) => MessageBloc(
          getIt<SmsRepository>(),
          getIt<TabBloc>(),
          getIt<BookingManager>(),
        ),
      ),
      BlocProvider<HighlightCubit>(
        create: (_) => HighlightCubit(
          getIt<SharedPreferences>(),
          allFlows: [
            betaUpdatesFlow,
            redesignFlow,
            coverStatsFlow,
            timeBasedBlocksFlow,
            feedFlow,
            bookingAlertsButtonFlow,
            bookingAlertsPanelFlow,
            bookingAlertsSettingsFlow,
            combinedViewHomeFlow,
            combinedViewSettingsTileFlow,
            combinedViewConfigureFlow,
            combinedViewSettingsTutorialFlow,
          ],
          highlightsEnabled: environment != Env.TEST && environment != Env.DEMO,
        ),
      ),
      BlocProvider<DrawerBloc>(
        create: (context) => DrawerBloc(
          appInfo: appInfo,
          shareLogsService: getIt<ShareLogsService>(),
          currentRestaurantService: getIt<CurrentRestaurantService>(),
          deviceDataService: getIt<DeviceDataService>(),
          tokenStorage: getIt<TokenStorage>(),
          settingsBloc: context.read<SettingsBloc>(),
          errorLoggingService: getIt<ErrorLoggingService>(),
          tabBloc: getIt<TabBloc>(),
        ),
      ),
      BlocProvider<FeedBloc>(
        create: (context) => FeedBlocImpl(
          getIt<FeedService>(),
          getIt<SharedPreferences>(),
          getIt<CurrentRestaurantService>(),
        ),
        lazy: false, // eagerly load to fetch feed data sooner
      ),
    ],
    child: MultiProvider(
      providers: [
        Provider<BlocFactory>.value(value: const BlocFactory()),
        ChangeNotifierProvider(
          create: (context) => RestaurantContextProvider(
            getIt<CurrentRestaurantService>(),
          ),
        ),
      ],
      child: GuestEnrichmentProvider(
        tagsStream: getIt<RestaurantTagsRepository>().tagsStream,
        initialTags: getIt<RestaurantTagsRepository>().tags,
        enricher: (guest, tags) {
          if (guest == null) return null;
          return getIt<GuestRepository>().enrichGuest(guest, tags);
        },
        child: DevicePreview(
          enabled: kDebugMode,
          //the data field is actually not used so we need to use some fake storage to set the initial value
          storage: _PreviewStorage(),
          // not themed - rendered outside of the app and Theme widgets and only used for debugging
          backgroundColor: const Color(0xFF26272B), // ignore: custom_lints/avoid_hardcoded_colors
          builder: (context) => _App(navigatorKey: getIt<GlobalKey<NavigatorState>>()),
        ),
      ),
    ),
  );
}

class _PreviewStorage implements DevicePreviewStorage {
  @override
  Future<DevicePreviewData?> load() async {
    return const DevicePreviewData(
      isToolbarVisible: false,
      isEnabled: false,
    );
  }

  @override
  Future<void> save(DevicePreviewData data) => Future.value();
}

class _App extends StatelessWidget {
  const _App({required this.navigatorKey});
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    final isProduction = context.read<AppConfigState>().isProduction && kReleaseMode;

    return BlocListener<ForceUpdateBloc, ForceUpdateState>(
      listenWhen: (previous, current) => current is UpdateRecommended || current is UpdateRequired,
      listener: (context, state) => switch (state) {
        UpdateRecommended(:final data) => _showForceUpdateDialog(localVersion: data.localVersion),
        UpdateRequired(:final data) => _showForceUpdateDialog(localVersion: data.localVersion, updateRequired: true),
        _ => showErrorSnackBar(context, S.of(context).somethingWentWrong),
      },
      child: MediaQuery.withClampedTextScaling(
        // an arbitrary number that looks like it prevents overflows on small phones
        // - we could be smarter about this and apply looser numbers on larger devices
        maxScaleFactor: 1.25,
        child: HighlightScreen(
          navigatorKey: navigatorKey,
          child: MaterialApp(
            locale: DevicePreview.locale(context),
            builder: DevicePreview.appBuilder,
            navigatorKey: navigatorKey,
            theme: toastLightMode,
            darkTheme: toastDarkMode,
            themeMode: context.select((ThemeModeBloc bloc) => bloc.state),
            scrollBehavior: AllowPointerScrollForDesktopScrollBehavior(),
            navigatorObservers: [
              getIt<AppRouteObserver>(),
            ],
            onGenerateRoute: (settings) => switch (context.read<SessionBloc>().state) {
              LoggedOut() => LoginRoute(),
              LoggedIn() => LoginRoute(), // Logged in but no restaurant selected. Opens RestaurantSelectionDialog modal.
              RestaurantSelected() => MainRoute(),
            },
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: isProduction ? const [Locale('en')] : S.delegate.supportedLocales,
          ),
        ),
      ),
    );
  }

  void _showForceUpdateDialog({
    required AppVersion localVersion,
    bool updateRequired = false,
  }) {
    final appContext = navigatorKey.currentContext;
    if (appContext == null) return;
    showDialog<void>(
      context: appContext,
      barrierDismissible: false,
      builder: (BuildContext context) => ForceUpdateDialogContent(
        isUpdateRequired: updateRequired,
        localVersion: localVersion,
      ),
    );
  }
}

ErrorLoggingService? _safeGetErrorLoggingService() {
  // Defensive check
  // ErrorLoggingService may become unregistered (e.g. during test teardown)
  if (getIt.isRegistered<ErrorLoggingService>()) {
    return getIt<ErrorLoggingService>();
  }
  return null;
}

class AllowPointerScrollForDesktopScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    // In addition to the defaults - add the mouse for desktop support.
    // Without this the default scroll behavior disables many horizontal scroll actions
    // when using a mouse on desktop.
    // This could be an issue for scrollviews that have selectable text embedded in them - those can be handled as one-off cases if they
    // arise.
    PointerDeviceKind.mouse,
  };
}
