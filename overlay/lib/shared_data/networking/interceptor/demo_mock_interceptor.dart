import 'package:capman_host/di/env.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@LazySingleton()
@demo
class DemoMockInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method.toUpperCase();
    final path = options.uri.path;
    // ignore: avoid_print
    print('[DemoMock] $method $path');
    final data = _respond(method, path);
    handler.resolve(Response(
      requestOptions: options,
      data: data,
      statusCode: 200,
      statusMessage: 'OK',
    ));
  }

  dynamic _respond(String method, String path) {
    if (path.contains('oauth/token')) return _authToken();
    if (method == 'GET' && path.endsWith('/restaurants/v1/restaurants')) return [_restaurant()];
    if (method == 'GET' && path.contains('/restaurants/v1/restaurants/')) return _restaurant();
    if (path.contains('managementGroups')) return [{'guid': 'demo-group-1', 'name': 'Demo Group'}];
    if (method == 'GET' && path.contains('serviceAreas')) return _serviceAreas();
    if (method == 'GET' && path.endsWith('/bookings')) return _bookings();
    if (method == 'POST' && path.endsWith('/bookings')) return {'guid': 'booking-${DateTime.now().millisecondsSinceEpoch}'};
    if (method == 'PATCH' && path.contains('/bookings/')) return {'guid': path.split('/').last};
    if (method == 'DELETE' && path.contains('/bookings/')) return {'success': true};
    if (method == 'GET' && path.contains('/servers')) return _servers();
    if (method == 'GET' && path.contains('/schedule')) return _schedule();
    if (path.contains('smsThreads') || path.contains('experiences')) return <dynamic>[];
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

  // ── Restaurant ────────────────────────────────────────────────────────────

  Map<String, dynamic> _restaurant() => {
        'guid': 'demo-restaurant-guid-1234',
        'name': 'The Demo Kitchen',
        'address': {
          'address1': '123 Main St',
          'city': 'Boston',
          'state': 'MA',
          'zip': '02101',
        },
        'phone': '617-555-0100',
        'timeZone': 'America/New_York',
        'currency': 'USD',
        'features': {
          'reservationsEnabled': true,
          'waitlistEnabled': true,
        },
      };

  // ── Service Areas & Tables ────────────────────────────────────────────────

  List<Map<String, dynamic>> _serviceAreas() => [
        {
          'guid': 'area-main',
          'name': 'Main Dining',
          'tables': _tables('main', 10),
        },
        {
          'guid': 'area-bar',
          'name': 'Bar',
          'tables': _tables('bar', 4),
        },
        {
          'guid': 'area-patio',
          'name': 'Patio',
          'tables': _tables('patio', 6),
        },
      ];

  List<Map<String, dynamic>> _tables(String prefix, int count) =>
      List.generate(count, (i) => {
            'guid': 'table-$prefix-${i + 1}',
            'name': '${i + 1}',
            'minPartySize': 1,
            'maxPartySize': prefix == 'bar' ? 2 : 6,
            'shape': 'RECTANGLE',
            'x': (i % 5) * 120,
            'y': (i ~/ 5) * 120,
            'width': 80,
            'height': 80,
          });

  // ── Bookings ──────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _bookings() {
    final now = DateTime.now();
    final names = ['Johnson', 'Smith', 'Williams', 'Brown', 'Garcia', 'Martinez', 'Davis', 'Wilson', 'Anderson', 'Taylor'];
    final partySizes = [4, 2, 3, 6, 2, 4, 3, 2, 5, 3];

    final reservations = List.generate(6, (i) => {
          'guid': 'res-${i + 1}',
          'type': 'RESERVATION',
          'status': i < 2 ? 'SEATED' : 'CONFIRMED',
          'guestName': names[i],
          'partySize': partySizes[i],
          'estimatedArrivalTime': i < 2
              ? now.subtract(Duration(minutes: 15 + i * 10)).toIso8601String()
              : now.add(Duration(minutes: i * 15)).toIso8601String(),
          'serviceAreaGuid': 'area-main',
          'tableGuids': i < 2 ? ['table-main-${i + 1}'] : <String>[],
          'phone': '617-555-01${i.toString().padLeft(2, '0')}',
          'notes': i == 1 ? 'Anniversary dinner' : '',
          'createdDate': now.subtract(Duration(minutes: 60 + i * 30)).toIso8601String(),
        });

    final waitlist = List.generate(4, (i) => {
          'guid': 'wait-${i + 1}',
          'type': 'WAITLIST',
          'status': 'WAITING',
          'guestName': names[i + 6],
          'partySize': partySizes[i + 6],
          'quotedWaitTime': (i + 1) * 10,
          'addedTime': now.subtract(Duration(minutes: 5 + i * 8)).toIso8601String(),
          'phone': '617-555-02${i.toString().padLeft(2, '0')}',
          'notes': '',
          'createdDate': now.subtract(Duration(minutes: 5 + i * 8)).toIso8601String(),
        });

    return [...reservations, ...waitlist];
  }

  // ── Servers ───────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _servers() => [
        {'guid': 'server-1', 'name': 'Alex', 'tableGuids': ['table-main-1', 'table-main-2']},
        {'guid': 'server-2', 'name': 'Jordan', 'tableGuids': ['table-main-3', 'table-main-4']},
        {'guid': 'server-3', 'name': 'Casey', 'tableGuids': ['table-bar-1', 'table-bar-2']},
      ];

  // ── Schedule ──────────────────────────────────────────────────────────────

  Map<String, dynamic> _schedule() {
    final now = DateTime.now();
    return {
      'shifts': [
        {
          'guid': 'shift-1',
          'name': 'Dinner Service',
          'startTime': now.subtract(const Duration(minutes: 60)).toIso8601String(),
          'endTime': now.add(const Duration(minutes: 180)).toIso8601String(),
          'reservationInterval': 15,
          'maxCovers': 80,
        },
      ],
    };
  }
}
