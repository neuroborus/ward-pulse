import 'dart:async';

import '../sync/claude_account_client.dart';
import 'claude_account_store.dart';
import 'connection_lifecycle.dart';

final class ClaudeLoginAttempt {
  ClaudeLoginAttempt({
    required this.authorization,
    required Future<void> Function(String pastedCode) completeWithCode,
    required void Function() cancel,
  }) : _completeWithCode = completeWithCode,
       _cancel = cancel;

  final ClaudeAuthorizationRequest authorization;
  final Future<void> Function(String pastedCode) _completeWithCode;
  final void Function() _cancel;
  bool _finished = false;

  Future<void> completeWithCode(String pastedCode) async {
    if (_finished) {
      throw const ClaudeAccountException(ClaudeAccountFailure.cancelled);
    }
    await _completeWithCode(pastedCode);
    _finished = true;
  }

  void cancel() {
    if (_finished) {
      return;
    }
    _finished = true;
    _cancel();
  }
}

abstract interface class ClaudeAccountService {
  Future<bool> isConnected();

  Future<ClaudeLoginAttempt> startLogin();

  Future<String?> fetchReport();

  Future<void> disconnect();
}

final class MobileClaudeAccountService implements ClaudeAccountService {
  MobileClaudeAccountService({
    required ClaudeAccountStore store,
    ClaudeAccountClient? client,
  }) : _store = store,
       _client = client ?? ClaudeAccountClient();

  final ClaudeAccountStore _store;
  final ClaudeAccountClient _client;
  VersionedAccountStore<ClaudeAccountSession>? get _versioned =>
      _store is VersionedAccountStore<ClaudeAccountSession>
          ? _store as VersionedAccountStore<ClaudeAccountSession>
          : null;
  Future<void> _abortReconnect(CredentialVersion? ticket) async {
    if (ticket == null) return;
    try {
      await _versioned!.cancelReconnect(ticket);
    } catch (_) {
      /* Pending storage stays closed. */
    }
  }

  Future<void> _operations = Future.value();

  @override
  Future<bool> isConnected() => _serialized(() async {
    return await _readSession() != null;
  });

  @override
  Future<ClaudeLoginAttempt> startLogin() async {
    final ticket = await _versioned?.beginReconnect();
    final ClaudeAuthorizationRequest authorization;
    try {
      authorization = _client.beginAuthorization();
    } catch (_) {
      await _abortReconnect(ticket);
      rethrow;
    }
    final cancellation = Completer<void>();
    return ClaudeLoginAttempt(
      authorization: authorization,
      completeWithCode:
          (pastedCode) => _serialized(() async {
            var saved = false;
            try {
              if (cancellation.isCompleted)
                throw const ClaudeAccountException(
                  ClaudeAccountFailure.cancelled,
                );
              final session = await _client.exchangeAuthorizationCode(
                request: authorization,
                pastedCode: pastedCode,
              );
              if (cancellation.isCompleted)
                throw const ClaudeAccountException(
                  ClaudeAccountFailure.cancelled,
                );
              if (ticket == null) {
                await _writeSession(session);
              } else if (!await _versioned!.completeReconnect(
                session,
                ticket,
              )) {
                throw const ClaudeAccountException(
                  ClaudeAccountFailure.cancelled,
                );
              }
              saved = true;
            } finally {
              if (!saved) await _abortReconnect(ticket);
            }
          }),
      cancel: () {
        if (!cancellation.isCompleted) {
          cancellation.complete();
          unawaited(_abortReconnect(ticket));
        }
      },
    );
  }

  @override
  Future<String?> fetchReport() => _serialized(() {
    final managed = _versioned;
    return managed == null
        ? _fetchReport()
        : managed.serializeFetch(_fetchReport);
  });
  Future<String?> _fetchReport() async {
    final managed = _versioned;
    final VersionedCredential<ClaudeAccountSession>? captured;
    try {
      captured = await managed?.readVersioned();
    } catch (_) {
      throw const ClaudeAccountException(
        ClaudeAccountFailure.unavailable,
        'Claude account · Secure storage unavailable',
      );
    }
    final session = managed == null ? await _readSession() : captured?.value;
    if (session == null) return null;
    var expected = captured?.version;
    try {
      final result = await _client.fetchReport(
        session,
        onSessionChanged: (updated) async {
          if (managed == null) {
            await _writeSession(updated);
          } else {
            final next = await managed.refresh(updated, expected!);
            if (next == null)
              throw const ClaudeAccountException(
                ClaudeAccountFailure.cancelled,
              );
            expected = next;
          }
        },
      );
      if (managed != null && !await managed.isCurrent(expected!))
        throw const ClaudeAccountException(ClaudeAccountFailure.cancelled);
      return result.reportJson;
    } on ClaudeAccountException catch (error) {
      if (error.failure == ClaudeAccountFailure.authentication) {
        if (managed == null) {
          await _deleteSession();
        } else {
          await managed.deleteIfCurrent(expected!);
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> disconnect() =>
      _versioned == null ? _serialized(_disconnect) : _disconnect();
  Future<void> _disconnect() async {
    await _deleteSession();
  }

  Future<ClaudeAccountSession?> _readSession() async {
    try {
      return await _store.read();
    } on FormatException {
      await _deleteSession();
      return null;
    } catch (_) {
      throw const ClaudeAccountException(
        ClaudeAccountFailure.unavailable,
        'Claude account · Secure storage unavailable',
      );
    }
  }

  Future<void> _writeSession(ClaudeAccountSession session) async {
    try {
      await _store.write(session);
    } catch (_) {
      throw const ClaudeAccountException(
        ClaudeAccountFailure.unavailable,
        'Claude account · Secure storage unavailable',
      );
    }
  }

  Future<void> _deleteSession() async {
    try {
      await _store.delete();
    } catch (_) {
      throw const ClaudeAccountException(
        ClaudeAccountFailure.unavailable,
        'Claude account · Secure storage unavailable',
      );
    }
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operations = _operations.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

final class EmptyClaudeAccountService implements ClaudeAccountService {
  const EmptyClaudeAccountService();

  @override
  Future<bool> isConnected() async => false;

  @override
  Future<ClaudeLoginAttempt> startLogin() {
    throw const ClaudeAccountException(ClaudeAccountFailure.unavailable);
  }

  @override
  Future<String?> fetchReport() async => null;

  @override
  Future<void> disconnect() async {}
}
