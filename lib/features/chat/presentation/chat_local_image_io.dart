import 'dart:io';

import 'package:flutter/material.dart';

Widget buildChatLocalImage(BuildContext context, String path) {
  return Image.file(
    File(path),
    height: 180,
    width: double.infinity,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => Container(
      height: 180,
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, size: 40),
    ),
  );
}

Widget buildChatLocalImageViewer(BuildContext context, String path) {
  return InteractiveViewer(
    minScale: 0.5,
    maxScale: 5,
    child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
  );
}
