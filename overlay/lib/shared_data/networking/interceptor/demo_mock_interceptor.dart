import 'package:capman_host/shared_ui/bloc/app_config/app_config_state.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

// Registered for ALL environments (no @demo tag) so it can be injected into
// dev+demo Dio clients. Only intercepts when isDemo is true (release build
// with debugFeaturesEnabled=true, non-prod, non-staging).
@LazySingleton()
class DemoMockInterceptor extends Interceptor {
  final bool _isDemo;

  DemoMockInterceptor(AppConfigState config)
      : _isDemo = config.debugFeaturesEnabled &&
            !config.isProduction &&
            !config.isStaging;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!_isDemo) {
      handler.next(options);
      return;
    }
    final method = options.method.toUpperCase();
    final path = options.uri.path;
    // ignore: avoid_print
    print('[DEMO] $method $path');
    handler.resolve(Response(
      requestOptions: options,
      data: _respond(method, path),
      statusCode: 200,
      statusMessage: 'OK',
    ));
  }

  dynamic _respond(String method, String path) {
    // Auth
    if (path.contains('oauth/token')) return _authToken();
    // devices/tables must come before generic device check — returns AuthToken shape
    if (method == 'POST' && path.contains('devices/tables')) return _deviceAuthToken();
    if (path.contains('device')) return _deviceInfo();

    // Restaurant selection — ALL use parseJsonList → {"results": [...]}
    if (method == 'GET' && path.contains('restaurantAccess')) return {'results': [_restaurantDto()]};
    if (method == 'GET' && path.endsWith('/app/restaurant')) return {'results': [_restaurantInfo()]};

    // Management group
    if (path.contains('managementGroup')) return {'managementGroups': [_managementGroup()]};

    // Floor plan — parseJsonList → {"results": [...]}
    if (method == 'GET' && path.contains('serviceAreaGroups')) return {'results': _serviceAreaGroups()};
    if (method == 'GET' && path.contains('serviceAreas')) return {'results': _serviceAreaGeometries()};

    // Bookings — parseJsonList → {"results": [...]}
    if (method == 'GET' && path.endsWith('/bookings')) return {'results': _bookings()};
    if (method == 'POST' && path.contains('/booking/')) return {'results': <dynamic>[]};
    if (method == 'PATCH' && path.contains('/booking/')) return {'results': <dynamic>[]};
    if (method == 'DELETE' && path.contains('/booking/')) return {'results': <dynamic>[]};

    // Roster — parseJsonList → {"results": [...]}
    if (method == 'GET' && path.contains('serverAssignment')) return {'results': <dynamic>[]};
    if (method == 'GET' && path.contains('shiftCutoff')) return {'results': <dynamic>[]};
    if (method == 'GET' && path.contains('employee/list')) return {'results': <dynamic>[]};

    // Other endpoints
    if (path.contains('smsThread') || path.contains('experience')) return <dynamic>[];
    if (path.contains('appConfig')) return {'features': <String, dynamic>{}};
    if (method == 'POST' && path.contains('cloudSync')) return {'bookings': <dynamic>[]};

    return <String, dynamic>{};
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _authToken() => {
        'access_token': 'demo-access-token',
        'refresh_token': 'demo-refresh-token',
        'token_type': 'Bearer',
        'expires_in': 86400,
      };

  // AuthToken uses json_serializable default (camelCase keys)
  Map<String, dynamic> _deviceAuthToken() => {
        'accessToken': 'demo-device-access-token',
        'refreshToken': 'demo-device-refresh-token',
      };

  // ── Device ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _deviceInfo() => {
        'guid': 'demo-device-guid',
        'deviceGuid': 'demo-device-guid',
        'token': 'demo-device-token',
        'apiToken': 'demo-device-token',
        'status': 'ACTIVE',
      };

  // ── Management Group ──────────────────────────────────────────────────────

  Map<String, dynamic> _managementGroup() => {
        'guid': 'demo-group-guid',
        'managementGroupGuid': 'demo-group-guid',
        'name': 'Demo Group',
      };

  // ── Restaurant ────────────────────────────────────────────────────────────
  // RestaurantDto fields: restaurantGuid, name, managementGroupGuid?, restaurantSetGuid?

  Map<String, dynamic> _restaurantDto() => {
        'restaurantGuid': 'demo-restaurant-guid-1234',
        'name': 'The Demo Kitchen',
        'managementGroupGuid': 'demo-group-guid',
        'restaurantSetGuid': null,
      };

  // ── Restaurant Info ───────────────────────────────────────────────────────
  // RestaurantInfoDto fields (all required non-null shown explicitly)

  Map<String, dynamic> _restaurantInfo() => {
        'timezone': 'America/New_York',
        'reservationsEnabled': true,
        'waitlistEnabled': true,
        'closeOutHour': null,
        'twoWaySmsEnabled': false,
        'orderCreationEnabled': false,
        'waitlistNotifySmsEnabled': false,
        'reservationNotifySmsEnabled': false,
        'locale': null,
      };

  // ── Service Area Groups ───────────────────────────────────────────────────
  // ServiceAreaGroup: name, guid, serviceAreas (List<String>), enabled

  List<Map<String, dynamic>> _serviceAreaGroups() => [
        {
          'guid': 'group-main',
          'name': 'All Areas',
          'serviceAreas': ['area-main', 'area-bar', 'area-patio'],
          'enabled': true,
        },
      ];

  // ── Service Area Geometries ───────────────────────────────────────────────
  // ServiceAreaGeometryServer: name?, guid, tables (List<String> GUIDs), shapes

  List<Map<String, dynamic>> _serviceAreaGeometries() => [
        {
          'guid': 'area-main',
          'name': 'Main Dining',
          'tables': List.generate(10, (i) => 'table-main-${i + 1}'),
          'shapes': <dynamic>[],
        },
        {
          'guid': 'area-bar',
          'name': 'Bar',
          'tables': List.generate(4, (i) => 'table-bar-${i + 1}'),
          'shapes': <dynamic>[],
        },
        {
          'guid': 'area-patio',
          'name': 'Patio',
          'tables': List.generate(6, (i) => 'table-patio-${i + 1}'),
          'shapes': <dynamic>[],
        },
      ];

  // ── Bookings ──────────────────────────────────────────────────────────────
  // BookingDto uses bookingType, bookingStatus (R_SEATED/R_CONFIRMED/W_WAITING),
  // expectedStartTime/expectedEndTime, tables (GUIDs), serviceAreas (GUIDs), etc.

  List<Map<String, dynamic>> _bookings() {
    final now = DateTime.now();
    final lastNames = ['Johnson', 'Smith', 'Williams', 'Brown', 'Garcia', 'Martinez', 'Davis', 'Wilson', 'Anderson', 'Taylor'];
    final partySizes = [4, 2, 3, 6, 2, 4, 3, 2, 5, 3];

    final reservations = List.generate(6, (i) {
      final isSeated = i < 2;
      final start = isSeated
          ? now.subtract(Duration(minutes: 15 + i * 10))
          : now.add(Duration(minutes: i * 15));
      return _booking(
        guid: 'res-${i + 1}',
        bookingType: 'RESERVATION',
        bookingStatus: isSeated ? 'R_SEATED' : 'R_CONFIRMED',
        partySize: partySizes[i],
        expectedStartTime: start,
        tables: isSeated ? ['table-main-${i + 1}'] : [],
        serviceAreas: isSeated ? ['area-main'] : [],
        visitNotes: i == 1 ? 'Anniversary dinner' : null,
        guestLastName: lastNames[i],
        guestIndex: i,
        createdAt: now.subtract(Duration(minutes: 60 + i * 30)),
      );
    });

    final waitlist = List.generate(4, (i) {
      return _booking(
        guid: 'wait-${i + 1}',
        bookingType: 'WAITLIST',
        bookingStatus: 'W_WAITING',
        partySize: partySizes[i + 6],
        expectedStartTime: now.add(Duration(minutes: (i + 1) * 10)),
        tables: [],
        serviceAreas: [],
        guestLastName: lastNames[i + 6],
        guestIndex: i + 6,
        createdAt: now.subtract(Duration(minutes: 5 + i * 8)),
      );
    });

    return [...reservations, ...waitlist];
  }

  Map<String, dynamic> _booking({
    required String guid,
    required String bookingType,
    required String bookingStatus,
    required int partySize,
    required DateTime expectedStartTime,
    required List<String> tables,
    required List<String> serviceAreas,
    required String guestLastName,
    required int guestIndex,
    required DateTime createdAt,
    String? visitNotes,
  }) =>
      {
        'guid': guid,
        'bookingType': bookingType,
        'bookingStatus': bookingStatus,
        'partySize': partySize,
        'expectedStartTime': expectedStartTime.toIso8601String(),
        'expectedEndTime': expectedStartTime.add(const Duration(minutes: 90)).toIso8601String(),
        'actualStartTime': tables.isNotEmpty ? expectedStartTime.toIso8601String() : null,
        'actualEndTime': null,
        'tables': tables,
        'serviceAreas': serviceAreas,
        'serviceAreaGroup': null,
        'requestedServiceAreaGroups': <String>[],
        'server': null,
        'firstNotified': null,
        'lastNotified': null,
        'notificationCount': 0,
        'cancelledTime': null,
        'dismissToHistory': false,
        'cancellationSource': null,
        'depositOrderId': null,
        'paymentStatus': null,
        'depositPaymentExpirationDatetime': null,
        'depositRefundableCancellationDatetime': null,
        'depositAmount': null,
        'visitNotes': visitNotes,
        'bookingNotes': null,
        'bookingSource': null,
        'bookableId': null,
        'requestedTable': <String>[],
        'paymentConfigType': null,
        'paymentConfigSnapshot': null,
        'arrivedTime': null,
        'toastPayEnabled': null,
        'paymentMandateId': null,
        'guest': {
          'guid': 'guest-$guestIndex',
          'firstName': '',
          'lastName': guestLastName,
          'phone': '617-555-0${guestIndex.toString().padLeft(3, '0')}',
          'email': null,
        },
        'createdDate': createdAt.toIso8601String(),
        'modifiedDate': createdAt.toIso8601String(),
      };
}
