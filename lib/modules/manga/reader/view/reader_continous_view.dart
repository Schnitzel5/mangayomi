import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/manga/reader/providers/reader_controller_provider.dart';
import 'package:mangayomi/modules/manga/reader/virtual_scrolling/virtual_reader_view.dart';
import 'package:mangayomi/services/get_chapter_pages.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../u_chap_data_preload.dart';

class ReaderContinousView extends ConsumerStatefulWidget {
  final dynamic Function(Chapter)? onChapterChanged;
  final ReaderController readerController;
  final PhotoViewController photoViewController;
  final PhotoViewScaleStateController photoViewScaleStateController;
  final Alignment scalePosition;
  final List<UChapDataPreload> uChapDataPreload;
  final ItemScrollController itemScrollController;
  final ScrollOffsetController pageOffsetController;
  final ItemPositionsListener itemPositionsListener;
  final bool isHorizontalContinuaous;
  final int pagePreloadAmount;
  final void Function(UChapDataPreload, BuildContext) onLongPressImageDialog;
  final ValueNotifier<bool> failedToLoadImage;
  final BackgroundColor backgroundColor;
  final StateProvider<ReaderMode?> currentReaderMode;
  final void Function(Offset) toggleScale;
  final Chapter chapter;
  final bool isBookmarked;
  final void Function(GetChapterPagesModel, Chapter) preloadNextChapter;
  final void Function(Chapter) addLastPageTransition;
  final PageMode? pageMode;

  const ReaderContinousView({
    super.key,
    required this.onChapterChanged,
    required this.readerController,
    required this.photoViewController,
    required this.photoViewScaleStateController,
    required this.scalePosition,
    required this.uChapDataPreload,
    required this.itemScrollController,
    required this.pageOffsetController,
    required this.itemPositionsListener,
    required this.isHorizontalContinuaous,
    required this.pagePreloadAmount,
    required this.onLongPressImageDialog,
    required this.failedToLoadImage,
    required this.backgroundColor,
    required this.currentReaderMode,
    required this.toggleScale,
    required this.chapter,
    required this.isBookmarked,
    required this.preloadNextChapter,
    required this.addLastPageTransition,
    required this.pageMode,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ReaderContinousState();
}

class _ReaderContinousState extends ConsumerState<ReaderContinousView> {
  @override
  Widget build(BuildContext context) {
    return PhotoViewGallery.builder(
      itemCount: 1,
      builder: (_, _) => PhotoViewGalleryPageOptions.customChild(
        controller: widget.photoViewController,
        scaleStateController: widget.photoViewScaleStateController,
        basePosition: widget.scalePosition,
        onScaleEnd: _onScaleEnd,
        child: VirtualReaderView(
          pages: widget.uChapDataPreload,
          itemScrollController: widget.itemScrollController,
          scrollOffsetController: widget.pageOffsetController,
          itemPositionsListener: widget.itemPositionsListener,
          scrollDirection: widget.isHorizontalContinuaous
              ? Axis.horizontal
              : Axis.vertical,
          minCacheExtent: widget.pagePreloadAmount * context.height(1),
          initialScrollIndex: widget.readerController.getPageIndex(),
          physics: const ClampingScrollPhysics(),
          onLongPressData: (data) =>
              widget.onLongPressImageDialog(data, context),
          onFailedToLoadImage: (value) {
            // Handle failed image loading
            if (widget.failedToLoadImage.value != value && context.mounted) {
              widget.failedToLoadImage.value = value;
            }
          },
          backgroundColor: widget.backgroundColor,
          isDoublePageMode:
              widget.pageMode == PageMode.doublePage &&
              !widget.isHorizontalContinuaous,
          isHorizontalContinuous: widget.isHorizontalContinuaous,
          readerMode: ref.watch(widget.currentReaderMode)!,
          photoViewController: widget.photoViewController,
          photoViewScaleStateController: widget.photoViewScaleStateController,
          scalePosition: widget.scalePosition,
          onScaleEnd: (details) =>
              _onScaleEnd(context, details, widget.photoViewController.value),
          onDoubleTapDown: (offset) => widget.toggleScale(offset),
          onDoubleTap: () {},
          // Chapter transition callbacks
          onChapterChanged: widget.onChapterChanged,
          onReachedLastPage: (lastPageIndex) {
            try {
              ref
                  .watch(
                    getChapterPagesProvider(
                      chapter: widget.readerController.getNextChapter(),
                    ).future,
                  )
                  .then(
                    (value) => widget.preloadNextChapter(value, widget.chapter),
                  );
            } on RangeError {
              widget.addLastPageTransition(widget.chapter);
            }
          },
        ),
      ),
    );
  }

  void _onScaleEnd(
    BuildContext context,
    ScaleEndDetails details,
    PhotoViewControllerValue controllerValue,
  ) {
    if (controllerValue.scale! < 1) {
      widget.photoViewScaleStateController.reset();
    }
  }
}
