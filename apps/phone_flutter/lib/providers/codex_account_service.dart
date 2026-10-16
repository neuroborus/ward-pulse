import 'dart:async';

import '../sync/codex_account_client.dart';
import 'codex_account_store.dart';
import 'connection_lifecycle.dart';

final class CodexLoginAttempt {
  CodexLoginAttempt({
    required this.deviceCode,
    required Future<void> completion,
    required void Function() cancel,
  }) : _completion = completion,
       _cancel = cancel;

  final CodexDeviceCode deviceCode;
  final Future<void> _completion;
  final void Function() _cancel;

  Future<void> get completion => _completion;

  void cancel() => _cancel();
}

abstract interface class CodexAccountService {
  Future<bool> isConnected();

  Future<CodexLoginAttempt> startLogin();

  Future<String?> fetchReport();

  Future<void> disconnect();
}

final class MobileCodexAccountService implements CodexAccountService {
  MobileCodexAccountService({
    required CodexAccountStore store,
    CodexAccountClient? client,
  }) : _store = store,
       _client = client ?? CodexAccountClient();

  final CodexAccountStore _store;
  final CodexAccountClient _client;
  VersionedAccountStore<CodexAccountSession>? get _versioned =>
      _store is VersionedAccountStore<CodexAccountSession>
          ? _store as VersionedAccountStore<CodexAccountSession>
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
  Future<CodexLoginAttempt> startLogin() async {
    final ticket = await _versioned?.beginReconnect();
    final CodexDeviceCode deviceCode;
    try {
      deviceCode = await _client.requestDeviceCode();
    } catch (_) {
      await _abortReconnect(ticket);
      rethrow;
    }
    final cancellation = Completer<void>();
    final completion =
        (() async {
          var saved = false;
          try {
            final session = await _client.completeDeviceLogin(
              deviceCode,
              cancelled: cancellation.future,
            );
            await _serialized(() async {
              if (cancellation.isCompleted)
                throw const CodexAccountException(
                  CodexAccountFailure.cancelled,
                );
              if (ticket == null) {
                await _writeSession(session);
              } else if (!await _versioned!.completeReconnect(
                session,
                ticket,
              )) {
                throw const CodexAccountException(
                  CodexAccountFailure.cancelled,
                );
              }
              saved = true;
            });
          } finally {
            if (!saved) await _abortReconnect(ticket);
          }
        })();
    return CodexLoginAttempt(
      deviceCode: deviceCode,
      completion: completion,
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
    final VersionedCredential<CodexAccountSession>? captured;
    try {
      captured = await managed?.readVersioned();
    } catch (_) {
      throw const CodexAccountException(
        CodexAccountFailure.unavailable,
        'Codex account · Secure storage unavailable',
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
              throw const CodexAccountException(CodexAccountFailure.cancelled);
            expected = next;
          }
        },
      );
      if (managed != null && !await managed.isCurrent(expected!))
        throw const CodexAccountException(CodexAccountFailure.cancelled);
      return result.reportJson;
    } on CodexAccountException catch (error) {
      if (error.failure == CodexAccountFailure.authentication) {
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
    final session = await _readSession();
    await _deleteSession();
    if (session != null) {
      try {
        await _client.revoke(session);
      } catch (_) {
        // Local sign-out succeeds even if remote revocation is unavailable.
      }
    }
  }

  Future<CodexAccountSession?> _readSession() async {
    try {
      return await _store.read();
    } on FormatException {
      await _deleteSession();
      return null;
    } catch (_) {
      throw const CodexAccountException(
        CodexAccountFailure.unavailable,
        'Codex account · Secure storage unavailable',
      );
    }
  }

  Future<void> _writeSession(CodexAccountSession session) async {
    try {
      await _store.write(session);
    } catch (_) {
      throw const CodexAccountException(
        CodexAccountFailure.unavailable,
        'Codex account · Secure storage unavailable',
      );
    }
  }

  Future<void> _deleteSession() async {
    try {
      await _store.delete();
    } catch (_) {
      throw const CodexAccountException(
        CodexAccountFailure.unavailable,
        'Codex account · Secure storage unavailable',
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

final class EmptyCodexAccountService implements CodexAccountService {
  const EmptyCodexAccountService();

  @override
  Future<bool> isConnected() async => false;

  @override
  Future<CodexLoginAttempt> startLogin() {
    throw const CodexAccountException(CodexAccountFailure.unavailable);
  }

  @override
  Future<String?> fetchReport() async => null;

  @override
  Future<void> disconnect() async {}
}
