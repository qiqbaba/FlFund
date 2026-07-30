import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('proxy socket exception', () async {
    final client = HttpClient();
    client.findProxy = (uri) => 'PROXY 127.0.0.1:8073';
    try {
      final req = await client.getUrl(Uri.parse('https://open.bigmodel.cn/api/paas/v4'));
      await req.close();
    } catch (e) {
      // ignore: avoid_print
      print('EXCEPTION: $e');
    }
  });
}
