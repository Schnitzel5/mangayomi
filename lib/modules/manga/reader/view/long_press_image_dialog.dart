import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/eval/model/m_bridge.dart';
import 'package:mangayomi/main.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/providers/storage_provider.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class LongPressImageDialog extends ConsumerWidget {
  final Chapter chapter;
  final Uint8List imageBytes;
  final String name;

  const LongPressImageDialog({
    super.key,
    required this.chapter,
    required this.imageBytes,
    required this.name,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SuperListView(
      shrinkWrap: true,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            color: context.themeData.scaffoldBackgroundColor,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Container(
                  height: 7,
                  width: 35,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: context.secondaryColor.withValues(alpha: 0.4),
                  ),
                ),
              ),
              Row(
                children: [
                  button(
                    context.l10n.set_as_cover,
                    Icons.image_outlined,
                    () async {
                      final res = await showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            content: Text(context.l10n.use_this_as_cover_art),
                            actions: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                    },
                                    child: Text(context.l10n.cancel),
                                  ),
                                  const SizedBox(width: 15),
                                  TextButton(
                                    onPressed: () {
                                      final manga = chapter.manga.value!;
                                      isar.writeTxnSync(() {
                                        isar.mangas.putSync(
                                          manga
                                            ..customCoverImage = imageBytes
                                            ..updatedAt = DateTime.now()
                                                .millisecondsSinceEpoch,
                                        );
                                      });
                                      if (context.mounted) {
                                        Navigator.pop(context, "ok");
                                      }
                                    },
                                    child: Text(context.l10n.ok),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      );
                      if (res != null && res == "ok" && context.mounted) {
                        Navigator.pop(context);
                        botToast(context.l10n.cover_updated, second: 3);
                      }
                    },
                  ),
                  button(context.l10n.share, Icons.share_outlined, () async {
                    await Share.shareXFiles([
                      XFile.fromData(
                        imageBytes,
                        name: name,
                        mimeType: 'image/png',
                      ),
                    ]);
                  }),
                  button(context.l10n.save, Icons.save_outlined, () async {
                    final dir = await StorageProvider().getGalleryDirectory();
                    final file = File(p.join(dir!.path, "$name.png"));
                    file.writeAsBytesSync(imageBytes);
                    if (context.mounted) {
                      botToast(context.l10n.picture_saved, second: 3);
                    }
                  }),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget button(String label, IconData icon, Function() onPressed) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(padding: const EdgeInsets.all(4), child: Icon(icon)),
            Text(label),
          ],
        ),
      ),
    ),
  );
}
