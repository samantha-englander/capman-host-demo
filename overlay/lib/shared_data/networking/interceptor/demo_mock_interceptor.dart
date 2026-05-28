import 'package:capman_host/shared_ui/bloc/app_config/app_config_state.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@LazySingleton()
class DemoMockInterceptor extends Interceptor {
  final bool _isDemo;

  // Session-scoped state: overrides applied via mutating endpoints.
  // The interceptor is a @LazySingleton so these maps survive across requests
  // but reset when the page reloads — which is exactly what we want
  // (changes "stick" mid-demo, fresh state on every page load).
  final Map<String, String> _statusOverrides = {};        // booking guid → status
  final Map<String, DateTime> _notifyTimes = {};          // booking guid → firstNotified
  final Map<String, String> _tableStateOverrides = {};    // table guid → state

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

    // Side-effects: capture state mutations from PATCH/POST endpoints into
    // the override maps so subsequent GETs reflect the change.
    if (method == 'PATCH' && path.contains('/booking/')) {
      _captureStatusOverride(path, options.data);
    }
    if (method == 'POST' && path.endsWith('/booking/notify')) {
      _captureNotify(options.data);
    }
    if (method == 'PATCH' && (path.contains('/table/dirty') || path.contains('/table/makeAvailable'))) {
      _captureTableState(path, options.data);
    }

