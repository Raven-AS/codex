import 'dart:typed_data';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../calls/domain/call_models.dart' show callLocalTime;
import '../../lawyer/data/lawyer_repository.dart';
import '../domain/boost_models.dart';

class BoostRepository {
  BoostRepository(this.lawyer, {this.accessChanges});
  final LawyerRepository lawyer;
  final Stream<Object?>? accessChanges;
  void checkAccess() => lawyer.checkAccess();
  Future<T> _guard<T>(Future<T> Function() action) async {
    checkAccess();
    final result = await action();
    checkAccess();
    return result;
  }

  BoostData _decode(Object? value, BoostDto kind, {int? id}) {
    final result = BoostData.fromJson(value, kind);
    if ((id != null && result.id != id) ||
        (kind == BoostDto.monitoring &&
            result.fields['lawyerId'] != lawyer.ownerId)) {
      throw const FormatException('Unexpected boost owner or identifier');
    }
    return result;
  }

  Future<BoostData> _get(
    String path,
    BoostDto kind, {
    int? id,
    Map<String, String>? query,
  }) => _guard(
    () async => (await lawyer.api.request(
      'GET',
      path,
      authenticated: true,
      accessGuard: checkAccess,
      query: query,
      decode: (v) => _decode(v, kind, id: id),
    )).data,
  );
  Future<List<BoostData>> _list(
    String path,
    BoostDto kind, {
    Map<String, String>? query,
  }) => _guard(
    () async => (await lawyer.api.request(
      'GET',
      path,
      authenticated: true,
      accessGuard: checkAccess,
      query: query,
      decode: (v) {
        if (v is! List) throw const FormatException('Expected a list');
        return v.map((row) => _decode(row, kind)).toList();
      },
    )).data,
  );
  Future<ApiPage<BoostData>> _page(
    String path,
    BoostDto kind,
    int page, {
    Map<String, String>? query,
  }) => _guard(() async {
    if (page < 0) throw ArgumentError.value(page);
    return (await lawyer.api.request(
      'GET',
      path,
      authenticated: true,
      accessGuard: checkAccess,
      query: {'page': '$page', 'size': '20', ...?query},
      decode: (v) {
        final result = ApiPage.fromJson(v, (row) => _decode(row, kind));
        if (result.page != page || result.size != 20) {
          throw const FormatException('Unexpected boost page');
        }
        return result;
      },
    )).data;
  });
  Future<List<BoostData>> plans() => _list('lawyer/boost-plans', BoostDto.plan);
  Future<bool> verified() async =>
      (await lawyer.profile()).text('profileStatus') == 'VERIFIED';
  Future<BoostData> purchase(int planId) => _guard(() async {
    if (planId <= 0) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Choose a valid plan.',
      );
    }
    if (!await verified()) {
      throw const ApiException(
        kind: ApiErrorKind.forbidden,
        message: 'Only verified lawyers can purchase boosts.',
      );
    }
    checkAccess();
    return (await lawyer.api.request(
      'POST',
      'lawyer/boosts/purchase',
      authenticated: true,
      accessGuard: checkAccess,
      body: {'planId': planId},
      decode: (v) => _decode(v, BoostDto.purchase),
    )).data;
  });
  Future<ApiPage<BoostData>> history({int page = 0}) =>
      _page('lawyer/boosts', BoostDto.monitoring, page);
  Future<BoostData> detail(int id) =>
      _get('lawyer/boosts/$id', BoostDto.monitoring, id: id);
  Future<BoostData> checkout(int id) =>
      _get('lawyer/boosts/$id/sandbox-checkout', BoostDto.checkout, id: id);
  Future<ApiPage<BoostData>> activities(int id, {int page = 0}) =>
      _page('lawyer/boosts/$id/activities', BoostDto.activity, page);
  Future<List<BoostData>> invoices() =>
      _list('lawyer/boosts/invoices', BoostDto.invoice);
  Future<BoostData> invoice(int id) =>
      _get('lawyer/boosts/invoices/$id', BoostDto.invoice, id: id);
  Future<Uint8List> invoicePdf(int id) => _guard(
    () => lawyer.api.downloadPdf(
      'lawyer/boosts/invoices/$id/download',
      accessGuard: checkAccess,
    ),
  );
  Map<String, String> _range(String from, String to) {
    final f = from.trim().isEmpty ? null : callLocalTime(from.trim());
    final t = to.trim().isEmpty ? null : callLocalTime(to.trim());
    if (f != null && t != null) {
      String canonical(String v) => v.contains('.')
          ? '${v.split('.').first}.${v.split('.').last.padRight(9, '0')}'
          : '$v.000000000';
      if (canonical(f).compareTo(canonical(t)) >= 0) {
        throw const FormatException('From must be before To.');
      }
    }
    return {'from': ?f, 'to': ?t};
  }

  Future<BoostData> summary({int? boostId, String from = '', String to = ''}) =>
      _get(
        boostId == null
            ? 'lawyer/boosts/analytics/summary'
            : 'lawyer/boosts/$boostId/analytics',
        BoostDto.summary,
        query: _range(from, to),
      );
  Future<ApiPage<BoostData>> daily({
    int page = 0,
    String from = '',
    String to = '',
  }) => _page(
    'lawyer/boosts/analytics/daily',
    BoostDto.daily,
    page,
    query: _range(from, to),
  );
  Future<List<BoostData>> boostDaily(
    int id, {
    String from = '',
    String to = '',
  }) => _guard(() async {
    final query = _range(from, to);
    // The daily endpoint currently lacks its own ownership assertion. Require
    // the server's owned-detail check first; this does not repair that API gap.
    await detail(id);
    return _list(
      'lawyer/boosts/$id/analytics/daily',
      BoostDto.daily,
      query: query,
    );
  });
}
