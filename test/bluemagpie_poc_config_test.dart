import 'package:flutter_test/flutter_test.dart';
import 'package:geneapp/bluemagpie_poc_config.dart';

void main() {
  test('BlueMagpie PoC is disabled unless explicitly enabled', () {
    expect(BlueMagpiePocConfig.enabled, isFalse);
  });
}
