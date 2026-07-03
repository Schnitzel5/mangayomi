import 'dart:convert';
import 'package:mangayomi/eval/javascript/http.dart';
import 'package:mangayomi/eval/lib.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/models/source.dart';
import 'package:mangayomi/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'headers.g.dart';

/// Headers are static per source version, but computing them spins up a full
/// JS/Dart extension runtime. Cache them so widget builds never pay that cost.
final _sourceHeadersCache = <String, Map<String, String>>{};

@riverpod
Map<String, String> headers(
  Ref ref, {
  required String source,
  required String lang,
  required int? sourceId,
  String androidProxyServer = "",
}) {
  final mSource = getSource(lang, source, sourceId);

  if (mSource == null) return {};

  final cacheKey =
      '${mSource.id}|${mSource.version}|${mSource.sourceCode?.hashCode}|$androidProxyServer';
  final base = _sourceHeadersCache.putIfAbsent(cacheKey, () {
    final headers = <String, String>{};
    final fromSource = mSource.headers;
    if (fromSource != null && fromSource.isNotEmpty) {
      headers.addAll((jsonDecode(fromSource) as Map).toMapStringString!);
    }
    final service = getCachedExtensionService(mSource, androidProxyServer);
    headers.addAll(service.getHeaders());
    return headers;
  });

  if (mSource.sourceCodeLanguage != SourceCodeLanguage.mihon) return base;

  final headers = Map<String, String>.of(base);
  headers['user-agent'] = isar.settings.getSync(227)!.userAgent!;
  return headers;
}
