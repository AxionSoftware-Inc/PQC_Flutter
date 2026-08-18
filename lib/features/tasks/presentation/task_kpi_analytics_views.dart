part of 'task_kpi_page.dart';

// ignore_for_file: invalid_use_of_protected_member


extension _TaskKpiAnalyticsViews on _TaskKpiPageState {

  Future<void> _openKpiAnalytics() async {
    try {
      final values = await Future.wait<dynamic>([
        widget.repository.get('/task-kpi/kpi-summary'),
        widget.repository.get('/task-kpi/reports'),
        widget.repository.get('/task-kpi/kpi-goals'),
      ]);
      if (!mounted) return;
      final summary = values[0] is List
          ? List<Map<String, dynamic>>.from(values[0] as List)
          : _kpiSummary;
      final report = values[1] is Map
          ? Map<String, dynamic>.from(values[1] as Map)
          : const <String, dynamic>{};
      final goals = values[2] is List
          ? List<Map<String, dynamic>>.from(values[2] as List)
          : const <Map<String, dynamic>>[];
      final goalDetails = await Future.wait<dynamic>(
        goals.map(
          (goal) => widget.repository.get('/task-kpi/kpi-goals/${goal['id']}'),
        ),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('KPI ko‘rsatkichlari'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metricChip('Jami', report['total']),
                    _metricChip('Tugatilgan', report['done']),
                    _metricChip('Qaytarilgan', report['returned']),
                    _metricChip('Muddati o‘tgan', report['overdue']),
                  ],
                ),
                if (report['average_completion_hours'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'O‘rtacha bajarilish: ${report['average_completion_hours']} soat',
                    ),
                  ),
                const SizedBox(height: 16),
                ...summary.map((item) {
                  final total = (item['total'] as num?)?.toInt() ?? 0;
                  final done = (item['done'] as num?)?.toInt() ?? 0;
                  final progress = total == 0 ? 0.0 : done / total;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item['name'] as String? ?? 'Xodim'),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(value: progress),
                    ),
                    trailing: Text('$done/$total'),
                  );
                }),
                if (goals.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(
                    'KPI maqsadlari',
                    style: Theme.of(dialogContext).textTheme.titleMedium,
                  ),
                  ...goals.asMap().entries.map((entry) {
                    final goal = entry.value;
                    final current =
                        (goal['current_value'] as num?)?.toDouble() ?? 0;
                    final target =
                        (goal['target_value'] as num?)?.toDouble() ?? 0;
                    final progress = target <= 0
                        ? 0.0
                        : (current / target).clamp(0, 1).toDouble();
                    final detail = goalDetails[entry.key];
                    final historyCount =
                        detail is Map && detail['history'] is List
                        ? (detail['history'] as List).length
                        : 0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(goal['title'] as String? ?? 'KPI'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: progress),
                          const SizedBox(height: 4),
                          Text('Tarix: $historyCount ta o‘zgarish'),
                        ],
                      ),
                      trailing: Text('$current/$target'),
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Yopish'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('KPI ma’lumotlarini yuklab bo‘lmadi: $error')),
      );
    }
  }

  Widget _metricChip(String label, dynamic value) {
    return Chip(label: Text('$label: ${value ?? 0}'));
  }

  Future<void> _downloadTaskAttachment(Map<String, dynamic> attachment) async {
    final id = (attachment['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      final root = await getApplicationDocumentsDirectory();
      final directory = Directory(p.join(root.path, 'task-kpi'));
      await directory.create(recursive: true);
      final rawName = attachment['filename'] as String? ?? 'attachment';
      final safeName = rawName.replaceAll(RegExp(r'[\\/]'), '_');
      final file = File(p.join(directory.path, '${id}_$safeName'));
      if (!await file.exists() || await file.length() == 0) {
        final response = await widget.repository
            .getBytes('/task-kpi/attachments/$id/download')
            .timeout(const Duration(seconds: 45));
        await file.writeAsBytes(response.bytes, flush: true);
      }
      final mime = _attachmentMimeType(rawName);
      if (mime.startsWith('image/')) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
        );
      } else {
        await OpenFilex.open(file.path, type: mime);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Faylni yuklab bo‘lmadi: $error')));
    }
  }

  String _attachmentMimeType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    return 'application/octet-stream';
  }


}
