import 'dart:async';

import 'package:chat_core/chat_core.dart' show UnauthorizedApiException;
import 'package:drift/drift.dart' as drift;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../../../app/app_localization.dart';
import '../../../app/design_system/app_design_system.dart';
import '../../../core/database/app_database.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/storage/local_ui_preferences_store.dart';
import '../../crypto/chat_crypto_exceptions.dart';
import '../../crypto/durability/crypto_core_facade.dart';
import '../../security/key_verification_service.dart';
import '../application/chat_controllers.dart';
import '../application/chat_facade.dart';
import '../application/chat_models.dart';
import '../application/chat_services.dart';
import '../../transfers/application/attachment_transfer.dart';
import 'chat_local_image.dart';
import 'chat_thread_widget.dart';

part 'chat_page_state.dart';
part 'chat_page_state_actions.dart';
part 'chat_page_message_views.dart';
part 'chat_page_message_actions.dart';
part 'chat_page_message_state_views.dart';
part 'chat_page_message_item_views.dart';
part 'chat_page_attachment_views.dart';
part 'chat_page_transfer_views.dart';
part 'chat_page_composer_internal.dart';
part 'chat_page_conversation_widgets.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.currentUserId,
    required this.conversation,
    required this.title,
    this.avatarUrl = '',
    this.roleLabel = '',
    required this.chatFacade,
    required this.cryptoCoreFacade,
    required this.database,
    required this.onUnauthorized,
  });

  final int currentUserId;
  final Conversation conversation;
  final String title;
  final String avatarUrl;
  final String roleLabel;
  final ChatFacade chatFacade;
  final CryptoCoreFacade cryptoCoreFacade;
  final AppDatabase database;
  final Future<void> Function() onUnauthorized;

  @override
  State<ChatPage> createState() => _ChatPageState();
}
