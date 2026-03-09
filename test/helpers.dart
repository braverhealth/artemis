import 'package:artemis/builder.dart';
import 'package:artemis/generator/data/data.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:dart_style/dart_style.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:collection/collection.dart';

final bool Function(Iterable, Iterable) listEquals =
    const DeepCollectionEquality.unordered().equals;

final DartFormatter _dartFormatter = DartFormatter(
  languageVersion: DartFormatter.latestLanguageVersion,
);

String normalizeGeneratedDart(String source) => _dartFormatter.format(source);

void expectDartCode(String actual, String expected) {
  expect(normalizeGeneratedDart(actual), normalizeGeneratedDart(expected));
}

LibraryDefinition normalizeLibraryDefinition(LibraryDefinition definition) {
  final queries = definition.queries
      .map(normalizeQueryDefinition)
      .toList()
    ..sort((a, b) {
      final operationComparison =
          a.operationName.compareTo(b.operationName);
      if (operationComparison != 0) {
        return operationComparison;
      }

      return a.name.name.compareTo(b.name.name);
    });

  final customImports = definition.customImports.toList()..sort();

  return LibraryDefinition(
    basename: definition.basename,
    queries: queries,
    customImports: customImports,
  );
}

QueryDefinition normalizeQueryDefinition(QueryDefinition definition) {
  return QueryDefinition(
    name: definition.name,
    operationName: definition.operationName,
    document: definition.document,
    classes: definition.classes,
    inputs: definition.inputs,
    generateHelpers: definition.generateHelpers,
    generateQueries: definition.generateQueries,
    suffix: definition.suffix,
  );
}

Object _normalizeOutput(String assetPath, Object output) {
  if (output is String && assetPath.endsWith('.dart')) {
    return normalizeGeneratedDart(output);
  }

  return output;
}

Future<void> expectBuilderLogsError({
  required Builder builder,
  required Map<String, Object> sourceAssets,
  required Matcher messageMatcher,
  Map<String, Object> outputs = const {},
}) async {
  final logMessages = <String>[];

  await testBuilder(
    builder,
    sourceAssets,
    outputs: outputs,
    onLog: (record) => logMessages.add(record.message),
  );

  expect(logMessages.join('\n'), messageMatcher);
}

Future testGenerator({
  required String query,
  required LibraryDefinition libraryDefinition,
  required String generatedFile,
  required String schema,
  String namingScheme = 'pathedWithTypes',
  bool appendTypeName = false,
  bool generateHelpers = false,
  bool generateQueries = false,
  Map<String, dynamic> builderOptionsMap = const {},
  Map<String, Object> sourceAssetsMap = const {},
  Map<String, Object> outputsMap = const {},
}) async {
  Logger.root.level = Level.INFO;

  final anotherBuilder = graphQLQueryBuilder(BuilderOptions({
    if (!generateHelpers) 'generate_helpers': false,
    if (!generateQueries) 'generate_queries': false,
    'schema_mapping': [
      {
        'schema': 'api.schema.graphql',
        'queries_glob': 'queries/**.graphql',
        'output': 'lib/query.graphql.dart',
        'naming_scheme': namingScheme,
        'append_type_name': appendTypeName,
      }
    ],
    ...builderOptionsMap,
  }));

  anotherBuilder.onBuild = expectAsync1((definition) {
    log.fine(definition);
    expect(
      normalizeLibraryDefinition(definition),
      normalizeLibraryDefinition(libraryDefinition),
    );
  }, count: 1);

  final expectedOutputs = {
    'a|lib/query.graphql.dart': generatedFile,
    ...outputsMap,
  }.map((assetPath, output) =>
      MapEntry(assetPath, _normalizeOutput(assetPath, output)));

  return await testBuilder(
    anotherBuilder,
    {
      'a|api.schema.graphql': schema,
      'a|queries/query.graphql': query,
      ...sourceAssetsMap,
    },
    outputs: expectedOutputs,
    onLog: print,
  );
}

Future testNaming({
  required String query,
  required String schema,
  required List<String> expectedNames,
  required String namingScheme,
  bool shouldFail = false,
}) {
  final anotherBuilder = graphQLQueryBuilder(BuilderOptions({
    'generate_helpers': false,
    'generate_queries': false,
    'schema_mapping': [
      {
        'schema': 'api.schema.graphql',
        'queries_glob': 'queries/**.graphql',
        'output': 'lib/query.dart',
        'naming_scheme': namingScheme,
      }
    ],
  }));

  if (!shouldFail) {
    anotherBuilder.onBuild = expectAsync1((definition) {
      final names = definition.queries.first.classes
          .map((e) => e.name.namePrintable)
          .toSet();
      log.fine(names);
      expect(names.toSet(), equals(expectedNames.toSet()));
    }, count: 1);
  }

  return testBuilder(
    anotherBuilder,
    {
      'a|api.schema.graphql': schema,
      'a|queries/query.graphql': query,
    },
    onLog: print,
  );
}
