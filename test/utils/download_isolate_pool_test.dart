import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/services/download_manager/download_isolate_pool.dart';

void main() {
  group('isLocalVideoProxyUrl', () {
    test('recognizes loopback video proxy URLs', () {
      expect(
        isLocalVideoProxyUrl(
          'http://localhost:8765/video/token?source=upstream#part',
        ),
        isTrue,
      );
      expect(isLocalVideoProxyUrl('http://127.0.0.1/video/token'), isTrue);
      expect(isLocalVideoProxyUrl('http://[::1]:8765/video/token'), isTrue);
    });

    test('rejects non-proxy hosts and paths', () {
      expect(isLocalVideoProxyUrl('https://example.com/video/token'), isFalse);
      expect(isLocalVideoProxyUrl('http://localhost/video'), isFalse);
      expect(isLocalVideoProxyUrl('http://localhost/videos/token'), isFalse);
    });
  });
}
