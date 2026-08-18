import 'package:flutter/material.dart';

import '../../../app/design_system/app_design_system.dart';
import '../../transfers/application/attachment_transfer.dart';

class ChatTransferIndicator extends StatelessWidget {
  const ChatTransferIndicator({
    super.key,
    required this.transfer,
    required this.isBusy,
  });

  final AttachmentTransferState? transfer;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    if (isBusy) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (transfer?.status == AttachmentTransferStatus.completed) {
      return Icon(Icons.check_circle_rounded, color: context.appColors.success);
    }
    if (transfer?.status == AttachmentTransferStatus.failed) {
      return Icon(Icons.refresh_rounded, color: context.appColors.danger);
    }
    return Icon(Icons.download_rounded, color: context.appColors.primary);
  }
}
