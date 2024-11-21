import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/modules/more/settings/downloads/providers/downloads_state_provider.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  @override
  Widget build(
    BuildContext context,
  ) {
    final saveAsCBZArchiveState = ref.watch(saveAsCBZArchiveStateProvider);
    final onlyOnWifiState = ref.watch(onlyOnWifiStateProvider);
    final downloadLocationState = ref.watch(downloadLocationStateProvider);
    final cacheImagesDirectory = getTemporaryDirectory();
    ref.read(downloadLocationStateProvider.notifier).refresh();
    final l10n = l10nLocalizations(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n!.downloads),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            ListTile(
              onTap: () {
                showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: Text(l10n.download_location),
                        content: SizedBox(
                            width: context.width(0.8),
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                RadioListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.all(0),
                                    value: downloadLocationState.$2.isEmpty
                                        ? downloadLocationState.$1
                                        : downloadLocationState.$2,
                                    groupValue: downloadLocationState.$1,
                                    onChanged: (value) {
                                      ref
                                          .read(downloadLocationStateProvider
                                              .notifier)
                                          .set("");
                                      Navigator.pop(context);
                                    },
                                    title: Text(downloadLocationState.$1)),
                                RadioListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.all(0),
                                    value: downloadLocationState.$2.isEmpty
                                        ? downloadLocationState.$1
                                        : downloadLocationState.$2,
                                    groupValue: downloadLocationState.$2,
                                    onChanged: (value) async {
                                      String? result = await FilePicker.platform
                                          .getDirectoryPath();

                                      if (result != null) {
                                        ref
                                            .read(downloadLocationStateProvider
                                                .notifier)
                                            .set(result);
                                      } else {}
                                      if (!context.mounted) return;
                                      Navigator.pop(context);
                                    },
                                    title: Text(l10n.custom_location)),
                              ],
                            )),
                        actions: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                  onPressed: () async {
                                    Navigator.pop(context);
                                  },
                                  child: Text(
                                    l10n.cancel,
                                    style:
                                        TextStyle(color: context.primaryColor),
                                  )),
                            ],
                          )
                        ],
                      );
                    });
              },
              title: Text(l10n.download_location),
              subtitle: Text(
                downloadLocationState.$2.isEmpty
                    ? downloadLocationState.$1
                    : downloadLocationState.$2,
                style: TextStyle(fontSize: 11, color: context.secondaryColor),
              ),
            ),
            SwitchListTile(
                value: onlyOnWifiState,
                title: Text(l10n.only_on_wifi),
                onChanged: (value) {
                  ref.read(onlyOnWifiStateProvider.notifier).set(value);
                }),
            SwitchListTile(
                value: saveAsCBZArchiveState,
                title: Text(l10n.save_as_cbz_archive),
                onChanged: (value) {
                  ref.read(saveAsCBZArchiveStateProvider.notifier).set(value);
                }),
            IconButton(
                onPressed: () async {
                  final Directory cacheImagesDirectory = Directory(join(
                      (await getTemporaryDirectory()).path,
                      cacheImageFolderName));
                  cacheImagesDirectory.deleteSync(recursive: true);
                },
                icon: Icon(
                  Icons.cached_outlined,
                  color: Theme.of(context).hintColor,
                )),
            FutureBuilder(
                future: cacheImagesDirectory,
                builder:
                    (BuildContext context, AsyncSnapshot<Directory> snapshot) {
                  if (snapshot.hasData) {
                    final Directory cacheImagesDirectory = Directory(
                        join(snapshot.data!.path, cacheImageFolderName));
                    final cacheImageSize = getDirSize(cacheImagesDirectory);
                    return Text("${l10n.image_cache_size}: ${cacheImageSize / 1000000} MB",
                        style: TextStyle(
                            fontSize: 11, color: context.secondaryColor));
                  }
                  return Text("${l10n.image_cache_size}: -",
                      style: TextStyle(
                          fontSize: 11, color: context.secondaryColor));
                }),
          ],
        ),
      ),
    );
  }

  int getDirSize(Directory dir) {
    var files = dir.listSync(recursive: true).toList();
    var dirSize = files.fold(0, (int sum, file) => sum + file.statSync().size);
    return dirSize;
  }
}
