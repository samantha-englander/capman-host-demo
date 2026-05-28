import 'package:capman_host/shared_ui/bloc/app_config/app_config_state.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@LazySingleton()
class DemoMockInterceptor extends Interceptor {
  final bool _isDemo;

  // In demo environment isProduction=false and isStaging=false — that's the
  // sole condition. debugFeaturesEnabled is intentionally false for demo so
  // the debug menu doesn't surface, so we can't use it as a gate here.
  DemoMockInterceptor(AppConfigState config)
      : _isDemo = !config.isProduction && !config.isStaging;

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

  Map<String, dynamic> _restaurantDto() => {
        'restaurantGuid': 'demo-restaurant-guid-1234',
        'name': 'The Demo Kitchen',
        'managementGroupGuid': 'demo-group-guid',
        'restaurantSetGuid': null,
      };

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

  List<Map<String, dynamic>> _serviceAreaGroups() => [
        {
          'guid': 'group-main',
          'name': 'All Areas',
          'serviceAreas': ['area-dining', 'area-patio'],
          'enabled': true,
        },
      ];

  // ── Service Area Geometries ───────────────────────────────────────────────
  // Matches real floor plan: Dining Room (1–5, 11–15, 21–23, C1–C6, Counter)
  // and Patio (P1–P6).
  //
  // tables: List<TableServer> — full objects with name, guid, position, type
  //   (SQUARE / CIRCLE / DIAMOND), and capacity. Used by the app to render
  //   table entities and link to bookings.
  // shapes: List<ServiceAreaShapeServer> — structural elements only
  //   (BORDER = walls/outlines, LABEL = text). Tables are NOT included here.

  List<Map<String, dynamic>> _serviceAreaGeometries() => [
        {
          'guid': 'area-dining',
          'name': 'Dining Room',
          'tables': [
            // ── Row 1: Tables 1–5 ──
            _table('t-1',  name: '1',  top: 70,  left: 25,  w: 95,  h: 95,  type: 'SQUARE', minCap: 2, maxCap: 4),
            _table('t-2',  name: '2',  top: 70,  left: 155, w: 95,  h: 95,  type: 'SQUARE', minCap: 2, maxCap: 4),
            _table('t-3',  name: '3',  top: 70,  left: 285, w: 95,  h: 95,  type: 'SQUARE', minCap: 2, maxCap: 4),
            _table('t-4',  name: '4',  top: 70,  left: 415, w: 95,  h: 95,  type: 'SQUARE', minCap: 2, maxCap: 4),
            _table('t-5',  name: '5',  top: 70,  left: 540, w: 95,  h: 95,  type: 'SQUARE', minCap: 2, maxCap: 4),
            // ── Row 2: Tables 11–15 ──
            _table('t-11', name: '11', top: 205, left: 25,  w: 95,  h: 95,  type: 'SQUARE', minCap: 2, maxCap: 4),
            _table('t-12', name: '12', top: 205, left: 155, w: 95,  h: 95,  type: 'SQUARE', minCap: 2, maxCap: 4),
            _table('t-13', name: '13', top: 205, left: 285, w: 95,  h: 95,  type: 'SQUARE', minCap: 2, maxCap: 4),
            _table('t-14', name: '14', top: 205, left: 415, w: 95,  h: 95,  type: 'SQUARE', minCap: 2, maxCap: 4),
            _table('t-15', name: '15', top: 205, left: 540, w: 95,  h: 95,  type: 'SQUARE', minCap: 2, maxCap: 4),
            // ── Row 3: Tables 21–23 (large round) ──
            _table('t-21', name: '21', top: 360, left: 25,  w: 120, h: 120, type: 'CIRCLE', minCap: 4, maxCap: 8),
            _table('t-22', name: '22', top: 360, left: 180, w: 120, h: 120, type: 'CIRCLE', minCap: 4, maxCap: 8),
            _table('t-23', name: '23', top: 360, left: 540, w: 120, h: 120, type: 'CIRCLE', minCap: 4, maxCap: 8),
            // ── Counter seats C1–C6 ──
            _table('t-c1', name: 'C1', top: 70,  left: 745, w: 60,  h: 60,  type: 'CIRCLE', minCap: 1, maxCap: 2),
            _table('t-c2', name: 'C2', top: 160, left: 745, w: 60,  h: 60,  type: 'CIRCLE', minCap: 1, maxCap: 2),
            _table('t-c3', name: 'C3', top: 250, left: 745, w: 60,  h: 60,  type: 'CIRCLE', minCap: 1, maxCap: 2),
            _table('t-c4', name: 'C4', top: 365, left: 745, w: 60,  h: 60,  type: 'CIRCLE', minCap: 1, maxCap: 2),
            _table('t-c5', name: 'C5', top: 450, left: 745, w: 60,  h: 60,  type: 'CIRCLE', minCap: 1, maxCap: 2),
            _table('t-c6', name: 'C6', top: 535, left: 745, w: 60,  h: 60,  type: 'CIRCLE', minCap: 1, maxCap: 2),
          ],
          'shapes': [
            // ── Counter wall border ──
            _shape('border-counter', top: 55,  left: 828, w: 130, h: 545, type: 'BORDER'),
            // ── Counter label ──
            _shape('label-counter', label: 'Counter', top: 280, left: 835, w: 115, h: 30, type: 'LABEL'),
          ],
        },
        {
          'guid': 'area-patio',
          'name': 'Patio',
          'tables': [
            // ── Row 1: P1–P3 ──
            _table('t-p1', name: 'P1', top: 70,  left: 30,  w: 120, h: 120, type: 'SQUARE', minCap: 2, maxCap: 6),
            _table('t-p2', name: 'P2', top: 70,  left: 200, w: 120, h: 120, type: 'SQUARE', minCap: 2, maxCap: 6),
            _table('t-p3', name: 'P3', top: 70,  left: 370, w: 120, h: 120, type: 'SQUARE', minCap: 2, maxCap: 6),
            // ── Row 2: P4–P6 ──
            _table('t-p4', name: 'P4', top: 240, left: 30,  w: 120, h: 120, type: 'SQUARE', minCap: 2, maxCap: 6),
            _table('t-p5', name: 'P5', top: 240, left: 200, w: 120, h: 120, type: 'SQUARE', minCap: 2, maxCap: 6),
            _table('t-p6', name: 'P6', top: 240, left: 370, w: 120, h: 120, type: 'SQUARE', minCap: 2, maxCap: 6),
          ],
          'shapes': [],
        },
      ];

