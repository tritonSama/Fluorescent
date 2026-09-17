import 'package:flutter/widgets.dart';

/// A widget that displays the native texture provided by Fluorescent.
/// It should be added to the Flame `GameWidget` overlays.
class FluorescentTextureOverlay extends StatelessWidget {
  final int textureId;
  final double width;
  final double height;

  const FluorescentTextureOverlay({
    super.key,
    required this.textureId,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Texture(textureId: textureId),
    );
  }
}
