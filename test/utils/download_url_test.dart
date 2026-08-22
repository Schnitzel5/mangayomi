import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/modules/manga/download/providers/download_provider.dart';

void main() {
  test('classifies m3u8 URLs by path', () {
    expect(
      isM3u8Url('https://example.com/playlist.m3u8?token=abc#segment'),
      isTrue,
    );
    expect(isM3u8Url('https://example.com/video.mp4?format=.m3u8'), isFalse);
  });
}
