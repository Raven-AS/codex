import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../client/domain/client_models.dart';
import '../domain/discovery_models.dart';

class DiscoveryRepository {
  const DiscoveryRepository(this.api);
  final ApiClient api;

  // Both endpoints are public GETs. Do not send an owner's bearer or trigger
  // session rotation, and leave visibility/eligibility decisions to the server.
  Future<List<ReferenceItem>> practiceAreas() async =>
      (await api.request('GET', 'practice-areas', decode: referenceList)).data;

  Future<ApiPage<DiscoveredLawyer>> search({
    String search = '',
    int? practiceAreaId,
    int page = 0,
    int size = 20,
  }) async {
    if (page < 0 ||
        size <= 0 ||
        (practiceAreaId != null && practiceAreaId <= 0)) {
      throw const ApiException(
        kind: ApiErrorKind.validation,
        message: 'Page, page size, and practice area must be valid.',
      );
    }
    final safeSize = size > 50 ? 50 : size;
    final name = search.trim();
    return (await api.request(
      'GET',
      'lawyers/discover',
      query: {
        if (name.isNotEmpty) 'search': name,
        if (practiceAreaId != null) 'practiceAreaId': '$practiceAreaId',
        'page': '$page',
        'size': '$safeSize',
      },
      decode: (value) {
        final result = ApiPage.fromJson(value, DiscoveredLawyer.fromJson);
        if (result.page != page ||
            result.size != safeSize ||
            result.content.length > result.size) {
          throw const FormatException('Unexpected discovery page');
        }
        return result;
      },
    )).data;
  }
}
