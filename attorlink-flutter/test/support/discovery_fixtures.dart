// Test-only responses; production always calls the configured Spring Boot API.
import 'dart:async';
import 'dart:convert';

import 'package:attorlink_flutter/core/config/api_config.dart';
import 'package:attorlink_flutter/core/network/api_client.dart';
import 'package:attorlink_flutter/core/network/http_transport.dart';
import 'package:attorlink_flutter/features/discovery/data/discovery_repository.dart';

Map<String, Object?> discoveryLawyer(int id, {String? name}) => {
  'id': id,
  'userId': id + 100,
  'fullName': name ?? 'Lawyer $id',
  'profilePhoto': null,
  'professionalTitle': 'Advocate',
  'bio': 'Public biography $id',
  'yearsOfExperience': 0,
  'practiceAreas': ['Family Law'],
  'updatedAt': '2026-11-04T12:30:00.123456',
};

Map<String, Object?> discoveryPage(
  List<Object?> content, {
  int page = 0,
  int size = 20,
  int? total,
  int pages = 1,
}) => {
  'content': content,
  'page': page,
  'size': size,
  'totalElements': total ?? content.length,
  'totalPages': pages,
};

TransportResponse discoveryResponse(Object? data, {int status = 200}) =>
    TransportResponse(
      statusCode: status,
      body: jsonEncode({
        'success': status == 200,
        'message': status == 200 ? 'Success' : 'Access denied',
        'data': data,
      }),
    );

class DiscoveryTransport implements HttpTransport {
  DiscoveryTransport(this.handler);
  final FutureOr<TransportResponse> Function(TransportRequest request) handler;
  final requests = <TransportRequest>[];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    return handler(request);
  }

  @override
  void close() {}
}

DiscoveryRepository discoveryRepository(DiscoveryTransport transport) =>
    DiscoveryRepository(
      ApiClient(
        config: ApiConfig(baseUrl: Uri.parse('https://example.test/api/v1/')),
        transport: transport,
      ),
    );