  Map<String, dynamic> _table(String guid, {required String name, required int top, required int left, required int w, required int h, required String type, required int minCap, required int maxCap}) =>
      {'guid': guid, 'name': name, 'top': top, 'left': left, 'width': w, 'height': h, 'type': type, 'minCapacity': minCap, 'maxCapacity': maxCap};

  Map<String, dynamic> _shape(String guid, {String? label, required int top, required int left, required int w, required int h, required String type}) =>
      {'guid': guid, 'label': label, 'top': top, 'left': left, 'width': w, 'height': h, 'type': type};

  // ── Bookings ──────────────────────────────────────────────────────────────

  static const _firstNames = [
    'Michael', 'Sarah', 'David', 'Jennifer', 'James', 'Lisa',
    'Robert', 'Emily', 'Daniel', 'Ashley', 'Matthew', 'Jessica',
    'Christopher', 'Amanda', 'Andrew', 'Stephanie', 'Joshua', 'Nicole',
    'Kevin', 'Hannah', 'Brian', 'Megan', 'Scott', 'Rachel',
  ];

  List<Map<String, dynamic>> _bookings() {
    final now = DateTime.now();

    // Seated guests — various tables, been here 5–60 min
    final seated = [
      _booking(guid: 'res-1',  bookingType: 'RESERVATION', bookingStatus: 'R_SEATED', partySize: 4, expectedStartTime: now.subtract(const Duration(minutes: 35)), tables: ['t-1'],  serviceAreas: ['area-dining'], guestLastName: 'Johnson',  guestIndex: 0,  createdAt: now.subtract(const Duration(hours: 2))),
      _booking(guid: 'res-2',  bookingType: 'RESERVATION', bookingStatus: 'R_SEATED', partySize: 2, expectedStartTime: now.subtract(const Duration(minutes: 20)), tables: ['t-2'],  serviceAreas: ['area-dining'], guestLastName: 'Smith',    guestIndex: 1,  createdAt: now.subtract(const Duration(hours: 3)), visitNotes: 'Birthday dinner'),
      _booking(guid: 'res-3',  bookingType: 'RESERVATION', bookingStatus: 'R_SEATED', partySize: 5, expectedStartTime: now.subtract(const Duration(minutes: 15)), tables: ['t-11'], serviceAreas: ['area-dining'], guestLastName: 'Williams', guestIndex: 2,  createdAt: now.subtract(const Duration(hours: 1))),
      _booking(guid: 'res-4',  bookingType: 'RESERVATION', bookingStatus: 'R_SEATED', partySize: 3, expectedStartTime: now.subtract(const Duration(minutes: 50)), tables: ['t-12'], serviceAreas: ['area-dining'], guestLastName: 'Brown',    guestIndex: 3,  createdAt: now.subtract(const Duration(hours: 4))),
      _booking(guid: 'res-5',  bookingType: 'RESERVATION', bookingStatus: 'R_SEATED', partySize: 4, expectedStartTime: now.subtract(const Duration(minutes: 10)), tables: ['t-13'], serviceAreas: ['area-dining'], guestLastName: 'Garcia',   guestIndex: 4,  createdAt: now.subtract(const Duration(hours: 1, minutes: 30))),
      _booking(guid: 'res-6',  bookingType: 'RESERVATION', bookingStatus: 'R_SEATED', partySize: 6, expectedStartTime: now.subtract(const Duration(minutes: 45)), tables: ['t-21'], serviceAreas: ['area-dining'], guestLastName: 'Martinez', guestIndex: 5,  createdAt: now.subtract(const Duration(hours: 5)), visitNotes: 'Anniversary'),
      _booking(guid: 'res-7',  bookingType: 'RESERVATION', bookingStatus: 'R_SEATED', partySize: 2, expectedStartTime: now.subtract(const Duration(minutes: 5)),  tables: ['t-22'], serviceAreas: ['area-dining'], guestLastName: 'Davis',    guestIndex: 6,  createdAt: now.subtract(const Duration(hours: 2))),
      _booking(guid: 'res-8',  bookingType: 'RESERVATION', bookingStatus: 'R_SEATED', partySize: 3, expectedStartTime: now.subtract(const Duration(minutes: 25)), tables: ['t-p1'], serviceAreas: ['area-patio'],  guestLastName: 'Wilson',   guestIndex: 7,  createdAt: now.subtract(const Duration(hours: 1))),
      _booking(guid: 'res-9',  bookingType: 'RESERVATION', bookingStatus: 'R_SEATED', partySize: 4, expectedStartTime: now.subtract(const Duration(minutes: 30)), tables: ['t-p2'], serviceAreas: ['area-patio'],  guestLastName: 'Anderson', guestIndex: 8,  createdAt: now.subtract(const Duration(hours: 2))),
    ];

    // Upcoming — mix of R_ARRIVED (on-site, awaiting table) and R_CONFIRMED
    // Some have pre-assigned tables (host has already assigned them a spot)
    final upcoming = [
      _booking(guid: 'res-10', bookingType: 'RESERVATION', bookingStatus: 'R_ARRIVED',   partySize: 4, expectedStartTime: now.add(const Duration(minutes: 10)),  tables: ['t-3'],  serviceAreas: ['area-dining'], guestLastName: 'Taylor',   guestIndex: 9,  createdAt: now.subtract(const Duration(days: 1)),  arrivedTime: now.subtract(const Duration(minutes: 3))),
      _booking(guid: 'res-11', bookingType: 'RESERVATION', bookingStatus: 'R_ARRIVED',   partySize: 2, expectedStartTime: now.add(const Duration(minutes: 20)),  tables: [],       serviceAreas: [],              guestLastName: 'Thomas',   guestIndex: 10, createdAt: now.subtract(const Duration(days: 2)),  arrivedTime: now.subtract(const Duration(minutes: 6))),
      _booking(guid: 'res-12', bookingType: 'RESERVATION', bookingStatus: 'R_ARRIVED',   partySize: 3, expectedStartTime: now.add(const Duration(minutes: 25)),  tables: ['t-4'],  serviceAreas: ['area-dining'], guestLastName: 'Jackson',  guestIndex: 11, createdAt: now.subtract(const Duration(hours: 6)),  arrivedTime: now.subtract(const Duration(minutes: 1))),
      _booking(guid: 'res-13', bookingType: 'RESERVATION', bookingStatus: 'R_CONFIRMED', partySize: 3, expectedStartTime: now.add(const Duration(minutes: 35)),  tables: [],       serviceAreas: [],              guestLastName: 'White',    guestIndex: 12, createdAt: now.subtract(const Duration(days: 3))),
      _booking(guid: 'res-14', bookingType: 'RESERVATION', bookingStatus: 'R_CONFIRMED', partySize: 6, expectedStartTime: now.add(const Duration(minutes: 45)),  tables: ['t-23'], serviceAreas: ['area-dining'], guestLastName: 'Harris',   guestIndex: 13, createdAt: now.subtract(const Duration(days: 1))),
      _booking(guid: 'res-15', bookingType: 'RESERVATION', bookingStatus: 'R_CONFIRMED', partySize: 2, expectedStartTime: now.add(const Duration(minutes: 60)),  tables: [],       serviceAreas: [],              guestLastName: 'Lewis',    guestIndex: 14, createdAt: now.subtract(const Duration(days: 4))),
      _booking(guid: 'res-16', bookingType: 'RESERVATION', bookingStatus: 'R_CONFIRMED', partySize: 4, expectedStartTime: now.add(const Duration(minutes: 75)),  tables: [],       serviceAreas: [],              guestLastName: 'Robinson', guestIndex: 15, createdAt: now.subtract(const Duration(days: 2))),
      _booking(guid: 'res-17', bookingType: 'RESERVATION', bookingStatus: 'R_CONFIRMED', partySize: 4, expectedStartTime: now.add(const Duration(minutes: 90)),  tables: [],       serviceAreas: [],              guestLastName: 'Clark',    guestIndex: 16, createdAt: now.subtract(const Duration(days: 1))),
    ];

    // Waitlist
    final waitlist = [
      _booking(guid: 'wait-1', bookingType: 'WAITLIST', bookingStatus: 'W_WAITING', partySize: 3, expectedStartTime: now.add(const Duration(minutes: 15)), tables: [], serviceAreas: [], guestLastName: 'Rodriguez', guestIndex: 17, createdAt: now.subtract(const Duration(minutes: 12))),
      _booking(guid: 'wait-2', bookingType: 'WAITLIST', bookingStatus: 'W_WAITING', partySize: 2, expectedStartTime: now.add(const Duration(minutes: 25)), tables: [], serviceAreas: [], guestLastName: 'Lee',       guestIndex: 18, createdAt: now.subtract(const Duration(minutes: 8))),
      _booking(guid: 'wait-3', bookingType: 'WAITLIST', bookingStatus: 'W_WAITING', partySize: 4, expectedStartTime: now.add(const Duration(minutes: 35)), tables: [], serviceAreas: [], guestLastName: 'Walker',    guestIndex: 19, createdAt: now.subtract(const Duration(minutes: 5))),
      _booking(guid: 'wait-4', bookingType: 'WAITLIST', bookingStatus: 'W_WAITING', partySize: 2, expectedStartTime: now.add(const Duration(minutes: 40)), tables: [], serviceAreas: [], guestLastName: 'Hall',      guestIndex: 20, createdAt: now.subtract(const Duration(minutes: 3))),
      _booking(guid: 'wait-5', bookingType: 'WAITLIST', bookingStatus: 'W_WAITING', partySize: 5, expectedStartTime: now.add(const Duration(minutes: 50)), tables: [], serviceAreas: [], guestLastName: 'Allen',     guestIndex: 21, createdAt: now.subtract(const Duration(minutes: 1))),
    ];

    return [...seated, ...upcoming, ...waitlist];
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
    DateTime? arrivedTime,
  }) {
    final firstName = guestIndex < _firstNames.length ? _firstNames[guestIndex] : '';
    return {
      'guid': guid,
      'bookingType': bookingType,
      'bookingStatus': bookingStatus,
      'partySize': partySize,
      'expectedStartTime': expectedStartTime.toIso8601String(),
      'expectedEndTime': expectedStartTime.add(const Duration(minutes: 90)).toIso8601String(),
      'actualStartTime': bookingStatus == 'R_SEATED' ? expectedStartTime.toIso8601String() : null,
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
      'arrivedTime': arrivedTime?.toIso8601String(),
      'toastPayEnabled': null,
      'paymentMandateId': null,
      'guest': {
        'guid': 'guest-$guestIndex',
        'firstName': firstName,
        'lastName': guestLastName,
        'phone': '617-555-0${guestIndex.toString().padLeft(3, '0')}',
        'email': null,
      },
      'createdDate': createdAt.toIso8601String(),
      'modifiedDate': createdAt.toIso8601String(),
    };
  }
}
