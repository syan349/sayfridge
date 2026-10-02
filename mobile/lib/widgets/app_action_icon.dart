import 'package:flutter/material.dart';

abstract final class ActionAssets {
  static const _root = 'assets/icons/inventory';
  static const deleteBlack = '$_root/delete_black.png';
  static const deleteWhite = '$_root/delete_white.png';
  static const deleteRed = '$_root/delete_red.png';
  static const edit = '$_root/edit.png';
  static const defaultSelected = '$_root/default_selected.png';
  static const defaultUnselected = '$_root/default_unselected.png';
}

class AppActionIcon extends StatelessWidget {
  const AppActionIcon(this.asset, {this.size = 24, super.key});
  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: (size * 3).ceil(),
      excludeFromSemantics: true,
    );
    if (asset != ActionAssets.defaultSelected &&
        asset != ActionAssets.defaultUnselected) {
      return image;
    }
    // The supplied circular badges have transparent star cutouts.
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * .84,
            height: size * .84,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
          ),
          image,
        ],
      ),
    );
  }
}
