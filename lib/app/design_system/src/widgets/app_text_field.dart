import 'package:flutter/material.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.onSubmitted,
    this.maxLines = 1,
    this.minLines,
  });

  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final int? minLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        labelText: labelText,
      ),
      onSubmitted: onSubmitted,
      maxLines: maxLines,
      minLines: minLines,
    );
  }
}
