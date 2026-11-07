import '../../auth/domain/auth_models.dart' show jsonObject;

const boostStatuses = [
  'PENDING_PAYMENT',
  'SCHEDULED',
  'ACTIVE',
  'EXPIRED',
  'CANCELLED',
  'SUSPENDED',
];
const paymentStatuses = [
  'INITIATED',
  'PENDING',
  'COMPLETED',
  'FAILED',
  'CANCELLED',
];
const invoiceStatuses = ['DRAFT', 'ISSUED', 'PAID', 'VOID'];
const activityTypes = [
  'CREATED',
  'PAYMENT_INITIATED',
  'PAYMENT_COMPLETED',
  'PAYMENT_VERIFIED',
  'INVOICE_GENERATED',
  'INVOICE_GENERATION_FAILED',
  'BOOST_ACTIVATED',
  'BOOST_SCHEDULED',
  'BOOST_EXPIRED',
  'BOOST_CANCELLED',
  'BOOST_SUSPENDED',
  'AUTO_ACTIVATED',
  'SCHEDULED',
  'EXPIRED',
  'INVOICE_ISSUED',
  'FAILED',
  'CANCELLED',
];

enum BoostDto {
  plan,
  purchase,
  monitoring,
  activity,
  invoice,
  summary,
  daily,
  checkout,
}

/// Separate exact response shapes; no locally inferred payment/activation state.
class BoostData {
  BoostData.fromJson(Object? value, this.kind) {
    final json = jsonObject(value);
    final required = switch (kind) {
      BoostDto.plan => ['id', 'name', 'durationDays', 'price', 'currency'],
      BoostDto.purchase => [
        'boostId',
        'paymentId',
        'planName',
        'durationDays',
        'amount',
        'currency',
        'boostStatus',
        'paymentStatus',
      ],
      BoostDto.monitoring => [
        'boostId',
        'lawyerId',
        'planName',
        'durationDays',
        'amount',
        'currency',
        'boostStatus',
      ],
      BoostDto.activity => ['id', 'activityType'],
      BoostDto.invoice => [
        'id',
        'invoiceNumber',
        'status',
        'amount',
        'currency',
      ],
      BoostDto.summary => [
        'impressions',
        'uniqueReach',
        'profileVisits',
        'likes',
        'comments',
        'shares',
        'engagementRate',
      ],
      BoostDto.daily => [
        'date',
        'impressions',
        'uniqueReach',
        'profileVisits',
        'likes',
        'comments',
        'shares',
        'engagementRate',
      ],
      BoostDto.checkout => [
        'boostId',
        'paymentId',
        'planName',
        'amount',
        'currency',
        'sandboxDemoUrl',
        'paymentStatus',
        'paymentNote',
      ],
    };
    for (final key in required) {
      if (json[key] == null) throw FormatException('Missing $key');
    }
    for (final key in ['id', 'boostId', 'paymentId', 'lawyerId', 'invoiceId']) {
      if (json[key] != null && (json[key] is! int || (json[key] as int) <= 0)) {
        throw FormatException('Invalid $key');
      }
    }
    for (final key in [
      'durationDays',
      'impressions',
      'uniqueReach',
      'profileVisits',
      'likes',
      'comments',
      'shares',
    ]) {
      if (json[key] != null && (json[key] is! int || (json[key] as int) < 0)) {
        throw FormatException('Invalid $key');
      }
    }
    for (final key in ['amount', 'price', 'engagementRate']) {
      final n = json[key];
      if (n != null && (n is! num || !n.isFinite || n < 0)) {
        throw FormatException('Invalid $key');
      }
    }
    final enums = {
      'boostStatus': boostStatuses,
      'paymentStatus': paymentStatuses,
      'invoiceStatus': invoiceStatuses,
      if (kind == BoostDto.invoice) 'status': invoiceStatuses,
      if (kind == BoostDto.summary) 'status': boostStatuses,
      'activityType': activityTypes,
    };
    for (final entry in enums.entries) {
      if (json[entry.key] != null && !entry.value.contains(json[entry.key])) {
        throw FormatException('Invalid ${entry.key}');
      }
    }
    final keys = switch (kind) {
      BoostDto.plan => [
        'id',
        'name',
        'description',
        'durationDays',
        'price',
        'currency',
      ],
      BoostDto.purchase => [
        'boostId',
        'paymentId',
        'planName',
        'durationDays',
        'amount',
        'currency',
        'boostStatus',
        'paymentStatus',
        'createdAt',
      ],
      BoostDto.monitoring => [
        'boostId',
        'lawyerId',
        'lawyerName',
        'paymentId',
        'paymentReference',
        'paymentStatus',
        'planName',
        'durationDays',
        'amount',
        'currency',
        'boostStatus',
        'startsAt',
        'endsAt',
        'activatedAt',
        'expiredAt',
        'createdAt',
        'updatedAt',
        'invoiceId',
        'invoiceNumber',
        'invoiceStatus',
      ],
      BoostDto.activity => ['id', 'activityType', 'description', 'createdAt'],
      BoostDto.invoice => [
        'id',
        'boostId',
        'paymentId',
        'invoiceNumber',
        'status',
        'planName',
        'durationDays',
        'amount',
        'currency',
        'issuedAt',
        'pdfUrl',
      ],
      BoostDto.summary => [
        'boostId',
        'packageName',
        'status',
        'startsAt',
        'endsAt',
        'impressions',
        'uniqueReach',
        'profileVisits',
        'likes',
        'comments',
        'shares',
        'engagementRate',
        'from',
        'to',
      ],
      BoostDto.daily => [
        'date',
        'impressions',
        'uniqueReach',
        'profileVisits',
        'likes',
        'comments',
        'shares',
        'engagementRate',
      ],
      BoostDto.checkout => [
        'boostId',
        'paymentId',
        'planName',
        'amount',
        'currency',
        'sandboxDemoUrl',
        'paymentStatus',
        'paymentNote',
        'createdAt',
      ],
    };
    for (final key in keys) {
      if (![
            'id',
            'boostId',
            'lawyerId',
            'paymentId',
            'invoiceId',
            'durationDays',
            'price',
            'amount',
            'engagementRate',
            'impressions',
            'uniqueReach',
            'profileVisits',
            'likes',
            'comments',
            'shares',
          ].contains(key) &&
          json[key] != null &&
          json[key] is! String) {
        throw FormatException('Invalid $key');
      }
    }
    fields = Map.unmodifiable({
      for (final key in keys)
        if (json[key] != null) key: json[key],
    });
    if (kind == BoostDto.checkout) {
      checkoutUri(fields['sandboxDemoUrl'] as String);
    }
  }
  final BoostDto kind;
  late final Map<String, dynamic> fields;
  int get id =>
      fields[kind == BoostDto.monitoring ||
                  kind == BoostDto.purchase ||
                  kind == BoostDto.checkout
              ? 'boostId'
              : 'id']
          as int;
  String text(String key) => fields[key]?.toString() ?? 'Not provided';
  bool get pending =>
      fields['boostStatus'] == 'PENDING_PAYMENT' &&
      fields['paymentStatus'] != 'COMPLETED';
}

Uri checkoutUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Invalid sandbox checkout URL');
  }
  return uri;
}
