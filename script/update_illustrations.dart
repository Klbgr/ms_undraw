import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_logging.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';
import 'package:yamlicious/yamlicious.dart';

part 'model.dart';

void main(List<String> args) async {
  final _illustrations = await _getIllustrations();
  final _enumList = _getEnuns(_illustrations);
  final _baseUrl =
      'https://42f2671d685f51e10fc6-b9fcecea3e50b3b59bdc28dead054ebc.ssl.cf5.rackcdn.com/illustrations';
  final _identifierAndUrl = _getIdentifierAndUrl(_illustrations);
  await _updateFile(_enumList, _baseUrl, _identifierAndUrl);

  logger.stdout('Formatting file');
  await Process.run(
      'dartfmt.bat', ['-w', '--fix', '.\\lib\\illustrations.g.dart']);
  logger.stdout('File formatted');

  if (args.contains('--publish') && await _hasChanges()) {
    await _updateLibraryVersion();
    await _commitChanges();
    await _pushingChanges();
    await _updateLibrary();
  }
}

Future<bool> _hasChanges() async {
  var gitStatusOutput = await Process.run('git', ['status']);
  return !gitStatusOutput.stdout
      .toString()
      .contains('nothing to commit, working tree clean');
}

_updateLibraryVersion() async {
  final pubspec = File('./pubspec.yaml');
  var doc = Map.from(loadYaml(await pubspec.readAsString()));
  doc['version'] = (doc['version'] as String).split('+')[0] +
      '+' +
      (int.parse((doc['version'] as String).split('+')[1]) + 1).toString();
  pubspec.writeAsString(toYamlString(doc));
  final changelog = File('./changelog.md');
  var list = await changelog.readAsLines();
  changelog.writeAsString([
    list.removeAt(0),
    ...[
      '',
      '## [${doc['version']}] - ${DateTime.now().toIso8601String().split('T')[0]}',
      '',
      '* More illustrations added or updated',
    ],
    ...list
  ].join('\n'));
}

_updateLibrary() async {
  await Process.run(
    'pub',
    ['publish'],
  );
}

_pushingChanges() async {
  await Process.run(
    'git',
    ['push', 'origin', 'master'],
  );
}

_commitChanges() async {
  await Process.run(
    'git',
    ['commit', '-a', '-m', 'update undraw illustrations'],
  );
}

Logger logger = Logger.standard();
final _startNum = RegExp(r"^\d");

List<String> _getEnuns(List<IllustrationElement> illustrations) {
  logger.stdout('Transforming enums');

  final list = (illustrations..sort((ia, ib) => ia.title.compareTo(ib.title)))
      .map((illustration) {
    return '''
/// Title: ${illustration.title}
/// <br/>
/// <img src="${illustration.image}" alt="${illustration.title}" width="200"/>
${_kebabCase(illustration.title)}''';
  }).toList();

  logger.stdout('Enums transformed');
  return list;
}

List<String> _getIdentifierAndUrl(List<IllustrationElement> illustrations) {
  logger.stdout('Transforming illustrations');
  final list = illustrations
      .map((ill) =>
          "UnDrawIllustration.${_kebabCase(ill.title)}: '\$baseUrl/${ill.image.split('/').last}'")
      .toList();
  logger.stdout('Illustrations transformed');
  return list;
}

Future<List<IllustrationElement>> _getIllustrations() async {
  final progress = logger.progress('Downloading undraw illustration list');
  var _isEnd = false;
  var _page = 0;
  List<IllustrationElement> _illustrations = [];
  do {
    logger.stdout('Downloading page $_page');
    final http.Response response =
        await http.get("https://undraw.co/api/illustrations?page=$_page");
    final illustrations = Illustration.fromMap(jsonDecode(response.body));
    _isEnd = illustrations.hasMore;
    _page = illustrations.nextPage;
    _illustrations.addAll(illustrations.illustrations);
  } while (_isEnd);
  progress.finish(
      message: '${_illustrations.length} undraw illustration list downloaded',
      showTiming: true);
  return _illustrations;
}

String _kebabCase(String value) => value
    .toLowerCase()
    .trim()
    .replaceAll(' ', '_')
    .replaceAll('-', '_')
    .replaceAllMapped(_startNum, (match) => '_${match.group(0)}')
    .replaceFirst('void', 'void_');

Future _updateFile(
    List<String> enuns, String baseUrl, List<String> identifierAndUrl) async {
  logger.stdout('Writing in file');
  final File _illustrations = File('./lib/illustrations.g.dart');
  final content = '''
// ignore_for_file: unused_field
/// Enums to help locate the correct illustration
enum UnDrawIllustration {${enuns.join(',')}}

/// Base url for the illustrations
const baseUrl = "$baseUrl";

/// Map of illustrations with url to download
const illustrationMap = const <UnDrawIllustration, String>{
  ${identifierAndUrl.join(',')}
};

''';
  if (!await _illustrations.exists())
    await _illustrations.create(recursive: true);
  await _illustrations.writeAsString(content,
      encoding: Encoding.getByName('utf-8'));
  logger.stdout('File writed');
}
