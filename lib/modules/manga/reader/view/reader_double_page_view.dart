import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/manga/reader/double_columm_view_center.dart';
import 'package:mangayomi/modules/manga/reader/u_chap_data_preload.dart';
import 'package:mangayomi/modules/manga/reader/widgets/transition_view_paged.dart';

class ReaderDoublePageView extends ConsumerStatefulWidget {
  final ExtendedPageController extendedController;
  final List<UChapDataPreload> uChapDataPreload;
  final void Function(UChapDataPreload, BuildContext) onLongPressImageDialog;
  final void Function(int) onPageChanged;
  final ValueNotifier<bool> failedToLoadImage;
  final BackgroundColor backgroundColor;
  final Axis scrollDirection;
  final bool isReverseHorizontal;
  final double horizontalScaleValue;

  const ReaderDoublePageView({
    super.key,
    required this.extendedController,
    required this.uChapDataPreload,
    required this.onLongPressImageDialog,
    required this.onPageChanged,
    required this.failedToLoadImage,
    required this.backgroundColor,
    required this.scrollDirection,
    required this.isReverseHorizontal,
    required this.horizontalScaleValue,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _ReaderDoublePageState();
}

class _ReaderDoublePageState extends ConsumerState<ReaderDoublePageView> {
  @override
  Widget build(BuildContext context) {
    return ExtendedImageGesturePageView.builder(
      controller: widget.extendedController,
      scrollDirection: widget.scrollDirection,
      reverse: widget.isReverseHorizontal,
      physics: const ClampingScrollPhysics(),
      canScrollPage: (_) {
        return widget.horizontalScaleValue == 1.0;
      },
      itemBuilder: (context, index) {
        if (index < widget.uChapDataPreload.length &&
            widget.uChapDataPreload[index].isTransitionPage) {
          return TransitionViewPaged(data: widget.uChapDataPreload[index]);
        }

        int index1 = index * 2 - 1;
        int index2 = index1 + 1;
        final pageList = (index == 0
            ? [widget.uChapDataPreload[0], null]
            : [
                index1 < widget.uChapDataPreload.length
                    ? widget.uChapDataPreload[index1]
                    : null,
                index2 < widget.uChapDataPreload.length
                    ? widget.uChapDataPreload[index2]
                    : null,
              ]);
        return DoubleColummView(
          datas: widget.isReverseHorizontal
              ? pageList.reversed.toList()
              : pageList,
          backgroundColor: widget.backgroundColor,
          isFailedToLoadImage: (val) {
            if (widget.failedToLoadImage.value != val && mounted) {
              widget.failedToLoadImage.value = val;
            }
          },
          onLongPressData: (datas) {
            widget.onLongPressImageDialog(datas, context);
          },
        );
      },
      itemCount: (widget.uChapDataPreload.length / 2).ceil() + 1,
      onPageChanged: widget.onPageChanged,
    );
  }
}
