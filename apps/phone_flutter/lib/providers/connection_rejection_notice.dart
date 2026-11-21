import 'connection_lifecycle.dart';
import 'provider_connection.dart';

/// Bounded historical feedback. No credentials, account data or error text.
final class ConnectionRejectionNotice {
  const ConnectionRejectionNotice({
    required this.connection,
    required this.eventId,
    required this.dismissed,
  });
  final ProviderConnectionId connection;
  final String eventId;
  final bool dismissed;

  bool matches(ConnectionRejection? rejection) =>
      rejection?.connection == connection.storageKey &&
      rejection?.eventId == eventId;
}

abstract interface class ConnectionRejectionNoticeStore {
  Future<List<ConnectionRejectionNotice>> read();
  Future<bool> dismiss(ConnectionRejectionNotice notice);
}

final class NativeConnectionRejectionNoticeStore
    implements ConnectionRejectionNoticeStore {
  const NativeConnectionRejectionNoticeStore({
    this.platform = const MethodChannelConnectionCachePlatform(),
  });
  final ConnectionCachePlatform platform;

  @override
  Future<List<ConnectionRejectionNotice>> read() async {
    final notices = <ConnectionRejectionNotice>[];
    for (final entry in providerConnectionCatalog()) {
      final value = Map<String, Object?>.from(
        (await platform.invoke('readNotice', {
              'connection': entry.id.storageKey,
            }))!
            as Map,
      );
      if (value['eventId'] case final String eventId) {
        notices.add(
          ConnectionRejectionNotice(
            connection: entry.id,
            eventId: eventId,
            dismissed: value['dismissed'] == true,
          ),
        );
      }
    }
    return List.unmodifiable(notices);
  }

  @override
  Future<bool> dismiss(ConnectionRejectionNotice notice) async =>
      await platform.invoke('dismissNotice', {
        'connection': notice.connection.storageKey,
        'eventId': notice.eventId,
      }) ==
      true;
}

final class EmptyConnectionRejectionNoticeStore
    implements ConnectionRejectionNoticeStore {
  const EmptyConnectionRejectionNoticeStore();
  @override
  Future<List<ConnectionRejectionNotice>> read() async => const [];
  @override
  Future<bool> dismiss(ConnectionRejectionNotice notice) async => false;
}
