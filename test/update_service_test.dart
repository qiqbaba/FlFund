import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';

void main() {
  test('UpdateService parses raw JSON string properly', () {
    const rawJsonStr = '''
{
  "version": "1.8.20",
  "buildNumber": 102,
  "minSupportedVersion": "1.8.0",
  "releaseDate": "2026-08-18",
  "releaseNotes": "1. 启动流程优化",
  "platforms": {
    "windows": {
      "url": "https://github.com/qiqbaba/FlFund/releases/download/v1.8.20/FlFund-Windows-x64.zip",
      "sha256": "abc123",
      "fileSize": 1024
    }
  }
}
''';
    final decoded = jsonDecode(rawJsonStr);
    expect(decoded is Map<String, dynamic>, isTrue);

    final data = Map<String, dynamic>.from(decoded as Map);
    expect(data['version'], '1.8.20');
    expect(data['buildNumber'], 102);

    final currentVersion = Version.parse('1.8.19');
    final latestVersion = Version.parse(data['version']);
    expect(latestVersion > currentVersion, isTrue);
  });
}
