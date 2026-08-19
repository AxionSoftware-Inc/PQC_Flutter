part of 'task_kpi_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _TaskKpiDashboardViews on _TaskKpiPageState {
  Widget _buildKpiDashboard(BuildContext context) {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final report = _report;
    final dashboard = _dashboard;
    final total = _asInt(report['total']);
    final done = _asInt(report['done']);
    final completion = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final team = dashboard['team'] is List
        ? (dashboard['team'] as List).whereType<Map>().toList()
        : const <Map>[];
    final teamTotal = team.fold<int>(
      0,
      (sum, item) => sum + _asInt(item['total']),
    );
    final teamDone = team.fold<int>(
      0,
      (sum, item) => sum + _asInt(item['done']),
    );
    final teamCompletion = teamTotal == 0
        ? completion
        : (teamDone / teamTotal).clamp(0.0, 1.0);

    return AppSurfaceCard(
      padding: EdgeInsets.all(spacing.lg),
      backgroundColor: colors.primarySoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(context.appRadii.md),
                ),
                child: Icon(
                  Icons.insights_rounded,
                  color: colors.primary,
                  size: 26,
                ),
              ),
              SizedBox(width: spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vazifalar markazi',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      'Vazifalar, muddatlar va jamoa bajarilishini bir joyda boshqaring.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Vazifalar ma’lumotlarini yangilash',
                onPressed: _dashboardLoading ? null : () => _load(),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          SizedBox(height: spacing.lg),
          if (_dashboardLoading)
            const LinearProgressIndicator(minHeight: 2)
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 620 ? 4 : 2;
                final itemWidth =
                    (constraints.maxWidth - spacing.sm * (columns - 1)) /
                    columns;
                return Wrap(
                  spacing: spacing.sm,
                  runSpacing: spacing.sm,
                  children: [
                    SizedBox(
                      width: itemWidth,
                      child: _dashboardMetric(
                        context,
                        icon: Icons.pending_actions_rounded,
                        label: 'Mening faol ishlarim',
                        value: _asInt(dashboard['mine_open']),
                        color: colors.info,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _dashboardMetric(
                        context,
                        icon: Icons.warning_amber_rounded,
                        label: 'Muddati o‘tgan',
                        value: _asInt(dashboard['overdue']),
                        color: colors.danger,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _dashboardMetric(
                        context,
                        icon: Icons.today_rounded,
                        label: 'Bugun',
                        value: _asInt(dashboard['due_today']),
                        color: colors.warning,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _dashboardMetric(
                        context,
                        icon: Icons.task_alt_rounded,
                        label: 'Tugallanish',
                        value: '${(completion * 100).round()}%',
                        color: colors.success,
                      ),
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: spacing.lg),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Jamoa bajarilishi',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      SizedBox(height: spacing.xs),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: teamCompletion,
                          minHeight: 8,
                          backgroundColor: colors.surface.withValues(
                            alpha: 0.7,
                          ),
                          color: colors.primary,
                        ),
                      ),
                      SizedBox(height: spacing.xs),
                      Text(
                        '$teamDone / $teamTotal topshiriq bajarilgan',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: spacing.md),
                OutlinedButton.icon(
                  onPressed: _openOperationalReport,
                  icon: const Icon(Icons.bar_chart_rounded, size: 18),
                  label: const Text('Operatsion hisobot'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _dashboardMetric(
    BuildContext context, {
    required IconData icon,
    required String label,
    required dynamic value,
    required Color color,
  }) {
    final colors = context.appColors;
    return Container(
      padding: EdgeInsets.all(context.appSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(context.appRadii.md),
        border: Border.all(color: colors.border.withValues(alpha: 0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(height: context.appSpacing.sm),
          Text(
            '$value',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: context.appSpacing.xs),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }

  int _asInt(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }
}
