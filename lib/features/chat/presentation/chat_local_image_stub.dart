import 'package:flutter/material.dart';

Widget buildChatLocalImage(BuildContext context, String path) {
  return Container(
    height: 180,
    width: double.infinity,
    color: Theme.of(context).colorScheme.surface,
    alignment: Alignment.center,
    child: const Text('Preview unavailable on this platform'),
  );
}
