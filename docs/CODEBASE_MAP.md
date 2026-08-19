# Codebase Map

This document is the shortest route through the repository. Start here before
opening implementation files.

## Runtime flow

```text
lib/main.dart
  -> lib/app/bootstrap/antiq_app_bootstrap.dart   composition root
  -> lib/app/app.dart                              application shell
  -> lib/features/*/presentation                  screens and view state
  -> lib/features/*/data                           feature repositories
  -> packages/chat_core                            chat use cases and storage
  -> packages/crypto_core                           crypto policy and adapters
  -> packages/pqc_engine_sdk                        pure PQC wire/primitive SDK
  -> services/backend                               Django transport and identity
```

The bootstrap file is the only place where the shared `ApiClient`, database,
repositories and core services are assembled. A screen receives a feature
repository or application facade; it does not construct or call the transport
client directly.

## Where to start by task

| Task | Start here | Then follow |
| --- | --- | --- |
| Login/session | `lib/features/auth/presentation/` | `lib/features/auth/data/` |
| Chat list/contacts | `lib/features/chat/presentation/chat_list_page.dart` | `chat_hub_controller.dart` and `packages/chat_core/.../chat_facade.dart` (users/conversations parts) |
| Conversation UI | `lib/features/chat/presentation/chat_page.dart` | `chat_conversation_controller.dart` and `chat_page_*` parts |
| Send/retry/outbox | `packages/chat_core/lib/src/chat/application/outgoing_message_service.dart` | `outgoing_message_queue.dart`, `outgoing_message_delivery.dart`, `outgoing_message_attachments.dart` |
| Chat transport | `packages/chat_core/lib/src/chat/data/` | `chat_remote_data_source.dart`, `chat_repository.dart` |
| Private/group crypto | `packages/crypto_core/lib/src/crypto/` | `private_message_codec.dart`, `group_message_codec.dart`, `group_key_store.dart` |
| V3 protocol | `packages/pqc_engine_sdk/lib/src/v3_engine.dart` | `v3_attachment_codec.dart` and the V3 engine contract |
| Release/capability negotiation | `docs/release-profiles.md` | `PqcProtocolRelease`, `PayloadFormatRegistry`, backend `users/serializers.py` |
| Key verification | `packages/chat_core/lib/src/security/` | `key_verification_service.dart` barrel and `key_verification_service_impl.dart` |
| File transfers | `packages/chat_core/lib/src/transfer/` | models -> store -> facade |
| Tasks/KPI | `lib/features/tasks/` | `data/task_kpi_repository.dart`, then `presentation/` |
| RBAC | `lib/features/rbac/` | `data/rbac_repository.dart`, then `presentation/` |
| Account/recovery | `lib/features/account/data/` | `account_repository.dart`, then chat hub actions |
| Backend endpoint | `services/backend/chat/` or `services/backend/users/` | serializer -> `api_views/` domain module -> compatibility `views.py` -> URL/test |

## Backend API navigation

The backend keeps the historical `views.py` import path as a small compatibility
barrel. New endpoint work belongs in the domain module that owns the behavior:

| Domain | Implementation modules | Boundary |
| --- | --- | --- |
| Authentication/account/recovery/devices | `services/backend/users/api_views/` | `users/urls.py` -> `users/views.py` barrel |
| Conversations/messages/attachments/protocol | `services/backend/chat/api_views/` | `chat/urls.py` -> `chat/views.py` barrel |
| Optional RBAC | `services/backend/backend_plugins/rbac/` | plugin URLs -> `rbac/views.py` barrel |
| Tasks/activity/notifications/KPI | `services/backend/backend_plugins/task_kpi/api_views/` | plugin URLs -> `task_kpi/views.py` barrel |

The compatibility barrels contain exports only; they are not places for new
business logic. This keeps URL contracts stable while making each API domain
independently searchable and testable.

## Chat application navigation

`packages/chat_core/lib/src/chat/application/chat_facade.dart` is the stable
public facade and composition boundary. Its implementation is split by
responsibility into `chat_facade_users.dart`,
`chat_facade_conversations.dart`, `chat_facade_messaging.dart`,
`chat_facade_attachments.dart`, and `chat_facade_realtime.dart`. These are Dart
library parts, so callers keep one facade while maintainers can work in a
narrow domain file.

## Layer rules

1. `presentation` may depend on feature repositories, application facades and
   domain models. It must not import `ApiClient`.
2. `data` owns HTTP paths, DTO conversion and local persistence adapters.
3. `packages/chat_core` owns chat orchestration and does not import Flutter UI.
4. `packages/crypto_core` owns crypto policy and SDK adapters; it does not own
   widgets or backend views.
5. `packages/pqc_engine_sdk` is pure Dart and owns stable wire contracts. It
   must not depend on Flutter, Django or app-specific storage.
6. `services/backend` is a separate Python service. Client code must not be
   imported from it and client packages must not import backend modules.
7. Generated files (`*.g.dart`) are outputs of the database generator; edit
   their source schema or Drift declarations instead.
8. Deployment crypto capabilities and per-device protocol capabilities are
   different contracts. Never use the deployment endpoint alone to decide
   whether a recipient device can receive V2.5 or V3.

## Naming and navigation conventions

- `*_page.dart`: screen shell and dependency list.
- `*_state.dart`, `*_actions.dart`, `*_views.dart`: parts of one screen
  library; they share only that screen's private state.
- `*_repository.dart`: feature data boundary.
- `*_facade.dart` or `*_service.dart`: application orchestration boundary.
- `*_models.dart`: data/state contracts without side effects.
- `*_encode.dart` / `*_decode.dart`: protocol direction split; both remain
  behind the original public barrel.
- Barrel files preserve stable imports while directing new code to the
  specific implementation boundary.

## Safe change workflow

1. Find the entry point in the table above.
2. Change the narrowest layer that owns the behavior.
3. Keep transport calls in `data/` and crypto calls in the crypto package.
4. Run `dart format` on changed Dart files, then `dart analyze`.
5. Run the relevant package tests and backend tests before a release.
