import 'package:flutter/material.dart';
import 'package:mangayomi/utils/global_style.dart';

class CustomPopupMenuButton<T> extends StatelessWidget {
  final String label;
  final String title;
  final ValueChanged<T> onSelected;
  final T value;
  final List<T> list;
  final String Function(T) itemText;
  const CustomPopupMenuButton({
    super.key,
    required this.label,
    required this.title,
    required this.onSelected,
    required this.value,
    required this.list,
    required this.itemText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: PopupMenuButton(
        popUpAnimationStyle: popupAnimationStyle,
        tooltip: "",
        offset: Offset.fromDirection(1),
        color: Colors.black,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (var d in list)
            PopupMenuItem(
              value: d,
              child: Row(
                children: [
                  Icon(
                    Icons.check,
                    color: d == value ? Colors.white : Colors.transparent,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    itemText(d),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).textTheme.bodyLarge!.color!.withValues(alpha: 0.9),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              Row(
                children: [
                  Text(title),
                  const SizedBox(width: 20),
                  const Icon(Icons.keyboard_arrow_down_outlined),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomValueIndicatorShape extends SliderComponentShape {
  final _indicatorShape = const PaddleSliderValueIndicatorShape();
  final bool tranform;
  const CustomValueIndicatorShape({this.tranform = false});
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(40, 40);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final textSpan = TextSpan(
      text: labelPainter.text?.toPlainText(),
      style: sliderTheme.valueIndicatorTextStyle,
    );

    final textPainter = TextPainter(
      text: textSpan,
      textAlign: labelPainter.textAlign,
      textDirection: textDirection,
    );

    textPainter.layout();

    context.canvas.save();
    context.canvas.translate(center.dx, center.dy);
    context.canvas.scale(tranform ? -1.0 : 1.0, 1.0);
    context.canvas.translate(-center.dx, -center.dy);

    _indicatorShape.paint(
      context,
      center,
      activationAnimation: activationAnimation,
      enableAnimation: enableAnimation,
      labelPainter: textPainter,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      value: value,
      textScaleFactor: textScaleFactor,
      sizeWithOverflow: sizeWithOverflow,
      isDiscrete: isDiscrete,
      textDirection: textDirection,
    );

    context.canvas.restore();
  }
}
