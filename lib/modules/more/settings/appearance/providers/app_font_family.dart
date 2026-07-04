import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'app_font_family.g.dart';

@riverpod
class AppFontFamily extends _$AppFontFamily {
  @override
  String? build() {
    // The stored value already is the resolved GoogleFonts fontFamily;
    // scanning GoogleFonts.asMap() to look it up constructed a TextStyle for
    // every catalog font (~1500) on the theme path just to return the input.
    return isar.settings.getSync(227)!.appFontFamily;
  }

  void set(String? fontFamily) {
    final settings = isar.settings.getSync(227);
    state = fontFamily;
    isar.writeTxnSync(
      () => isar.settings.putSync(
        settings!
          ..appFontFamily = fontFamily
          ..updatedAt = DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
