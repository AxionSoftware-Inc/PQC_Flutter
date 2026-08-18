part of 'chat_page.dart';

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({
    required this.trust,
    required this.onVerify,
    required this.isExpanded,
    required this.onToggleExpanded,
  });

  final ConversationKeyTrust trust;
  final Future<void> Function() onVerify;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final summary = !trust.isAvailable
        ? 'Suhbatdosh qurilmasining kaliti hali tayyor emas.'
        : trust.hasEnterpriseKeyChanged
        ? 'Xavfsizlik kalitlari o‘zgargan. Qayta tasdiqlash tavsiya etiladi.'
        : trust.isEnterpriseVerified
        ? 'Korporativ ishonch tasdiqlangan.'
        : trust.isEnterpriseReady
        ? 'PQC tayyor. Xavfsiz xabar yuborish mumkin.'
        : trust.isVerified
        ? 'Qurilma ishonchi tasdiqlangan.'
        : 'Kalit hali tasdiqlanmagan.';

    final tone = !trust.isAvailable
        ? AppStatusTone.warning
        : trust.hasEnterpriseKeyChanged
        ? AppStatusTone.warning
        : trust.isEnterpriseVerified
        ? AppStatusTone.success
        : trust.isEnterpriseReady
        ? AppStatusTone.info
        : trust.isVerified
        ? AppStatusTone.success
        : AppStatusTone.info;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.appSpacing.sm,
        context.appSpacing.xs,
        context.appSpacing.sm,
        0,
      ),
      child: AppStatusBanner(
        message: summary,
        tone: tone,
        action: trust.isAvailable
            ? Wrap(
                spacing: context.appSpacing.xs,
                children: [
                  TextButton(
                    onPressed: onVerify,
                    child: Text(
                      trust.isEnterpriseVerified || trust.isVerified
                          ? 'Qayta tasdiqlash'
                          : 'Tasdiqlash',
                    ),
                  ),
                  TextButton(
                    onPressed: onToggleExpanded,
                    child: Text(
                      isExpanded ? 'Tafsilotni yashirish' : 'Tafsilotlar',
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

class _SecurityDetailCard extends StatelessWidget {
  const _SecurityDetailCard({required this.trust});

  final ConversationKeyTrust trust;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final rows = <(String, String)>[
      ('X25519', trust.fingerprint ?? '-'),
      ('PQC-KEM', trust.pqcFingerprint ?? '-'),
      ('ML-DSA', trust.signingFingerprint ?? '-'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.sm, spacing.xs, spacing.sm, 0),
      child: AppSurfaceCard(
        padding: EdgeInsets.all(spacing.md),
        backgroundColor: context.appColors.surfaceMuted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Xavfsizlik tafsilotlari',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: spacing.sm),
            ...rows.map(
              (row) => Padding(
                padding: EdgeInsets.only(bottom: spacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        row.$1,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.appColors.textMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.$2,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
