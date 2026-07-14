import 'package:record/record.dart';

/// Small platform-neutral recorder used by the chat composer.
/// The resulting path is passed to the normal attachment upload pipeline.
class VoiceMessageRecorder {
  VoiceMessageRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start(String path) async {
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: path,
    );
  }

  Future<String?> stop() => _recorder.stop();

  Future<void> dispose() => _recorder.dispose();
}
