import 'dart:io';

Future<int> voiceFileSize(String path) => File(path).length();
