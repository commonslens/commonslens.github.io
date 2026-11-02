import 'package:commonslens_core/commonslens_core.dart';
import 'package:test/test.dart';

void main() {
  test('stores and emits only categorized URL and status text', () {
    final lines = <String>[];
    final logger = WikimediaRequestLogger(sink: lines.add);
    final uri = Uri.parse('https://commons.wikimedia.org/w/api.php?x=1');

    logger.record(WikimediaRequestCategory.thumbnail, uri, '200');
    logger.record(WikimediaRequestCategory.autocomplete, uri, '503');

    expect(lines, [
      '[THUMBNAIL] $uri 200',
      '[AUTOCOMPLETE] $uri 503',
    ]);
    expect(logger.text, lines.join('\n'));
    expect(logger.grouped[WikimediaRequestCategory.thumbnail], hasLength(1));
    expect(
      logger.grouped[WikimediaRequestCategory.autocomplete]!.single.status,
      '503',
    );
  });
}