    handler.resolve(Response(
      requestOptions: options,
      data: _respond(method, path),
      statusCode: 200,
      statusMessage: 'OK',
    ));
  }

  /// Inspect a booking-mutating PATCH and, if it represents a status change,
  /// store the new wire-format status in [_statusOverrides] keyed by guid.
  /// Endpoints + body schema verified from BookingServiceApi source.
  void _captureStatusOverride(String path, dynamic body) {
    final afterBooking = path.split('/booking/').last;
    final guid = afterBooking.split('/').first;
    if (guid.isEmpty) return;
    // Waitlist bookings use the W_ wire prefix; reservations use R_.
    final isWaitlist = guid.startsWith('wait-');
    String r(String suffix) => isWaitlist ? 'W_$suffix' : 'R_$suffix';

    String? newStatus;
    if (path.endsWith('/statusV2')) {
      // UpdateBookingStatusBody = { bookingStatus: '<wire-format>' }
      if (body is Map && body['bookingStatus'] is String) {
        newStatus = body['bookingStatus'] as String;
      }
    } else if (path.endsWith('/confirmV2')) {
      newStatus = r('CONFIRMED');
    } else if (path.endsWith('/noShowV2')) {
      newStatus = r('NO_SHOW');
    } else if (path.endsWith('/seatV2')) {
      newStatus = r('SEATED');
    } else if (path.endsWith('/unseatV2')) {
      newStatus = r('CONFIRMED');
    } else if (path.endsWith('/leftBuilding') || path.endsWith('/doneV2')) {
      newStatus = r('DONE');
    } else if (path.endsWith('/cancel')) {
      newStatus = r('CANCELLED');
    }

    if (newStatus != null) {
      _statusOverrides[guid] = newStatus;
    }
  }

  /// Notify body schema verified from BookingNotifyRequestBody: contains
  /// bookingGuid, restaurantGuid, guestGuid. Mark the booking NOTIFIED and
  /// stamp firstNotified so the app's in-row countdown timer activates.
  void _captureNotify(dynamic body) {
    if (body is! Map) return;
    final guid = body['bookingGuid'];
    if (guid is! String || guid.isEmpty) return;
    final isWaitlist = guid.startsWith('wait-');
    _statusOverrides[guid] = isWaitlist ? 'W_NOTIFIED' : 'R_NOTIFIED';
    _notifyTimes[guid] = DateTime.now();
  }

  /// Table state body is typically {tableGuids: [...]}. /dirty marks tables
  /// DIRTY; /makeAvailable marks them AVAILABLE. Apply override so the next
  /// /tableStates poll reflects the change on the floor plan.
  void _captureTableState(String path, dynamic body) {
    if (body is! Map) return;
    final raw = body['tableGuids'];
    if (raw is! List) return;
    final newState = path.contains('/dirty') ? 'DIRTY' : 'AVAILABLE';
    for (final t in raw) {
      if (t is String && t.isNotEmpty) {
        _tableStateOverrides[t] = newState;
      }
    }
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
    // /tables must come before /serviceAreas to avoid the contains() overlap
    if (method == 'GET' && path.contains('serviceAreaGroups')) return {'results': _serviceAreaGroups()};
    if (method == 'GET' && path.contains('serviceAreas')) return {'results': _serviceAreaGeometries()};
    if (method == 'GET' && path.contains('tableStates')) return {'results': _tableStates()};
    if (method == 'GET' && (path.endsWith('/tables') || path.contains('/app/tables'))) return {'results': _allTables()};

    // Bookings — parseJsonList → {"results": [...]}
    if (method == 'GET' && path.endsWith('/bookings')) return {'results': _bookings()};
    if (method == 'POST' && path.contains('/booking/')) return {'results': <dynamic>[]};
    if (method == 'PATCH' && path.contains('/booking/')) {
      final guid = path.split('/booking/').last.split('/').first;
      final all = _bookings();
      Map<String, dynamic>? found;
      for (final b in all) {
        if ((b['guid'] as String?) == guid) { found = b; break; }
      }
      // Seat-action endpoints (seatV2, unseatV2, moveV2, serverV2) parse the
      // response as List<SeatActionDto>, NOT List<BookingDto>. SeatActionDto
      // shape: {order: OrderDto?, booking: BookingDto}. Wrap accordingly so
      // floor-plan drag-and-drop, "Seat Party", "Move Table", and "Change
      // Server" actions don't throw "Something went wrong."
      final isSeatAction = path.endsWith('/seatV2')
          || path.endsWith('/unseatV2')
          || path.endsWith('/moveV2')
          || path.endsWith('/serverV2');
      if (isSeatAction) {
        return {
          'results': found != null
              ? [{'order': null, 'booking': found}]
              : <dynamic>[],
        };
      }
      // All other booking PATCHes (statusV2, confirmV2, noShowV2, cancel,
      // reservation, waitlist, leftBuilding) parse as List<BookingDto>.
      return {'results': found != null ? [found] : <dynamic>[]};
    }
    if (method == 'DELETE' && path.contains('/booking/')) return {'results': <dynamic>[]};

    // POST /booking/notify returns List<BookingDto> (the updated booking with
    // status flipped to W_NOTIFIED / R_NOTIFIED and firstNotified stamped).
    // _captureNotify already wired the override; just look up the booking.
    if (method == 'POST' && path.endsWith('/booking/notify')) {
      Map<String, dynamic>? found;
      final body = null; // body already captured; just return updated record
      // ignore: unused_local_variable
      final _ = body;
      // Find whichever booking was just notified (the most recent in the map).
      if (_notifyTimes.isNotEmpty) {
        final lastGuid = _notifyTimes.entries.last.key;
        for (final b in _bookings()) {
          if (b['guid'] == lastGuid) { found = b; break; }
        }
      }
      return {'results': found != null ? [found] : <dynamic>[]};
    }

    // PATCH /table/dirty and /table/makeAvailable return List<TableStateDto>.
    // _captureTableState already wrote the override; rebuild the full list.
    if (method == 'PATCH' && (path.contains('/table/dirty') || path.contains('/table/makeAvailable'))) {
      return {'results': _tableStates()};
    }

    // Blocks / orders / other booking endpoints that crash parseJsonList when unhandled
    if (method == 'GET' && path.contains('/app/blocks')) return {'results': <dynamic>[]};
    if (method == 'GET' && path.contains('/app/orders')) return {'results': <dynamic>[]};
    // Order completion / linking — parsed as List<OrderDto>. Empty results is safe.
    if (method == 'PATCH' && path.contains('/orders/')) return {'results': <dynamic>[]};

    // Create-reservation flow.
    //
    // availabilitiesV2: parseJsonList<TimeSlotAvailability>
    //   TimeSlotAvailability = {slots, bookableAvailabilityInfo, reservationsDisabled}
    //   Empty slots = "no time slots" UI in the picker but no crash.
    if (method == 'GET' && path.contains('availabilitiesV2')) return {
          'results': [
            {
              'slots': <dynamic>[],
              'bookableAvailabilityInfo': <dynamic>[],
              'reservationsDisabled': false,
            },
          ],
        };
    // configInfo: parseJson<ScheduleInfoDto> = {message, results: [ScheduleGroupDto]}
    // Empty results = no schedule but no crash. Was returning a flat object
    // with wrong field names, causing "Something went wrong" on the
    // Create New Reservation screen.
    if (method == 'GET' && path.contains('configInfo')) return {
          'message': null,
          'results': <dynamic>[],
        };
    // Waitlist wait-time estimate — parsed via parseJsonList<WaitInfoDto>,
    // so the response MUST be a {results: [...]} envelope. Was returning a
    // bare object, which crashed the "Add to waitlist" preview.
    if (path.contains('previewEstimate')) return {
          'results': [
            {
              'estimatedWaitMinutes': 15,
              'minWaitMinutes': 10,
              'maxWaitMinutes': 25,
              'partySize': 2,
            },
          ],
        };

    // Ticketed events — parsed via parseRawJsonList (raw array, no envelope).
    if (method == 'GET' && path.contains('event-showings')) return <dynamic>[];

    // Roster — parseJsonList → {"results": [...]}
    if (method == 'GET' && path.contains('serverAssignment')) return {'results': _serverAssignments()};
    // POST /roster/replace — RosterReplaceResponse shape verified from source:
    // { employees: [EmployeeDto...], serverAssignments: [ServerAssignmentDto...] }
    // Returning empty {} causes a `Bad state: No element` crash and the save
    // button hangs in "in progress" forever.
    if (method == 'POST' && path.contains('roster/replace')) return {
          'employees': _employees(),
          'serverAssignments': _serverAssignments(),
        };
    if (method == 'GET' && path.contains('shiftCutoff')) return {'results': <dynamic>[]};
    // listColors must match BEFORE the generic 'employee' branch, otherwise
    // the server-color picker tries to parse employees as ServerColorNetworking.
    if (method == 'GET' && path.contains('listColors')) return {'results': <dynamic>[]};
    if (method == 'GET' && path.contains('employee')) return {'results': _employees()};
    // Manager passcode auth: POST /booking/v2/app/employee with passcode.
    // Returns List<EmployeeDto> — accept any passcode by returning the
    // first on-roster employee so override prompts complete.
    if (method == 'POST' && path.contains('employee')) return {'results': [_employees().first]};
    // Server-rotation / table-assignment feature: section, coverage, rotation endpoints
    if (method == 'GET' && path.contains('section')) return {'results': <dynamic>[]};
    if (method == 'GET' && path.contains('coverage')) return {'results': <dynamic>[]};
    if (method == 'GET' && path.contains('rotation')) return {'results': <dynamic>[]};
    if (method == 'POST' && path.contains('section')) return {'results': <dynamic>[]};
    if (method == 'POST' && path.contains('rotation')) return {'results': <dynamic>[]};

    // Guest tags (needed for tag icons in reservation list)
    if (method == 'GET' && path.contains('guestTags')) return {'results': _guestTags()};

    // Guest search — the "Add Reservation" flow searches guests by name or
    // phone via querySearch / guestSearch endpoints. Without explicit matches
    // these fall through to the empty fallback, so the guest picker shows
    // "no results" no matter what. Return the full guestbook so any query
    // surfaces matches (the app does its own client-side filtering).
    if (method == 'GET' && (path.contains('querySearch') || path.contains('guestSearch'))) {
      return {'results': _guests()};
    }
    // Guestbook
    if (method == 'GET' && path.contains('/guests')) return {'results': _guests()};

    // SMS threads — must return {"results":[]} not a raw list (fixes TypeError on floor plan load)
    if (path.contains('smsThread')) return {'results': <dynamic>[]};
    // Waitlist/reservation notify — succeed silently so UI completes the flow
    if (path.contains('notify')) return {'results': <dynamic>[]};
    // experiences: parseJson<ExperienceInfoDto> = {message, results: [[ExperienceDto]]}
    // Single object, NOT a raw list. We used to return [] which would parse-error.
    if (path.contains('experience')) return {'message': null, 'results': <dynamic>[]};
    if (path.contains('appConfig')) return {'features': <String, dynamic>{}};
    if (method == 'POST' && path.contains('cloudSync')) return {'bookings': <dynamic>[]};

    // Safe fallthrough: GET endpoints always return an empty results envelope so
    // parseJsonList never crashes on unhandled paths. Mutations (POST/PATCH/DELETE)
    // return an empty map — the app rarely parses mutation responses strictly.
    if (method == 'GET') return {'results': <dynamic>[]};
    return <String, dynamic>{};
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _authToken() => {
        'access_token': 'demo-access-token',
        'refresh_token': 'demo-refresh-token',
        'token_type': 'Bearer',
        'expires_in': 86400,
      };

  Map<String, dynamic> _deviceAuthToken() => {
        'accessToken': 'demo-device-access-token',
        'refreshToken': 'demo-device-refresh-token',
      };

  // ── Device ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _deviceInfo() => {
        // Numeric — Toast BigInt-parses device/management/restaurant guids.
        'guid': '9000000000000001',
        'deviceGuid': '9000000000000001',
        'token': 'demo-device-token',
        'apiToken': 'demo-device-token',
        'status': 'ACTIVE',
      };

  // ── Management Group ──────────────────────────────────────────────────────

  Map<String, dynamic> _managementGroup() => {
        'guid': '8000000000000001',
        'managementGroupGuid': '8000000000000001',
        'name': 'Demo Group',
      };

  // ── Restaurant ────────────────────────────────────────────────────────────

  Map<String, dynamic> _restaurantDto() => {
        'restaurantGuid': '7000000000000001',
        'name': 'The Demo Kitchen',
        'managementGroupGuid': '8000000000000001',
        'restaurantSetGuid': null,
      };

  Map<String, dynamic> _restaurantInfo() => {
        'timezone': 'America/New_York',
        'reservationsEnabled': true,
        'waitlistEnabled': true,
        'closeOutHour': null,
        'twoWaySmsEnabled': false,
        'orderCreationEnabled': false,
        'waitlistNotifySmsEnabled': true,
        'reservationNotifySmsEnabled': true,
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

  List<Map<String, dynamic>> _serviceAreaGeometries() => [
        {
          'guid': 'area-dining',
          'name': 'Dining Room',
          // ServiceAreaGeometry.tables is List<String> guids — full objects go to GET /tables
          'tables': ['t-1','t-2','t-3','t-4','t-5','t-11','t-12','t-13','t-14','t-15','t-21','t-22','t-23','t-c1','t-c2','t-c3','t-c4','t-c5','t-c6'],
          'shapes': [
            _shape('border-counter', top: 55,  left: 828, w: 130, h: 545, type: 'BORDER'),
            _shape('label-counter', label: 'Counter', top: 280, left: 835, w: 115, h: 30, type: 'LABEL'),
          ],
        },
        {
          'guid': 'area-patio',
          'name': 'Patio',
          'tables': ['t-p1','t-p2','t-p3','t-p4','t-p5','t-p6'],
          'shapes': [],
        },
      ];

  Map<String, dynamic> _table(String guid, {required String name, required int top, required int left, required int w, required int h, required String type, required int minCap, required int maxCap}) =>
      {'guid': guid, 'name': name, 'top': top, 'left': left, 'width': w, 'height': h, 'type': type, 'minCapacity': minCap, 'maxCapacity': maxCap};

  Map<String, dynamic> _shape(String guid, {String? label, required int top, required int left, required int w, required int h, required String type}) =>
      {'guid': guid, 'label': label, 'top': top, 'left': left, 'width': w, 'height': h, 'type': type};

  // ── Bookings ──────────────────────────────────────────────────────────────
  // All times are relative to DateTime.now() so the demo always feels mid-service.
  // Upcoming reservation times are rounded up to the next quarter-hour so they
  // never show oddities like "11:53 PM".

  /// Round [dt] up to the next :00, :15, :30, or :45 boundary.
  DateTime _q(DateTime dt) {
    final r = dt.minute % 15;
    if (r == 0) return DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);
    final up = dt.add(Duration(minutes: 15 - r));
    return DateTime(up.year, up.month, up.day, up.hour, up.minute);
  }

  List<Map<String, dynamic>> _bookings() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    final list = <Map<String, dynamic>>[
      // ── Seated (currently at tables) ─────────────────────────────────────
      _booking(guid: 'seat-1', type: 'RESERVATION', status: 'R_SEATED', partySize: 4,
          start: now.subtract(const Duration(minutes: 35)),
          tables: ['t-1'], areas: ['area-dining'],
          firstName: 'Jason', lastName: 'Mitchell', phone: '14085558123',
          email: 'jason.mitchell@fakemail.com',
          created: now.subtract(const Duration(hours: 2))),
      _booking(guid: 'seat-2', type: 'RESERVATION', status: 'R_SEATED', partySize: 2,
          start: now.subtract(const Duration(minutes: 20)),
          tables: ['t-2'], areas: ['area-dining'],
          firstName: 'Vincent', lastName: 'Torres', phone: '16505556846',
          email: 'vincent.torres@fakemail.com',
          created: now.subtract(const Duration(hours: 3))),
      _booking(guid: 'seat-3', type: 'RESERVATION', status: 'R_SEATED', partySize: 3,
          start: now.subtract(const Duration(minutes: 15)),
          tables: ['t-11'], areas: ['area-dining'],
          firstName: 'Judith', lastName: 'Thomas', phone: '12135557637',
          email: 'judith.thomas@fakemail.com',
          created: now.subtract(const Duration(hours: 1))),
      _booking(guid: 'seat-4', type: 'RESERVATION', status: 'R_SEATED', partySize: 3,
          start: now.subtract(const Duration(minutes: 50)),
          tables: ['t-12'], areas: ['area-dining'],
          firstName: 'Beverly', lastName: 'Reed', phone: '16505559326',
          email: 'beverly.reed@fakemail.com',
          created: now.subtract(const Duration(hours: 4))),
      _booking(guid: 'seat-5', type: 'RESERVATION', status: 'R_SEATED', partySize: 4,
          start: now.subtract(const Duration(minutes: 10)),
          tables: ['t-13'], areas: ['area-dining'],
          firstName: 'Jennifer', lastName: 'Evans', phone: '17185554858',
          email: 'jennifer.evans@fakemail.com',
          created: now.subtract(const Duration(hours: 1, minutes: 30))),
      _booking(guid: 'seat-6', type: 'RESERVATION', status: 'R_SEATED', partySize: 6,
          start: now.subtract(const Duration(minutes: 45)),
          tables: ['t-21'], areas: ['area-dining'],
          firstName: 'Julie', lastName: 'Anderson', phone: '12135553486',
          email: 'julie.anderson@fakemail.com',
          created: now.subtract(const Duration(hours: 5)),
          notes: 'Anniversary dinner', occasion: 'ANNIVERSARY', vip: true),
      _booking(guid: 'seat-7', type: 'RESERVATION', status: 'R_SEATED', partySize: 2,
          start: now.subtract(const Duration(minutes: 5)),
          tables: ['t-22'], areas: ['area-dining'],
          firstName: 'Kevin', lastName: 'Ramirez', phone: '16505553268',
          email: 'kevin.ramirez@fakemail.com',
          created: now.subtract(const Duration(hours: 2))),
      _booking(guid: 'seat-8', type: 'RESERVATION', status: 'R_SEATED', partySize: 3,
          start: now.subtract(const Duration(minutes: 25)),
          tables: ['t-p1'], areas: ['area-patio'],
          firstName: 'Julia', lastName: 'Edwards', phone: '17185556552',
          email: 'julia.edwards@fakemail.com',
          created: now.subtract(const Duration(hours: 1))),
      _booking(guid: 'seat-9', type: 'RESERVATION', status: 'R_SEATED', partySize: 4,
          start: now.subtract(const Duration(minutes: 30)),
          tables: ['t-p2'], areas: ['area-patio'],
          firstName: 'Edward', lastName: 'Gutierrez', phone: '12135559492',
          email: 'edward.gutierrez@fakemail.com',
          created: now.subtract(const Duration(hours: 2))),

      // ── Arrived (on-site, awaiting table) ────────────────────────────────
      _booking(guid: 'arr-1', type: 'RESERVATION', status: 'R_ARRIVED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 8))),
          tables: ['t-3'], areas: ['area-dining'],
          firstName: 'Kathy', lastName: 'Taylor', phone: '16505552396',
          email: 'kathy.taylor@fakemail.com',
          created: now.subtract(const Duration(days: 1)),
          arrivedAt: now.subtract(const Duration(minutes: 5)),
          notes: 'Celebrating a new job; hoping for a lively table in the main dining room.'),
      _booking(guid: 'arr-2', type: 'RESERVATION', status: 'R_ARRIVED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 15))),
          tables: ['t-c1'], areas: ['area-dining'],
          firstName: 'Keith', lastName: 'Johnson', phone: '16505557677',
          email: 'keith.johnson@fakemail.com',
          created: now.subtract(const Duration(days: 2)),
          arrivedAt: now.subtract(const Duration(minutes: 8))),
      _booking(guid: 'arr-3', type: 'RESERVATION', status: 'R_ARRIVED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 20))),
          tables: ['t-4'], areas: ['area-dining'], pinned: true,
          firstName: 'Angela', lastName: 'Perez', phone: '17185551435',
          email: 'angela.perez@fakemail.com',
          created: now.subtract(const Duration(hours: 6)),
          arrivedAt: now.subtract(const Duration(minutes: 2)),
          notes: 'Celebrating a 50th wedding anniversary; a quiet, romantic table would be lovely.',
          occasion: 'ANNIVERSARY'),

      // ── Upcoming today ────────────────────────────────────────────────────
      // Table assignment strategy (90-min turn time):
      // Wave 1 uses fresh available tables; Wave 2 reuses them once they've turned.
      // t-5/t-14/t-15/t-23: dining 4-tops | t-c1…t-c6: counter 2-tops
      // Patio tables (t-p3…t-p6) available for later waves.
      _booking(guid: 'res-1', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 4,
          start: _q(now.add(const Duration(minutes: 30))),
          tables: ['t-23'], areas: ['area-dining'], pinned: true,
          firstName: 'Sharon', lastName: 'Foster', phone: '17185554667',
          email: 'sharon.foster@fakemail.com',
          created: now.subtract(const Duration(days: 3)),
          notes: "It's a surprise birthday for my friend; please no mention of it until dessert.",
          occasion: 'BIRTHDAY', vip: true),
      _booking(guid: 'res-2', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 45))),
          tables: ['t-14'], areas: ['area-dining'],
          firstName: 'Patrick', lastName: 'Cooper', phone: '16505555670',
          email: 'patrick.cooper@fakemail.com',
          created: now.subtract(const Duration(days: 1)),
          notes: 'Prefer a table away from the kitchen entrance if possible.'),
      _booking(guid: 'res-3', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 60))),
          tables: ['t-15'], areas: ['area-dining'],
          firstName: 'Hannah', lastName: 'Lewis', phone: '16505554242',
          email: 'hannah.lewis@fakemail.com',
          created: now.subtract(const Duration(days: 4))),
      _booking(guid: 'res-4', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 75))),
          tables: ['t-c2'], areas: ['area-dining'],
          firstName: 'William', lastName: 'Anderson', phone: '16505554714',
          email: 'william.anderson@fakemail.com',
          created: now.subtract(const Duration(days: 2)),
          notes: "It's a surprise birthday for my friend; please no mention of it until dessert.",
          occasion: 'BIRTHDAY'),
      _booking(guid: 'res-5', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 4,
          start: _q(now.add(const Duration(minutes: 90))),
          // 4-top: two 2-tops pushed together (t-1 frees at +55, t-2 at +70)
          tables: ['t-1', 't-2'], areas: ['area-dining'],
          firstName: 'Sandra', lastName: 'Stewart', phone: '16505551694',
          email: 'sandra.stewart@fakemail.com',
          created: now.subtract(const Duration(days: 1))),
      _booking(guid: 'res-6', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 105))),
          tables: ['t-c3'], areas: ['area-dining'],
          firstName: 'Brian', lastName: 'Campbell', phone: '17185550514',
          email: 'brian.campbell@fakemail.com',
          created: now.subtract(const Duration(days: 3))),
      _booking(guid: 'res-7', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 120))),
          tables: ['t-c4'], areas: ['area-dining'],
          firstName: 'Diana', lastName: 'Sanchez', phone: '16505555727',
          email: 'diana.sanchez@fakemail.com',
          created: now.subtract(const Duration(days: 2))),
      _booking(guid: 'res-8', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 135))),
          tables: ['t-c5'], areas: ['area-dining'], pinned: true,
          firstName: 'Rebecca', lastName: 'Green', phone: '19425555399',
          email: 'rebecca.green@fakemail.com',
          created: now.subtract(const Duration(days: 5)),
          notes: 'One diner has a shellfish allergy; careful preparation is essential.'),
      _booking(guid: 'res-9', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 150))),
          tables: ['t-c6'], areas: ['area-dining'],
          firstName: 'Nathan', lastName: 'Hughes', phone: '17185552093',
          email: 'nathan.hughes@fakemail.com',
          created: now.subtract(const Duration(days: 1))),
      // Wave 2: tables freed from Wave 1 (≥90 min after their first seating)
      _booking(guid: 'res-10', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 165))),
          tables: ['t-14'], areas: ['area-dining'],   // frees from res-2 at +45+90=+135 ✓
          firstName: 'Andrew', lastName: 'Kelly', phone: '17185558218',
          email: 'andrew.kelly@fakemail.com',
          created: now.subtract(const Duration(days: 2))),
      _booking(guid: 'res-11', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 180))),
          tables: ['t-15'], areas: ['area-dining'], pinned: true,   // frees from res-3 at +60+90=+150 ✓
          firstName: 'Lauren', lastName: 'Richardson', phone: '17185550419',
          email: 'lauren.richardson@fakemail.com',
          created: now.subtract(const Duration(days: 3)),
          notes: "We're celebrating a promotion; any chance of a complimentary dessert?",
          occasion: 'CELEBRATION'),
      _booking(guid: 'res-12', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 4,
          start: _q(now.add(const Duration(minutes: 210))),
          // 4-top: t-4 + t-5 pushed. t-4 frees from arr-3 at +110 ✓
          tables: ['t-4', 't-5'], areas: ['area-dining'], pinned: true,
          firstName: 'Timothy', lastName: 'Long', phone: '16505556561',
          email: 'timothy.long@fakemail.com',
          created: now.subtract(const Duration(days: 1)),
          notes: 'My son is having his 10th birthday; could we have a table near the window?',
          occasion: 'BIRTHDAY'),
      _booking(guid: 'res-13', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 240))),
          tables: ['t-c2'], areas: ['area-dining'],   // frees from res-4 at +75+90=+165 ✓
          firstName: 'Jordan', lastName: 'Lee', phone: '16505551407',
          email: 'jordan.lee@fakemail.com',
          created: now.subtract(const Duration(days: 4))),
      _booking(guid: 'res-14', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 270))),
          tables: ['t-23'], areas: ['area-dining'],   // frees from res-5 at +90+90=+180 ✓
          firstName: 'Samantha', lastName: 'Howard', phone: '19425550910',
          email: 'samantha.howard@fakemail.com',
          created: now.subtract(const Duration(days: 2))),
      _booking(guid: 'res-15', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 4,
          start: _q(now.add(const Duration(minutes: 300))),
          tables: ['t-21'], areas: ['area-dining'],   // frees from seat-6 which started -45min ✓
          firstName: 'Aaron', lastName: 'Gomez', phone: '19425554427',
          email: 'aaron.gomez@fakemail.com',
          created: now.subtract(const Duration(days: 1))),
      _booking(guid: 'res-16', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 330))),
          tables: ['t-c3'], areas: ['area-dining'],   // frees from res-6 at +105+90=+195 ✓
          firstName: 'Bryan', lastName: 'White', phone: '17185550099',
          email: 'bryan.white@fakemail.com',
          created: now.subtract(const Duration(days: 3)),
          notes: 'We have a tight schedule, aiming for a quick meal before the theater.'),
      _booking(guid: 'res-17', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 360))),
          tables: ['t-c4'], areas: ['area-dining'],   // frees from res-7 at +120+90=+210 ✓
          firstName: 'Walter', lastName: 'Campbell', phone: '17185553091',
          email: 'walter.campbell@fakemail.com',
          created: now.subtract(const Duration(days: 5))),
      _booking(guid: 'res-18', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: _q(now.add(const Duration(minutes: 390))),
          tables: ['t-c5'], areas: ['area-dining'],   // frees from res-8 at +135+90=+225 ✓
          firstName: 'Debra', lastName: 'Myers', phone: '16505553271',
          email: 'debra.myers@fakemail.com',
          created: now.subtract(const Duration(days: 2))),

      // ── Tomorrow ──────────────────────────────────────────────────────────
      _booking(guid: 'tmr-1', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 4,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 12, 0),
          tables: ['t-4', 't-5'], areas: ['area-dining'],
          firstName: 'Janice', lastName: 'Hill', phone: '16505557206',
          email: 'janice.hill@fakemail.com',
          created: now.subtract(const Duration(days: 7))),
      _booking(guid: 'tmr-2', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 12, 30),
          tables: ['t-14'], areas: ['area-dining'],
          firstName: 'Rachel', lastName: 'Green', phone: '17185557615',
          email: 'rachel.green@fakemail.com',
          created: now.subtract(const Duration(days: 5))),
      _booking(guid: 'tmr-3', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 13, 0),
          tables: ['t-15'], areas: ['area-dining'],
          firstName: 'Kyle', lastName: 'Cox', phone: '17185558283',
          email: 'kyle.cox@fakemail.com',
          created: now.subtract(const Duration(days: 3))),
      _booking(guid: 'tmr-4', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 13, 30),
          tables: ['t-c1'], areas: ['area-dining'],
          firstName: 'Isaac', lastName: 'Carter', phone: '16505558775',
          email: 'isaac.carter@fakemail.com',
          created: now.subtract(const Duration(days: 4))),
      _booking(guid: 'tmr-5', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 14, 0),
          tables: ['t-c2'], areas: ['area-dining'],
          firstName: 'Frank', lastName: 'Martinez', phone: '17185553441',
          email: 'frank.martinez@fakemail.com',
          created: now.subtract(const Duration(days: 6))),
      _booking(guid: 'tmr-6', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 14, 30),
          tables: ['t-11'], areas: ['area-dining'],
          firstName: 'Jacob', lastName: 'Morris', phone: '17185557996',
          email: 'jacob.morris@fakemail.com',
          created: now.subtract(const Duration(days: 2))),
      _booking(guid: 'tmr-7', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15, 0),
          tables: ['t-12'], areas: ['area-dining'],
          firstName: 'Sharon', lastName: 'Robinson', phone: '17185556490',
          email: 'sharon.robinson@fakemail.com',
          created: now.subtract(const Duration(days: 3))),
      _booking(guid: 'tmr-8', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15, 30),
          tables: ['t-5'], areas: ['area-dining'],   // t-5 frees at 12:00+90=13:30 ✓
          firstName: 'Kenneth', lastName: 'Kelly', phone: '16505554150',
          email: 'kenneth.kelly@fakemail.com',
          created: now.subtract(const Duration(days: 5))),
      _booking(guid: 'tmr-9', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 16, 0),
          tables: ['t-14'], areas: ['area-dining'],  // frees at 12:30+90=14:00 ✓
          firstName: 'Gloria', lastName: 'Nguyen', phone: '17185555651',
          email: 'gloria.nguyen@fakemail.com',
          created: now.subtract(const Duration(days: 1))),
      _booking(guid: 'tmr-10', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 16, 30),
          tables: ['t-c1'], areas: ['area-dining'],  // frees at 13:30+90=15:00 ✓
          firstName: 'Jonathan', lastName: 'Castillo', phone: '17185556136',
          email: 'jonathan.castillo@fakemail.com',
          created: now.subtract(const Duration(days: 4))),
      _booking(guid: 'tmr-11', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 4,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 17, 0),
          tables: ['t-23'], areas: ['area-dining'],
          firstName: 'Emily', lastName: 'Lee', phone: '16505552575',
          email: 'emily.lee@fakemail.com',
          created: now.subtract(const Duration(days: 7))),
      _booking(guid: 'tmr-12', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 17, 30),
          tables: ['t-15'], areas: ['area-dining'],  // frees at 13:00+90=14:30 ✓
          firstName: 'Jesse', lastName: 'Evans', phone: '16505557998',
          email: 'jesse.evans@fakemail.com',
          created: now.subtract(const Duration(days: 2)),
          notes: "We're visiting from out of town and looking for a truly memorable dining experience."),
      _booking(guid: 'tmr-13', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 4,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18, 0),
          // 4-top: t-4 + t-5 pushed (tmr-1 ends 13:30, tmr-8 on t-5 ends 17:00 ✓)
          tables: ['t-4', 't-5'], areas: ['area-dining'],
          firstName: 'Frances', lastName: 'Jackson', phone: '19425554644',
          email: 'frances.jackson@fakemail.com',
          created: now.subtract(const Duration(days: 3))),
      _booking(guid: 'tmr-14', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 4,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18, 30),
          tables: ['t-1', 't-2'], areas: ['area-dining'], pinned: true,
          firstName: 'Sophia', lastName: 'King', phone: '17185553078',
          email: 'sophia.king@fakemail.com',
          created: now.subtract(const Duration(days: 5))),
      _booking(guid: 'tmr-15', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 10,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 19, 0),
          tables: ['t-21', 't-22'], areas: ['area-dining'], pinned: true, // large party — two tables combined
          firstName: 'Bobby', lastName: 'Peterson', phone: '17185559432',
          email: 'bobby.peterson@fakemail.com',
          created: now.subtract(const Duration(days: 6))),
      _booking(guid: 'tmr-16', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 19, 30),
          tables: ['t-c3'], areas: ['area-dining'],
          firstName: 'Ashley', lastName: 'Gray', phone: '16505556351',
          email: 'ashley.gray@fakemail.com',
          created: now.subtract(const Duration(days: 2)),
          notes: 'Requesting a table with a view of the city skyline for our engagement.',
          occasion: 'CELEBRATION'),
      _booking(guid: 'tmr-17', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 20, 0),
          tables: ['t-c4'], areas: ['area-dining'],
          firstName: 'Ruth', lastName: 'Lewis', phone: '17185557881',
          email: 'ruth.lewis@fakemail.com',
          created: now.subtract(const Duration(days: 4)),
          notes: 'Any chance of a small candle for a birthday celebration on a dessert?',
          occasion: 'BIRTHDAY'),
      _booking(guid: 'tmr-18', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 20, 30),
          tables: ['t-14'], areas: ['area-dining'],  // frees from tmr-9 at 16:00+90=17:30 ✓
          firstName: 'Marilyn', lastName: 'Rivera', phone: '16505554784',
          email: 'marilyn.rivera@fakemail.com',
          created: now.subtract(const Duration(days: 1))),
      _booking(guid: 'tmr-19', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 21, 0),
          tables: ['t-15'], areas: ['area-dining'],  // frees from tmr-12 at 17:30+90=19:00 ✓
          firstName: 'Jacqueline', lastName: 'Gray', phone: '19425550932',
          email: 'jacqueline.gray@fakemail.com',
          created: now.subtract(const Duration(days: 3)),
          notes: 'One of our guests has a gluten intolerance; please advise on suitable menu items.'),
      _booking(guid: 'tmr-20', type: 'RESERVATION', status: 'R_CONFIRMED', partySize: 2,
          start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 21, 30),
          tables: ['t-c5'], areas: ['area-dining'],
          firstName: 'Bruce', lastName: 'White', phone: '16505553588',
          email: 'bruce.white@fakemail.com',
          created: now.subtract(const Duration(days: 7))),

      // ── Waitlist ──────────────────────────────────────────────────────────
      _booking(guid: 'wait-1', type: 'WAITLIST', status: 'W_WAITING', partySize: 3,
          start: _q(now.add(const Duration(minutes: 15))),
          tables: [], areas: [],
          firstName: 'Emily', lastName: 'Gomez', phone: '17185558202',
          email: 'emily.gomez@fakemail.com',
          created: now.subtract(const Duration(minutes: 12))),
      _booking(guid: 'wait-2', type: 'WAITLIST', status: 'W_WAITING', partySize: 2,
          start: _q(now.add(const Duration(minutes: 25))),
          tables: [], areas: [],
          firstName: 'Nicholas', lastName: 'Rivera', phone: '12135557862',
          email: 'nicholas.rivera@fakemail.com',
          created: now.subtract(const Duration(minutes: 8))),
      _booking(guid: 'wait-3', type: 'WAITLIST', status: 'W_WAITING', partySize: 4,
          start: _q(now.add(const Duration(minutes: 35))),
          tables: [], areas: [],
          firstName: 'Juan', lastName: 'Castillo', phone: '17185551115',
          email: 'juan.castillo@fakemail.com',
          created: now.subtract(const Duration(minutes: 5))),
      _booking(guid: 'wait-4', type: 'WAITLIST', status: 'W_WAITING', partySize: 2,
          start: _q(now.add(const Duration(minutes: 40))),
          tables: [], areas: [],
          firstName: 'Debra', lastName: 'Hernandez', phone: '14085550890',
          email: 'debra.hernandez@fakemail.com',
          created: now.subtract(const Duration(minutes: 3))),
      _booking(guid: 'wait-5', type: 'WAITLIST', status: 'W_WAITING', partySize: 5,
          start: _q(now.add(const Duration(minutes: 50))),
          tables: [], areas: [],
          firstName: 'Natalie', lastName: 'Gonzales', phone: '12135553156',
          email: 'natalie.gonzales@fakemail.com',
          created: now.subtract(const Duration(minutes: 1))),
    ];

    // Apply session status overrides set by PATCH endpoints. This is what
    // makes status changes (e.g. Confirmed → Arrived) actually stick in the
    // UI for the duration of the page session.
    if (_statusOverrides.isNotEmpty || _notifyTimes.isNotEmpty) {
      for (final b in list) {
        final guid = b['guid'] as String?;
        final override = _statusOverrides[guid];
        if (override != null) {
          b['bookingStatus'] = override;
          // Stamp timestamps the row UI keys off of, so badges + countdowns
          // animate the way the real backend would drive them.
          if (override.endsWith('_ARRIVED') && b['arrivedTime'] == null) {
            b['arrivedTime'] = DateTime.now().toIso8601String();
          }
          if (override.endsWith('_SEATED') && b['actualStartTime'] == null) {
            b['actualStartTime'] = DateTime.now().toIso8601String();
          }
        }
        // Apply notify timestamp + bump notification count so the in-row
        // countdown displays after the user taps "Notify guest".
        final notifiedAt = _notifyTimes[guid];
        if (notifiedAt != null) {
          final iso = notifiedAt.toIso8601String();
          b['firstNotified'] ??= iso;
          b['lastNotified'] = iso;
          final cur = (b['notificationCount'] as int?) ?? 0;
          b['notificationCount'] = cur < 1 ? 1 : cur;
        }
      }
    }

    return list;
  }

  // ── Guestbook ─────────────────────────────────────────────────────────────
  // ~200 entries drawn from Demo Guests.csv. Format: email|+phone|First|Last

  static const List<String> _guestRows = [
    'jason.mitchell@fakemail.com|+14085558123|Jason|Mitchell',
    'vincent.torres@fakemail.com|+16505556846|Vincent|Torres',
    'judith.thomas@fakemail.com|+12135557637|Judith|Thomas',
    'beverly.reed@fakemail.com|+16505559326|Beverly|Reed',
    'jennifer.evans@fakemail.com|+17185554858|Jennifer|Evans',
    'julie.anderson@fakemail.com|+12135553486|Julie|Anderson',
    'kevin.ramirez@fakemail.com|+16505553268|Kevin|Ramirez',
    'julia.edwards@fakemail.com|+17185556552|Julia|Edwards',
    'edward.gutierrez@fakemail.com|+12135559492|Edward|Gutierrez',
    'emily.gomez@fakemail.com|+17185558202|Emily|Gomez',
    'nicholas.rivera@fakemail.com|+12135557862|Nicholas|Rivera',
    'juan.castillo@fakemail.com|+17185551115|Juan|Castillo',
    'debra.hernandez@fakemail.com|+14085550890|Debra|Hernandez',
    'natalie.gonzales@fakemail.com|+12135553156|Natalie|Gonzales',
    'david.morgan@fakemail.com|+12135556390|David|Morgan',
    'patricia.jones@fakemail.com|+16505551319|Patricia|Jones',
    'melissa.gray@fakemail.com|+17185553219|Melissa|Gray',
    'stephanie.bennet@fakemail.com|+16505554358|Stephanie|Bennet',
    'rebecca.gonzales@fakemail.com|+17185551373|Rebecca|Gonzales',
    'rachel.williams@fakemail.com|+14085553038|Rachel|Williams',
    'john.davis@fakemail.com|+17185556753|John|Davis',
    'alan.scott@fakemail.com|+14085557017|Alan|Scott',
    'brian.cox@fakemail.com|+16505558337|Brian|Cox',
    'mason.mitchell@fakemail.com|+17185550273|Mason|Mitchell',
    'jeremy.mendoza@fakemail.com|+16505559260|Jeremy|Mendoza',
    'jeffrey.chavez@fakemail.com|+17185553608|Jeffrey|Chavez',
    'michael.jones@fakemail.com|+14085553334|Michael|Jones',
    'terry.long@fakemail.com|+12135555797|Terry|Long',
    'barbara.martin@fakemail.com|+16505557818|Barbara|Martin',
    'ruth.robinson@fakemail.com|+12135551296|Ruth|Robinson',
    'thomas.phillips@fakemail.com|+14085555016|Thomas|Phillips',
    'jesse.evans@fakemail.com|+16505557998|Jesse|Evans',
    'anna.murphy@fakemail.com|+16505553164|Anna|Murphy',
    'nancy.garcia@fakemail.com|+12135556086|Nancy|Garcia',
    'victoria.ramirez@fakemail.com|+16505553486|Victoria|Ramirez',
    'sara.turner@fakemail.com|+17185555874|Sara|Turner',
    'deborah.martinez@fakemail.com|+16505553014|Deborah|Martinez',
    'lucas.wood@fakemail.com|+12135554415|Lucas|Wood',
    'brittany.thompson@fakemail.com|+17185558093|Brittany|Thompson',
    'david.phillips@fakemail.com|+17185554138|David|Phillips',
    'peter.davis@fakemail.com|+16505552838|Peter|Davis',
    'ronald.campbell@fakemail.com|+16505558895|Ronald|Campbell',
    'noah.baker@fakemail.com|+17185550150|Noah|Baker',
    'pamela.sanders@fakemail.com|+16505552777|Pamela|Sanders',
    'patricia.ramos@fakemail.com|+16505550762|Patricia|Ramos',
    'elizabeth.anderson@fakemail.com|+16505555149|Elizabeth|Anderson',
    'jonathan.castillo@fakemail.com|+17185556136|Jonathan|Castillo',
    'joshua.cook@fakemail.com|+17185550918|Joshua|Cook',
    'sandra.stewart@fakemail.com|+16505551694|Sandra|Stewart',
    'daniel.robinson@fakemail.com|+16505557826|Daniel|Robinson',
    'sharon.lee@fakemail.com|+14085550422|Sharon|Lee',
    'pamela.rodriguez@fakemail.com|+12135555381|Pamela|Rodriguez',
    'kelly.carter@fakemail.com|+14085555847|Kelly|Carter',
    'olivia.sanchez@fakemail.com|+17185559368|Olivia|Sanchez',
    'larry.evans@fakemail.com|+16505551124|Larry|Evans',
    'heather.sanchez@fakemail.com|+17185550181|Heather|Sanchez',
    'grace.cook@fakemail.com|+14085558776|Grace|Cook',
    'theresa.allen@fakemail.com|+16505556491|Theresa|Allen',
    'gerald.bennet@fakemail.com|+16505552682|Gerald|Bennet',
    'rachel.ward@fakemail.com|+16505550607|Rachel|Ward',
    'sharon.foster@fakemail.com|+17185554667|Sharon|Foster',
    'angela.perez@fakemail.com|+17185551435|Angela|Perez',
    'kathy.taylor@fakemail.com|+16505552396|Kathy|Taylor',
    'keith.johnson@fakemail.com|+16505557677|Keith|Johnson',
    'linda.morales@fakemail.com|+17185552023|Linda|Morales',
    'lauren.richardson@fakemail.com|+17185550419|Lauren|Richardson',
    'angela.johnson@fakemail.com|+17185553414|Angela|Johnson',
    'brenda.martinez@fakemail.com|+17185556400|Brenda|Martinez',
    'jonathan.king@fakemail.com|+17185557551|Jonathan|King',
    'diana.sanchez@fakemail.com|+16505555727|Diana|Sanchez',
    'brian.campbell@fakemail.com|+17185550514|Brian|Campbell',
    'gloria.nguyen@fakemail.com|+17185555651|Gloria|Nguyen',
    'willie.reed@fakemail.com|+16505550251|Willie|Reed',
    'jennifer.thomas@fakemail.com|+17185553754|Jennifer|Thomas',
    'christina.nguyen@fakemail.com|+17185557229|Christina|Nguyen',
    'joe.brown@fakemail.com|+16505550117|Joe|Brown',
    'christina.garcia@fakemail.com|+16505555146|Christina|Garcia',
    'william.anderson@fakemail.com|+16505554714|William|Anderson',
    'steven.martinez@fakemail.com|+16505555143|Steven|Martinez',
    'amber.harris@fakemail.com|+16505559522|Amber|Harris',
    'donna.rivera@fakemail.com|+17185552297|Donna|Rivera',
    'kathy.taylor@fakemail.com|+16505552396|Kathy|Taylor',
    'patrick.cooper@fakemail.com|+16505555670|Patrick|Cooper',
    'joe.hughes@fakemail.com|+16505559320|Joe|Hughes',
    'alan.collins@fakemail.com|+16505550544|Alan|Collins',
    'amber.davis@fakemail.com|+16505553985|Amber|Davis',
    'william.myers@fakemail.com|+17185555184|William|Myers',
    'juan.reed@fakemail.com|+17185557483|Juan|Reed',
    'hannah.lewis@fakemail.com|+16505554242|Hannah|Lewis',
    'grace.campbell@fakemail.com|+16505556556|Grace|Campbell',
    'katherine.brooks@fakemail.com|+17185557523|Katherine|Brooks',
    'lori.collins@fakemail.com|+16505554976|Lori|Collins',
    'isaac.castillo@fakemail.com|+17185551521|Isaac|Castillo',
    'charles.diaz@fakemail.com|+17185558835|Charles|Diaz',
    'joseph.nelson@fakemail.com|+16505550141|Joseph|Nelson',
    'luke.castillo@fakemail.com|+17185552293|Luke|Castillo',
    'kimberly.sanders@fakemail.com|+17185554896|Kimberly|Sanders',
    'virginia.alvarez@fakemail.com|+16505552330|Virginia|Alvarez',
    'betty.williams@fakemail.com|+17185552627|Betty|Williams',
    'ruth.taylor@fakemail.com|+16505554835|Ruth|Taylor',
    'joseph.turner@fakemail.com|+16505557185|Joseph|Turner',
    'brenda.taylor@fakemail.com|+17185556381|Brenda|Taylor',
    'billy.mendoza@fakemail.com|+16505554672|Billy|Mendoza',
    'daniel.wood@fakemail.com|+16505555852|Daniel|Wood',
    'nathan.hughes@fakemail.com|+17185552093|Nathan|Hughes',
    'rebecca.green@fakemail.com|+19425555399|Rebecca|Green',
    'ronald.campbell@fakemail.com|+16505558895|Ronald|Campbell',
    'marilyn.reed@fakemail.com|+17185559028|Marilyn|Reed',
    'samantha.howard@fakemail.com|+19425550910|Samantha|Howard',
    'aaron.gomez@fakemail.com|+19425554427|Aaron|Gomez',
    'andrew.kelly@fakemail.com|+17185558218|Andrew|Kelly',
    'nathan.gomez@fakemail.com|+17185559521|Nathan|Gomez',
    'andrew.mendoza@fakemail.com|+16505555585|Andrew|Mendoza',
    'jordan.lee@fakemail.com|+16505551407|Jordan|Lee',
    'timothy.long@fakemail.com|+16505556561|Timothy|Long',
    'bryan.white@fakemail.com|+17185550099|Bryan|White',
    'walter.campbell@fakemail.com|+17185553091|Walter|Campbell',
    'debra.myers@fakemail.com|+16505553271|Debra|Myers',
    'richard.kim@fakemail.com|+16505551990|Richard|Kim',
    'rachel.chavez@fakemail.com|+16505552012|Rachel|Chavez',
    'teresa.cox@fakemail.com|+16505553264|Teresa|Cox',
    'aaron.walker@fakemail.com|+16505554886|Aaron|Walker',
    'judy.chavez@fakemail.com|+16505558968|Judy|Chavez',
    'kenneth.moore@fakemail.com|+17185550466|Kenneth|Moore',
    'charles.martinez@fakemail.com|+16505555637|Charles|Martinez',
    'heather.cruz@fakemail.com|+16505559242|Heather|Cruz',
    'benjamin.ross@fakemail.com|+17185551348|Benjamin|Ross',
    'christopher.edwards@fakemail.com|+17185551800|Christopher|Edwards',
    'janice.hill@fakemail.com|+16505557206|Janice|Hill',
    'rachel.green@fakemail.com|+17185557615|Rachel|Green',
    'kyle.cox@fakemail.com|+17185558283|Kyle|Cox',
    'stephanie.wilson@fakemail.com|+16505555097|Stephanie|Wilson',
    'isaac.carter@fakemail.com|+16505558775|Isaac|Carter',
    'frank.martinez@fakemail.com|+17185553441|Frank|Martinez',
    'jacob.morris@fakemail.com|+17185557996|Jacob|Morris',
    'lori.cox@fakemail.com|+17185559522|Lori|Cox',
    'sharon.robinson@fakemail.com|+17185556490|Sharon|Robinson',
    'kenneth.kelly@fakemail.com|+16505554150|Kenneth|Kelly',
    'cynthia.smith@fakemail.com|+16505555824|Cynthia|Smith',
    'kelly.ramirez@fakemail.com|+16505559504|Kelly|Ramirez',
    'gloria.nguyen@fakemail.com|+17185555651|Gloria|Nguyen',
    'melissa.bailey@fakemail.com|+17185557616|Melissa|Bailey',
    'emily.lee@fakemail.com|+16505552575|Emily|Lee',
    'karen.hughes@fakemail.com|+17185552233|Karen|Hughes',
    'dennis.ward@fakemail.com|+16505558219|Dennis|Ward',
    'karen.williams@fakemail.com|+17185556745|Karen|Williams',
    'jacqueline.james@fakemail.com|+16505558791|Jacqueline|James',
    'frances.jackson@fakemail.com|+19425554644|Frances|Jackson',
    'jacqueline.jimenez@fakemail.com|+19425557894|Jacqueline|Jimenez',
    'willie.jones@fakemail.com|+16505551687|Willie|Jones',
    'joyce.kelly@fakemail.com|+16505553102|Joyce|Kelly',
    'kayla.ward@fakemail.com|+17185553475|Kayla|Ward',
    'samuel.smith@fakemail.com|+16505553645|Samuel|Smith',
    'ashley.gray@fakemail.com|+16505556351|Ashley|Gray',
    'katherine.alvarez@fakemail.com|+16505554166|Katherine|Alvarez',
    'maria.clark@fakemail.com|+16505558068|Maria|Clark',
    'vincent.bailey@fakemail.com|+17185552058|Vincent|Bailey',
    'jose.nelson@fakemail.com|+16505558800|Jose|Nelson',
    'joyce.gomez@fakemail.com|+17185559540|Joyce|Gomez',
    'patricia.ramos@fakemail.com|+16505550762|Patricia|Ramos',
    'katherine.moore@fakemail.com|+16505556393|Katherine|Moore',
    'sophia.king@fakemail.com|+17185553078|Sophia|King',
    'jacqueline.gray@fakemail.com|+19425550932|Jacqueline|Gray',
    'judy.anderson@fakemail.com|+16505554726|Judy|Anderson',
    'randy.jimenez@fakemail.com|+17185553446|Randy|Jimenez',
    'marilyn.rivera@fakemail.com|+16505554784|Marilyn|Rivera',
    'judy.perez@fakemail.com|+16505555192|Judy|Perez',
    'anna.reed@fakemail.com|+19425552252|Anna|Reed',
    'bruce.white@fakemail.com|+16505553588|Bruce|White',
    'jacqueline.james2@fakemail.com|+16505550528|Jacqueline|James',
    'ruth.lewis@fakemail.com|+17185557881|Ruth|Lewis',
    'laura.sanders@fakemail.com|+17185551269|Laura|Sanders',
    'lauren.green@fakemail.com|+17185557503|Lauren|Green',
    'brittany.thompson2@fakemail.com|+17185558093|Brittany|Thompson',
    'stephen.collins@fakemail.com|+17185559131|Stephen|Collins',
    'bobby.peterson@fakemail.com|+17185559432|Bobby|Peterson',
    'megan.phillips@fakemail.com|+17185553507|Megan|Phillips',
    'alice.hernandez@fakemail.com|+16505550559|Alice|Hernandez',
    'sarah.james@fakemail.com|+17185550134|Sarah|James',
    'christopher.brown@fakemail.com|+16505552174|Christopher|Brown',
    'isaac.williams@fakemail.com|+16505557285|Isaac|Williams',
    'ethan.watson@fakemail.com|+16505557669|Ethan|Watson',
    'sarah.martinez@fakemail.com|+16505553589|Sarah|Martinez',
    'carol.long@fakemail.com|+17185552817|Carol|Long',
    'jonathan.torres@fakemail.com|+17185557958|Jonathan|Torres',
    'stephanie.walker@fakemail.com|+17185552449|Stephanie|Walker',
    'barbara.reed@fakemail.com|+16505555399|Barbara|Reed',
    'edward.wright@fakemail.com|+17185552953|Edward|Wright',
    'sean.williams@fakemail.com|+17185557332|Sean|Williams',
    'jeffrey.wood@fakemail.com|+19425556036|Jeffrey|Wood',
    'denise.perez@fakemail.com|+16505554509|Denise|Perez',
    'lori.garcia@fakemail.com|+17185557659|Lori|Garcia',
    'diana.baker@fakemail.com|+16505559425|Diana|Baker',
    'alexander.reed@fakemail.com|+17185554759|Alexander|Reed',
    'timothy.walker@fakemail.com|+17185555605|Timothy|Walker',
    'jeremy.sanchez@fakemail.com|+17185554388|Jeremy|Sanchez',
    'linda.williams@fakemail.com|+17185554646|Linda|Williams',
    'olivia.peterson@fakemail.com|+17185552857|Olivia|Peterson',
    'melissa.rivera@fakemail.com|+17185551398|Melissa|Rivera',
    'david.morgan@fakemail.com|+12135556390|David|Morgan',
    'roger.allen@fakemail.com|+16505552761|Roger|Allen',
    'angela.adams@fakemail.com|+17185557247|Angela|Adams',
    'jacqueline.martin@fakemail.com|+17185555214|Jacqueline|Martin',
    'paul.moore@fakemail.com|+16505557686|Paul|Moore',
    'denise.flores@fakemail.com|+16505550793|Denise|Flores',
    'carolyn.evans@fakemail.com|+16505558519|Carolyn|Evans',
    'keith.brooks@fakemail.com|+16505552444|Keith|Brooks',
    'mason.jimenez@fakemail.com|+16505555324|Mason|Jimenez',
    'hannah.mendoza@fakemail.com|+16505559319|Hannah|Mendoza',
    'samantha.bailey@fakemail.com|+12135551341|Samantha|Bailey',
    'kenneth.morris@fakemail.com|+12135551703|Kenneth|Morris',
    'luke.gomez@fakemail.com|+14085553113|Luke|Gomez',
    'cheryl.reyes@fakemail.com|+12135556365|Cheryl|Reyes',
    'gerald.rivera@fakemail.com|+17185558855|Gerald|Rivera',
    'maria.sanchez@fakemail.com|+17185552015|Maria|Sanchez',
    'amber.walker@fakemail.com|+14085551193|Amber|Walker',
    'gabriel.kim@fakemail.com|+14085551152|Gabriel|Kim',
    'kathleen.wilson@fakemail.com|+14085557041|Kathleen|Wilson',
    'marilyn.adams@fakemail.com|+14085558455|Marilyn|Adams',
    'judith.taylor@fakemail.com|+16505554838|Judith|Taylor',
    'carol.wright@fakemail.com|+12135555118|Carol|Wright',
    'jason.stewart@fakemail.com|+17185554805|Jason|Stewart',
    'cynthia.watson@fakemail.com|+17185552536|Cynthia|Watson',
    'thomas.edwards@fakemail.com|+16505558448|Thomas|Edwards',
    'laura.parker@fakemail.com|+12135550021|Laura|Parker',
    'diane.wilson@fakemail.com|+16505557207|Diane|Wilson',
    'abigail.carter@fakemail.com|+14085558693|Abigail|Carter',
  ];

  List<Map<String, dynamic>> _guests() => _guestRows.map((row) {
        final p = row.split('|');
        return <String, dynamic>{
          'guid': 'g-${p[1].replaceAll('+', '')}',
          'firstName': p[2],
          'lastName': p[3],
          'phoneNumber': p[1],
          'email': p[0],
          'bookingCount': 0,
          'guestNotes': null,
          'guestTags': <String>[],
          'guestbookTagIds': <String>[],
          'guestbookGuid': null,
          'guestProfilesGuid': null,
        };
      }).toList();

  // ── Booking builder ───────────────────────────────────────────────────────

  Map<String, dynamic> _booking({
    required String guid,
    required String type,
    required String status,
    required int partySize,
    required DateTime start,
    required List<String> tables,
    required List<String> areas, // empty → defaults to ['area-dining']
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    required DateTime created,
    String? notes,
    DateTime? arrivedAt,
    // BIRTHDAY | ANNIVERSARY | DATE | BUSINESS | REUNION | CELEBRATION
    String? occasion,
    bool vip = false,
    // When true, this booking's table assignment is "manually pinned" by the host
    // (won't auto-reassign). When false, the table was system-suggested.
    bool pinned = false,
  }) {
    // Default to Dining Room so every reservation shows its area in the list.
    // Patio/other areas must be passed explicitly (non-empty list).
    final effectiveAreas = areas.isEmpty ? const <String>['area-dining'] : areas;

    return {
      'guid': guid,
      'bookingType': type,
      'bookingStatus': status,
      'partySize': partySize,
      'expectedStartTime': start.toIso8601String(),
      'expectedEndTime': start.add(const Duration(minutes: 90)).toIso8601String(),
      'actualStartTime': status == 'R_SEATED' ? start.toIso8601String() : null,
      'actualEndTime': null,
      'tables': tables,
      'serviceAreas': effectiveAreas,
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
      'visitNotes': notes,
      // bookingNotes mirrors visitNotes so the notes icon renders in the list
      'bookingNotes': notes,
      'bookingSource': null,
      'bookableId': null,
      // Verified against BookingDto source: `requestedTable` is the real field
      // backing the pushpin icon. When the host manually assigns a table, the
      // app populates requestedTable with the chosen table guids — that signals
      // "don't auto-reassign this." When empty, the assignment was system-chosen.
      'requestedTable': pinned ? tables : <String>[],
      'paymentConfigType': null,
      'paymentConfigSnapshot': null,
      'arrivedTime': arrivedAt?.toIso8601String(),
      'toastPayEnabled': null,
      'paymentMandateId': null,
      'specialOccasion': occasion,
      'guest': {
        'guid': 'g-${phone.replaceAll('+', '')}',
        'firstName': firstName,
        'lastName': lastName,
        'phoneNumber': phone,
        'email': email.isNotEmpty ? email : null,
        'bookingCount': 0,
        'guestNotes': null,
        // Reference the official VIP tag guid (from DefaultGuestTag enum)
        // so bookings link to the same tag rendered by the guestTags endpoint.
        'guestTags': vip ? [_vipTagGuid] : <String>[],
        'guestbookTagIds': vip ? [_vipTagGuid] : <String>[],
        'vipStatus': vip,
        'guestbookGuid': null,
        'guestProfilesGuid': null,
      },
      'createdDate': created.toIso8601String(),
      'modifiedDate': created.toIso8601String(),
    };
  }

  // ── Availabilities (time-slot picker in Create Reservation) ──────────────

  List<Map<String, dynamic>> _availabilities() {
    // Return half-hour slots covering the next 8 hours, rounded to :00/:30.
    final slots = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (int i = 1; i <= 16; i++) {
      final raw = now.add(Duration(minutes: i * 30));
      final slot = DateTime(raw.year, raw.month, raw.day, raw.hour,
          raw.minute < 30 ? 0 : 30);
      final timeStr =
          '${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}:00';
      slots.add({
        'time': timeStr,
        'available': true,
        'serviceAreaGuids': ['area-dining', 'area-patio'],
        'partySize': 2,
      });
    }
    return slots;
  }

  // ── Reservation config (per-date restaurant config) ───────────────────────

  Map<String, dynamic> _configInfo() => {
        'reservationsEnabled': true,
        'waitlistEnabled': true,
        'maxPartySize': 20,
        'minPartySize': 1,
        'slotDuration': 15,
        'turnTime': 90,
        'openTime': '11:00:00',
        'closeTime': '22:00:00',
        'timeZone': 'America/New_York',
      };

  // ── Tables (flat list for GET /tables) ───────────────────────────────────

  List<Map<String, dynamic>> _allTables() => [
        // 2-tops (can be pushed together for 4, or 3 together for 6)
        _table('t-1',  name: '1',  top: 70,  left: 25,  w: 95,  h: 95,  type: 'SQUARE', minCap: 1, maxCap: 2),
        _table('t-2',  name: '2',  top: 70,  left: 155, w: 95,  h: 95,  type: 'SQUARE', minCap: 1, maxCap: 2),
        _table('t-3',  name: '3',  top: 70,  left: 285, w: 95,  h: 95,  type: 'SQUARE', minCap: 1, maxCap: 2),
        _table('t-4',  name: '4',  top: 70,  left: 415, w: 95,  h: 95,  type: 'SQUARE', minCap: 1, maxCap: 2),
        _table('t-5',  name: '5',  top: 70,  left: 540, w: 95,  h: 95,  type: 'SQUARE', minCap: 1, maxCap: 2),
        _table('t-11', name: '11', top: 205, left: 25,  w: 95,  h: 95,  type: 'SQUARE', minCap: 1, maxCap: 2),
        _table('t-12', name: '12', top: 205, left: 155, w: 95,  h: 95,  type: 'SQUARE', minCap: 1, maxCap: 2),
        _table('t-13', name: '13', top: 205, left: 285, w: 95,  h: 95,  type: 'SQUARE', minCap: 1, maxCap: 2),
        _table('t-14', name: '14', top: 205, left: 415, w: 95,  h: 95,  type: 'SQUARE', minCap: 1, maxCap: 2),
        _table('t-15', name: '15', top: 205, left: 540, w: 95,  h: 95,  type: 'SQUARE', minCap: 1, maxCap: 2),
        // Large round tables (5-6 each)
        _table('t-21', name: '21', top: 360, left: 25,  w: 120, h: 120, type: 'CIRCLE', minCap: 4, maxCap: 6),
        _table('t-22', name: '22', top: 360, left: 180, w: 120, h: 120, type: 'CIRCLE', minCap: 4, maxCap: 6),
        _table('t-23', name: '23', top: 360, left: 540, w: 120, h: 120, type: 'CIRCLE', minCap: 4, maxCap: 6),
        // Counter: 1-tops, max 2 (a couple sitting at adjacent stools)
        _table('t-c1', name: 'C1', top: 70,  left: 745, w: 60,  h: 60,  type: 'CIRCLE', minCap: 1, maxCap: 2),
        _table('t-c2', name: 'C2', top: 160, left: 745, w: 60,  h: 60,  type: 'CIRCLE', minCap: 1, maxCap: 2),
        _table('t-c3', name: 'C3', top: 250, left: 745, w: 60,  h: 60,  type: 'CIRCLE', minCap: 1, maxCap: 2),
        _table('t-c4', name: 'C4', top: 365, left: 745, w: 60,  h: 60,  type: 'CIRCLE', minCap: 1, maxCap: 2),
        _table('t-c5', name: 'C5', top: 450, left: 745, w: 60,  h: 60,  type: 'CIRCLE', minCap: 1, maxCap: 2),
        _table('t-c6', name: 'C6', top: 535, left: 745, w: 60,  h: 60,  type: 'CIRCLE', minCap: 1, maxCap: 2),
        // Patio: 3-4 each, can't be pushed together
        _table('t-p1', name: 'P1', top: 70,  left: 30,  w: 120, h: 120, type: 'SQUARE', minCap: 2, maxCap: 4),
        _table('t-p2', name: 'P2', top: 70,  left: 200, w: 120, h: 120, type: 'SQUARE', minCap: 2, maxCap: 4),
        _table('t-p3', name: 'P3', top: 70,  left: 370, w: 120, h: 120, type: 'SQUARE', minCap: 2, maxCap: 4),
        _table('t-p4', name: 'P4', top: 240, left: 30,  w: 120, h: 120, type: 'SQUARE', minCap: 2, maxCap: 4),
        _table('t-p5', name: 'P5', top: 240, left: 200, w: 120, h: 120, type: 'SQUARE', minCap: 2, maxCap: 4),
        _table('t-p6', name: 'P6', top: 240, left: 370, w: 120, h: 120, type: 'SQUARE', minCap: 2, maxCap: 4),
      ];

  // ── Table states (OCCUPIED for seated tables, AVAILABLE for the rest) ─────

  List<Map<String, dynamic>> _tableStates() {
    const occupied = {'t-1','t-2','t-11','t-12','t-13','t-21','t-22','t-p1','t-p2'};
    return _allTables().map((t) {
      final guid = t['guid'] as String;
      // Override map wins if the user marked the table DIRTY or made it
      // AVAILABLE via the floor-plan menu mid-session.
      final overridden = _tableStateOverrides[guid];
      final defaultState = occupied.contains(guid) ? 'SEATED' : 'AVAILABLE';
      return <String, dynamic>{
        'tableGuid': guid,
        // Valid values per app: AVAILABLE | DIRTY | BLOCKED | SEATED
        'state': overridden ?? defaultState,
      };
    }).toList();
  }

  // ── Employees (demo servers) ──────────────────────────────────────────────

  // Employee guids must be BigInt-parseable — Toast uses long numeric IDs.
  // Letter prefixes ("emp-1") crash the app's BigInt parser and break the
  // server roster modal (white box) and the main bootstrap fetch.
  //
  // We include both on-roster servers (already working) and off-roster
  // employees (selectable in the "Add to roster" modal). Without off-roster
  // candidates the modal renders an empty list and crashes on .first.
  List<Map<String, dynamic>> _employees() => [
        // ── On roster ─────────────────────────────────────────────────────
        {
          'guid': '1000000000000001',
          'firstName': 'Alex',
          'lastName': 'Rivera',
          'serverColor': {'serverColor': '#E57373', 'textColor': '#FFFFFF'},
          'onRoster': true,
          'clockedIn': true,
          'clockInRequired': false,
          'permissions': '4',
        },
        {
          'guid': '1000000000000002',
          'firstName': 'Jordan',
          'lastName': 'Park',
          'serverColor': {'serverColor': '#64B5F6', 'textColor': '#FFFFFF'},
          'onRoster': true,
          'clockedIn': true,
          'clockInRequired': false,
          'permissions': '4',
        },
        {
          'guid': '1000000000000003',
          'firstName': 'Taylor',
          'lastName': 'Brooks',
          'serverColor': {'serverColor': '#81C784', 'textColor': '#FFFFFF'},
          'onRoster': true,
          'clockedIn': true,
          'clockInRequired': false,
          'permissions': '4',
        },
        // ── Off roster (selectable to add) ────────────────────────────────
        {
          'guid': '1000000000000004',
          'firstName': 'Morgan',
          'lastName': 'Chen',
          'serverColor': {'serverColor': '#BA68C8', 'textColor': '#FFFFFF'},
          'onRoster': false,
          'clockedIn': false,
          'clockInRequired': false,
          'permissions': '4',
        },
        {
          'guid': '1000000000000005',
          'firstName': 'Casey',
          'lastName': 'Nguyen',
          'serverColor': {'serverColor': '#FFB74D', 'textColor': '#FFFFFF'},
          'onRoster': true,
          'clockedIn': true,
          'clockInRequired': false,
          'permissions': '4',
        },
        {
          'guid': '1000000000000006',
          'firstName': 'Riley',
          'lastName': 'Patel',
          'serverColor': {'serverColor': '#4DD0E1', 'textColor': '#FFFFFF'},
          'onRoster': false,
          'clockedIn': false,
          'clockInRequired': false,
          'permissions': '4',
        },
        {
          'guid': '1000000000000007',
          'firstName': 'Sam',
          'lastName': 'Walker',
          'serverColor': {'serverColor': '#AED581', 'textColor': '#FFFFFF'},
          'onRoster': false,
          'clockedIn': false,
          'clockInRequired': false,
          'permissions': '4',
        },
        {
          'guid': '1000000000000008',
          'firstName': 'Drew',
          'lastName': 'Kim',
          'serverColor': {'serverColor': '#F06292', 'textColor': '#FFFFFF'},
          'onRoster': false,
          'clockedIn': false,
          'clockInRequired': false,
          'permissions': '4',
        },
      ];

  // ── Server assignments (employee ↔ table mapping) ────────────────────────
  // Default sections per Sam's request:
  //   Alex   → dining tables 1-5
  //   Jordan → dining tables 11-15
  //   Taylor → round tables 21-23 + counter C1-C6
  //   Casey  → all patio tables
  // Schema verified from ServerAssignmentDto source: {employeeGuid, tableGuid}.

  static const String _empAlex   = '1000000000000001';
  static const String _empJordan = '1000000000000002';
  static const String _empTaylor = '1000000000000003';
  static const String _empCasey  = '1000000000000005';

  List<Map<String, dynamic>> _serverAssignments() {
    Map<String, dynamic> assign(String emp, String table) => {
      'employeeGuid': emp,
      'tableGuid': table,
    };
    return [
      // Alex — dining 1-5
      assign(_empAlex,   't-1'),
      assign(_empAlex,   't-2'),
      assign(_empAlex,   't-3'),
      assign(_empAlex,   't-4'),
      assign(_empAlex,   't-5'),
      // Jordan — dining 11-15
      assign(_empJordan, 't-11'),
      assign(_empJordan, 't-12'),
      assign(_empJordan, 't-13'),
      assign(_empJordan, 't-14'),
      assign(_empJordan, 't-15'),
      // Taylor — round 21-23 + counter C1-C6
      assign(_empTaylor, 't-21'),
      assign(_empTaylor, 't-22'),
      assign(_empTaylor, 't-23'),
      assign(_empTaylor, 't-c1'),
      assign(_empTaylor, 't-c2'),
      assign(_empTaylor, 't-c3'),
      assign(_empTaylor, 't-c4'),
      assign(_empTaylor, 't-c5'),
      assign(_empTaylor, 't-c6'),
      // Casey — patio
      assign(_empCasey,  't-p1'),
      assign(_empCasey,  't-p2'),
      assign(_empCasey,  't-p3'),
      assign(_empCasey,  't-p4'),
      assign(_empCasey,  't-p5'),
      assign(_empCasey,  't-p6'),
    ];
  }

  // ── Guest tags ────────────────────────────────────────────────────────────

  // Official VIP tag guid from DefaultGuestTag enum in capman-host source.
  // Using this exact value makes the app render the built-in VIP styling.
  static const String _vipTagGuid = 'efea3d6a-9847-4beb-8bd3-964813bb32b8';

  // GuestTagDto schema confirmed from source: tagGuid, text, shortText,
  // description, icon (emoji string), type (DEFAULT | CUSTOM | AUTO).
  // The `icon` field is a literal emoji character — the UI renders it
  // verbatim. Sending name strings like "star" makes the badge show
  // the word "star" instead of the icon.
  List<Map<String, dynamic>> _guestTags() => [
        {
          'tagGuid': _vipTagGuid,
          'text': 'VIP',
          'shortText': 'VIP',
          'description': null,
          'icon': '👑',
          'type': 'DEFAULT',
        },
        {
          'tagGuid': 'tag-birthday',
          'text': 'Birthday',
          'shortText': 'BDAY',
          'description': null,
          'icon': '🎂',
          'type': 'CUSTOM',
        },
        {
          'tagGuid': 'tag-anniversary',
          'text': 'Anniversary',
          'shortText': 'ANN',
          'description': null,
          'icon': '💝',
          'type': 'CUSTOM',
        },
        {
          'tagGuid': 'tag-allergy',
          'text': 'Allergy',
          'shortText': 'ALRG',
          'description': null,
          'icon': '⚠️',
          'type': 'CUSTOM',
        },
      ];
}
