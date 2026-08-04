import 'dart:io';

import 'package:flutter/material.dart';

Widget buildChatLocalImage(BuildContext context, String path) {
  return Image.file(
    File(path),
    height: 220,
    width: double.infinity,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => const SizedBox(
      height: 160,
      child: Center(child: Icon(Icons.broken_image_outlined, size: 38)),
    ),
  );
}

Widget buildChatLocalImageViewer(BuildContext context, String path) {
  return InteractiveViewer(
    minScale: 0.7,
    maxScale: 5,
    child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
  );
}
