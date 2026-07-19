import 'dart:async';

import '../sync/codex_account_client.dart';
import 'codex_account_store.dart';

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
  Future<void> _operations = Future.value();

  @override
  Future<bool> isConnected() => _serialized(() async {
    return await _readSession() != null;
  });

  @override
  Future<CodexLoginAttempt> startLogin() async {
    final deviceCode = await _client.requestDeviceCode();
    final cancellation = Completer<void>();
    final completion = _client
        .completeDeviceLogin(deviceCode, cancelled: cancellation.future)
        .then(
          (session) => _serialized(() async {
            if (cancellation.isCompleted) {
              throw const CodexAccountException(CodexAccountFailure.cancelled);
            }
            await _writeSession(session);
          }),
        );

    return CodexLoginAttempt(
      deviceCode: deviceCode,
      completion: completion,
      cancel: () {
        if (!cancellation.isCompleted) {
          cancellation.complete();
        }
      },
    );
  }

  @override
  Future<String?> fetchReport() => _serialized(() async {
    final session = await _readSession();
    if (session == null) {
      return null;
    }

    try {
      final result = await _client.fetchReport(
        session,
        onSessionChanged: _writeSession,
      );
      return result.reportJson;
    } on CodexAccountException catch (error) {
      if (error.failure == CodexAccountFailure.authentication) {
        await _deleteSession();
      }
      rethrow;
    }
  });

  @override
  Future<void> disconnect() => _serialized(() async {
    final session = await _readSession();
    await _deleteSession();
    if (session != null) {
      try {
        await _client.revoke(session);
      } catch (_) {
        // Local sign-out succeeds even if remote revocation is unavailable.
      }
    }
  });

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
