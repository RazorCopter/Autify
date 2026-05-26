import 'dart:io';

void main() {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('Errore: pubspec.yaml non trovato.');
    exit(1);
  }

  final lines = pubspecFile.readAsLinesSync();
  String? versionLine;
  for (final line in lines) {
    if (line.trim().startsWith('version:')) {
      versionLine = line;
      break;
    }
  }

  if (versionLine == null) {
    print('Errore: campo version non trovato in pubspec.yaml.');
    exit(1);
  }

  // Estrae la versione (es: 2.10.0+1 -> 2.10.0)
  final versionPart = versionLine.split(':').last.trim();
  final version = versionPart.split('+').first;

  final versionFile = File('lib/app_version.dart');
  versionFile.writeAsStringSync("const String kFrontendVersion = '$version';\n");
  print('Versione allineata con successo a $version in lib/app_version.dart');
}
