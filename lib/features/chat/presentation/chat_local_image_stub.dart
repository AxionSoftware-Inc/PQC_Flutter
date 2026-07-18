import 'package:flutter/material.dart';

Widget buildChatLocalImage(BuildContext context, String path) => const SizedBox(
  height: 160,
  child: Center(child: Icon(Icons.image_not_supported_outlined)),
);

Widget buildChatLocalImageViewer(BuildContext context, String path) =>
    const Center(child: Text('Image preview is unavailable on this platform.'));
