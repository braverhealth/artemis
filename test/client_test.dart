import 'package:artemis/client.dart';
import 'package:artemis/schema/graphql_query.dart';
import 'package:gql/ast.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_link/gql_link.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:test/test.dart';

class _NoVars extends JsonSerializable {
  _NoVars();
  @override
  Map<String, dynamic> toJson() => const {};
}

class _TestQuery extends GraphQLQuery<String, _NoVars> {
  _TestQuery(this._parse) {
    document = const DocumentNode(definitions: []);
  }

  final String Function(Map<String, dynamic>) _parse;

  @override
  String parse(Map<String, dynamic> json) => _parse(json);

  @override
  List<Object?> get props => const [];
}

/// Builds a [Link] that always responds with [response].
Link _linkReturning(Response response) =>
    Link.function((request, [forward]) => Stream.value(response));

Response _response({
  Map<String, dynamic>? data,
  List<GraphQLError>? errors,
}) =>
    Response(data: data, errors: errors, response: const {});

/// A parse function that mirrors the real-world failure: a non-nullable field
/// is missing from the payload and a `null` value gets cast to a `List`.
String _failingParse(Map<String, dynamic> json) {
  final value = json['missing'];
  return (value as List).first as String;
}

void main() {
  group('ArtemisClient.execute', () {
    test('returns parsed data on success', () async {
      final client = ArtemisClient.fromLink(
        _linkReturning(_response(data: const {'value': 'ok'})),
      );
      final query = _TestQuery((json) => json['value'] as String);

      final response = await client.execute(query);

      expect(response.data, 'ok');
      expect(response.hasErrors, isFalse);
    });

    test('returns null data when response.data is null', () async {
      final client = ArtemisClient.fromLink(_linkReturning(_response()));
      final query = _TestQuery(_failingParse);

      final response = await client.execute(query);

      expect(response.data, isNull);
      expect(response.hasErrors, isFalse);
    });

    test(
        'returns null data and preserves errors when parse fails on a '
        'partial response', () async {
      final errors = [
        const GraphQLError(message: 'Field is null', path: ['a', 'b']),
      ];
      final client = ArtemisClient.fromLink(
        _linkReturning(_response(data: const {}, errors: errors)),
      );
      final query = _TestQuery(_failingParse);

      final response = await client.execute(query);

      expect(response.data, isNull);
      expect(response.errors, same(errors));
      expect(response.hasErrors, isTrue);
    });

    test('rethrows parse failure when response has no errors', () async {
      final client = ArtemisClient.fromLink(
        _linkReturning(_response(data: const {})),
      );
      final query = _TestQuery(_failingParse);

      await expectLater(client.execute(query), throwsA(isA<TypeError>()));
    });
  });

  group('ArtemisClient.stream', () {
    test('emits parsed data on success', () async {
      final client = ArtemisClient.fromLink(
        _linkReturning(_response(data: const {'value': 'ok'})),
      );
      final query = _TestQuery((json) => json['value'] as String);

      final response = await client.stream(query).first;

      expect(response.data, 'ok');
      expect(response.hasErrors, isFalse);
    });

    test(
        'emits null data and preserves errors when parse fails on a '
        'partial response', () async {
      final errors = [
        const GraphQLError(message: 'Field is null'),
      ];
      final client = ArtemisClient.fromLink(
        _linkReturning(_response(data: const {}, errors: errors)),
      );
      final query = _TestQuery(_failingParse);

      final response = await client.stream(query).first;

      expect(response.data, isNull);
      expect(response.errors, same(errors));
    });

    test('propagates parse failure when response has no errors', () async {
      final client = ArtemisClient.fromLink(
        _linkReturning(_response(data: const {})),
      );
      final query = _TestQuery(_failingParse);

      await expectLater(client.stream(query).first, throwsA(isA<TypeError>()));
    });
  });
}
