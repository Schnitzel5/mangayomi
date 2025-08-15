import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/manga/reader/image_view_paged.dart';
import 'package:mangayomi/modules/manga/reader/reader_view.dart';
import 'package:mangayomi/modules/manga/reader/u_chap_data_preload.dart';
import 'package:mangayomi/modules/manga/reader/widgets/circular_progress_indicator_animate_rotate.dart';
import 'package:mangayomi/modules/manga/reader/widgets/transition_view_paged.dart';
import 'package:mangayomi/modules/more/settings/reader/reader_screen.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/utils/extensions/build_context_extensions.dart';

class ReaderNormalView extends ConsumerStatefulWidget {
  final ExtendedPageController extendedController;
  final List<UChapDataPreload> uChapDataPreload;
  final void Function(UChapDataPreload, BuildContext) onLongPressImageDialog;
  final void Function(int) onPageChanged;
  final ValueNotifier<bool> failedToLoadImage;
  final BackgroundColor backgroundColor;
  final Axis scrollDirection;
  final bool isReverseHorizontal;
  final Duration? Function() doubleTapAnimationDuration;
  final List<double> doubleTapScales;

  const ReaderNormalView({
    super.key,
    required this.extendedController,
    required this.uChapDataPreload,
    required this.onLongPressImageDialog,
    required this.onPageChanged,
    required this.failedToLoadImage,
    required this.backgroundColor,
    required this.scrollDirection,
    required this.isReverseHorizontal,
    required this.doubleTapAnimationDuration,
    required this.doubleTapScales,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ReaderNormalState();
}

class _ReaderNormalState extends ConsumerState<ReaderNormalView>
    with TickerProviderStateMixin {
  late AnimationController _doubleClickAnimationController;
  Animation<double>? _doubleClickAnimation;
  late DoubleClickAnimationListener _doubleClickAnimationListener;

  @override
  void initState() {
    super.initState();
    _doubleClickAnimationController = AnimationController(
      duration: widget.doubleTapAnimationDuration(),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _doubleClickAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExtendedImageGesturePageView.builder(
      controller: widget.extendedController,
      scrollDirection: widget.scrollDirection,
      reverse: widget.isReverseHorizontal,
      physics: const ClampingScrollPhysics(),
      canScrollPage: (gestureDetails) {
        return true;
      },
      itemBuilder: (BuildContext context, int index) {
        if (widget.uChapDataPreload[index].isTransitionPage) {
          return TransitionViewPaged(data: widget.uChapDataPreload[index]);
        }

        return ImageViewPaged(
          data: widget.uChapDataPreload[index],
          loadStateChanged: (state) {
            if (state.extendedImageLoadState == LoadState.loading) {
              final ImageChunkEvent? loadingProgress = state.loadingProgress;
              final double progress =
                  loadingProgress?.expectedTotalBytes != null
                  ? loadingProgress!.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : 0;
              return Container(
                color: getBackgroundColor(widget.backgroundColor),
                height: context.height(0.8),
                child: CircularProgressIndicatorAnimateRotate(
                  progress: progress,
                ),
              );
            }
            if (state.extendedImageLoadState == LoadState.completed) {
              if (widget.failedToLoadImage.value == true) {
                Future.delayed(
                  const Duration(milliseconds: 10),
                ).then((value) => widget.failedToLoadImage.value = false);
              }
              return ExtendedImageGesture(
                state,
                canScaleImage: (_) => true,
                imageBuilder:
                    (
                      Widget image, {
                      ExtendedImageGestureState? imageGestureState,
                    }) {
                      return image;
                    },
              );
            }
            if (state.extendedImageLoadState == LoadState.failed) {
              if (widget.failedToLoadImage.value == false) {
                Future.delayed(
                  const Duration(milliseconds: 10),
                ).then((value) => widget.failedToLoadImage.value = true);
              }
              return Container(
                color: getBackgroundColor(widget.backgroundColor),
                height: context.height(0.8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      context.l10n.image_loading_error,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: GestureDetector(
                        onLongPress: () {
                          state.reLoadImage();
                          widget.failedToLoadImage.value = false;
                        },
                        onTap: () {
                          state.reLoadImage();
                          widget.failedToLoadImage.value = false;
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: context.primaryColor,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 16,
                            ),
                            child: Text(context.l10n.retry),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          },
          initGestureConfigHandler: (state) {
            return GestureConfig(
              inertialSpeed: 200,
              inPageView: true,
              maxScale: 8,
              animationMaxScale: 8,
              cacheGesture: true,
              hitTestBehavior: HitTestBehavior.translucent,
            );
          },
          onDoubleTap: (state) {
            final Offset? pointerDownPosition = state.pointerDownPosition;
            final double? begin = state.gestureDetails!.totalScale;
            double end;

            //remove old
            _doubleClickAnimation?.removeListener(
              _doubleClickAnimationListener,
            );

            //stop pre
            _doubleClickAnimationController.stop();

            //reset to use
            _doubleClickAnimationController.reset();

            if (begin == widget.doubleTapScales[0]) {
              end = widget.doubleTapScales[1];
            } else {
              end = widget.doubleTapScales[0];
            }

            _doubleClickAnimationListener = () {
              state.handleDoubleTap(
                scale: _doubleClickAnimation!.value,
                doubleTapPosition: pointerDownPosition,
              );
            };

            _doubleClickAnimation = Tween(begin: begin, end: end).animate(
              CurvedAnimation(
                curve: Curves.ease,
                parent: _doubleClickAnimationController,
              ),
            );

            _doubleClickAnimation!.addListener(_doubleClickAnimationListener);

            _doubleClickAnimationController.forward();
          },
          onLongPressData: (datas) {
            widget.onLongPressImageDialog(datas, context);
          },
        );
      },
      itemCount: widget.uChapDataPreload.length,
      onPageChanged: widget.onPageChanged,
    );
  }
}
