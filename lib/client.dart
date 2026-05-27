import 'dart:async';

import 'package:gql_dedupe_link/gql_dedupe_link.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:gql_http_link/gql_http_link.dart';
import 'package:gql_link/gql_link.dart';
import 'package:http/http.dart' as http;
import 'package:json_annotation/json_annotation.dart';

import './schema/graphql_query.dart';
import './schema/graphql_response.dart';

/// Used to execute a GraphQL query or mutation and return its typed response.
///
/// A [Link] is used as the network interface.
class ArtemisClient {
  HttpLink? _httpLink;
  final Link _link;

  /// Instantiate an [ArtemisClient].
  ///
  /// [DedupeLink] and [HttpLink] are included.
  /// To use different [Link] create an [ArtemisClient] with [ArtemisClient.fromLink].
  factory ArtemisClient(
    String graphQLEndpoint, {
    http.Client? httpClient,
  }) {
    final httpLink = HttpLink(
      graphQLEndpoint,
      httpClient: httpClient,
    );
    return ArtemisClient.fromLink(
      Link.from([
        DedupeLink(),
        httpLink,
      ]),
    ).._httpLink = httpLink;
  }

  /// Create an [ArtemisClient] from [Link].
  ArtemisClient.fromLink(this._link);

  /// Executes a [GraphQLQuery], returning a typed response.
  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Context context = const Context(),
  }) async {
    final request = Request(
      operation: Operation(
        document: query.document,
        operationName: query.operationName,
      ),
      variables: query.getVariablesMap(),
      context: context,
    );

    final response = await _link.request(request).first;

    return GraphQLResponse<T>(
      data: _tryParse(query, response),
      errors: response.errors,
      context: response.context,
    );
  }

  /// Streams a [GraphQLQuery], returning a typed response stream.
  Stream<GraphQLResponse<T>> stream<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Context context = const Context(),
  }) {
    final request = Request(
      operation: Operation(
        document: query.document,
        operationName: query.operationName,
      ),
      variables: query.getVariablesMap(),
      context: context,
    );

    return _link.request(request).map((response) => GraphQLResponse<T>(
          data: _tryParse(query, response),
          errors: response.errors,
          context: response.context,
        ));
  }

  /// Parse [response] using [query]. If parsing throws while the server
  /// returned a non-empty [Response.errors] list, the failure is treated as a
  /// partial response (non-nullable typed model can't be built from the
  /// returned shape) and `null` is returned. Otherwise the error rethrows.
  static T? _tryParse<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query,
    Response response,
  ) {
    if (response.data == null) return null;
    try {
      return query.parse(response.data ?? {});
    } catch (_) {
      if (response.errors != null && response.errors!.isNotEmpty) return null;
      rethrow;
    }
  }

  /// Close the inline [http.Client].
  ///
  /// Keep in mind this will not close clients whose Artemis client
  /// was instantiated from [ArtemisClient.fromLink]. If you're using
  /// this constructor, you need to close your own links.
  void dispose() {
    _httpLink?.dispose();
  }
}
