import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/web_approvals/approvals_sync.dart';
import 'package:besttodo/services/web_approvals/token_vault.dart';
import 'package:besttodo/services/web_approvals/vault_crypto.dart';
import 'package:besttodo/ui/web_approvals_site.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MapStore implements VaultStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// Not real crypto: a keystream from the password, plus a check value that
/// fails on a wrong password like GCM's tag. Enough to test [TokenVault]'s
/// bookkeeping; the real thing is the browser's Web Crypto.
class _FakeCrypto implements VaultCrypto {
  int _counter = 0;

  @override
  Uint8List randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (i) => (i + _counter++) % 256));

  List<int> _key(String password, Uint8List salt, int n) {
    final seed = [...utf8.encode(password), ...salt];
    return List.generate(n, (i) => seed[i % seed.length] ^ (i * 31 % 256));
  }

  int _check(String password, Uint8List salt) =>
      _key(password, salt, 8).fold(7, (a, b) => (a * 31 + b) % 251);

  @override
  Future<Uint8List> encrypt({
    required String password,
    required Uint8List salt,
    required int iterations,
    required Uint8List iv,
    required Uint8List plaintext,
  }) async {
    final key = _key(password, salt, plaintext.length);
    return Uint8List.fromList([
      _check(password, salt),
      for (var i = 0; i < plaintext.length; i++) plaintext[i] ^ key[i],
    ]);
  }

  @override
  Future<Uint8List> decrypt({
    required String password,
    required Uint8List salt,
    required int iterations,
    required Uint8List iv,
    required Uint8List ciphertext,
  }) async {
    if (ciphertext.first != _check(password, salt)) {
      throw StateError('OperationError');
    }
    final body = ciphertext.sublist(1);
    final key = _key(password, salt, body.length);
    return Uint8List.fromList(
        [for (var i = 0; i < body.length; i++) body[i] ^ key[i]]);
  }
}

void main() {
  group('TokenVault', () {
    late _MapStore store;
    late DateTime now;
    late TokenVault vault;
    late List<Duration> delays;
    const password = 'correct horse battery';

    setUp(() {
      store = _MapStore();
      now = DateTime(2026, 10, 28, 12);
      delays = [];
      vault = TokenVault(
        store: store,
        crypto: _FakeCrypto(),
        now: () => now,
        delay: (d) async => delays.add(d),
      );
    });

    test('round-trips the token and never stores it in the clear', () async {
      expect(await vault.exists(), isFalse);
      await vault.create('secret-token-123', password);
      expect(await vault.exists(), isTrue);
      final raw = store.data[TokenVault.vaultKey]!;
      expect(raw, isNot(contains('secret-token-123')));
      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect(json['kdf'], 'PBKDF2-SHA256');
      expect(json['iterations'], TokenVault.defaultIterations);
      expect(await vault.unlock(password), 'secret-token-123');
    });

    test('refuses a short password', () async {
      expect(TokenVault.passwordProblem('short'), isNotNull);
      expect(TokenVault.passwordProblem('long enough pw'), isNull);
      expect(() => vault.create('t', 'short'), throwsArgumentError);
    });

    test('the 2nd wrong password in a row deletes the token and silently '
        'bans the browser for 3 months', () async {
      await vault.create('secret-token-123', password);
      await expectLater(vault.unlock('nope nope nope'),
          throwsA(isA<WrongPasswordException>()));
      expect(await vault.exists(), isTrue);
      expect(await vault.isBanned(), isFalse);

      await expectLater(vault.unlock('nope again!!'),
          throwsA(isA<WrongPasswordException>()));
      expect(await vault.exists(), isFalse);
      expect(store.data.toString(), isNot(contains('secret')));
      expect(await vault.isBanned(), isTrue);
      expect(delays, isEmpty);

      // The right password gets the same answer, after a realistic pause.
      await expectLater(
          vault.unlock(password), throwsA(isA<WrongPasswordException>()));
      expect(delays, [TokenVault.fakeCheckTime]);
      // Setting up again and Forget don't lift it.
      await expectLater(vault.create('other-token', password), throwsStateError);
      await vault.forget();
      expect(await vault.isBanned(), isTrue);

      now = now.add(TokenVault.banDuration - const Duration(minutes: 1));
      expect(await vault.isBanned(), isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(await vault.isBanned(), isFalse);
      await expectLater(
          vault.unlock(password), throwsA(isA<VaultWipedException>()));
      await vault.create('secret-token-123', password);
      expect(await vault.unlock(password), 'secret-token-123');
    });

    test('only wrong passwords in a row count: the right one resets them',
        () async {
      await vault.create('secret-token-123', password);
      await expectLater(vault.unlock('nope nope nope'),
          throwsA(isA<WrongPasswordException>()));
      expect(await vault.unlock(password), 'secret-token-123');
      expect(store.data.keys, [TokenVault.vaultKey]);
      await expectLater(vault.unlock('nope nope nope'),
          throwsA(isA<WrongPasswordException>()));
      expect(await vault.isBanned(), isFalse);
      expect(await vault.unlock(password), 'secret-token-123');
    });

    test('forget deletes everything', () async {
      await vault.create('secret-token-123', password);
      await vault.forget();
      expect(store.data, isEmpty);
      await expectLater(
          vault.unlock(password), throwsA(isA<VaultWipedException>()));
    });
  });

  group('ApprovalsSyncCoordinator.mergeOver', () {
    Task task(String uid, String title, {String label = ''}) =>
        Task(uid: uid, title: title, label: label);

    test('keeps what a sync pulled and applies only the page\'s changes', () {
      final pageA = task('a', 'Approve me', label: 'Waiting_for_approval');
      final pageB = task('b', 'Deny me');
      final pageC = task('c', 'Untouched');
      final page = [pageA, pageB, pageC];
      final baseline = ApprovalsSyncCoordinator.snapshot(page);

      // The page approves a, denies b, adds d.
      pageA.label = '';
      page.remove(pageB);
      page.add(task('d', 'Made here'));
      // Meanwhile a sync edited c remotely and pulled e.
      final stored = [
        task('a', 'Approve me', label: 'Waiting_for_approval'),
        task('b', 'Deny me'),
        task('c', 'Edited on Todoist'),
        task('e', 'Pulled by the sync'),
      ];

      final merged = ApprovalsSyncCoordinator.mergeOver(
          stored: stored, page: page, baseline: baseline);
      expect(merged.map((t) => '${t.uid}:${t.title}:${t.label}'), [
        'a:Approve me:',
        'c:Edited on Todoist:',
        'e:Pulled by the sync:',
        'd:Made here:',
      ]);
      expect(identical(merged.first, pageA), isTrue);
    });

    test('an unchanged task keeps the page\'s own instance', () {
      final mine = task('a', 'Same');
      final merged = ApprovalsSyncCoordinator.mergeOver(
        stored: [task('a', 'Same')],
        page: [mine],
        baseline: ApprovalsSyncCoordinator.snapshot([mine]),
      );
      expect(identical(merged.single, mine), isTrue);
    });

    test('a task the sync removed stays removed even if the page touched it',
        () {
      final mine = task('a', 'Gone remotely');
      final baseline = ApprovalsSyncCoordinator.snapshot([mine]);
      mine.label = 'mlr';
      final merged = ApprovalsSyncCoordinator.mergeOver(
          stored: const [], page: [mine], baseline: baseline);
      expect(merged, isEmpty);
    });
  });

  group('ApprovalsSyncCoordinator', () {
    test('a save waits for a running sync instead of interleaving', () async {
      final order = <String>[];
      final release = Completer<void>();
      final sync = ApprovalsSyncCoordinator(runSync: () async {
        order.add('sync start');
        await release.future;
        order.add('sync end');
        return null;
      });
      final syncDone = sync.syncNow();
      await Future<void>.delayed(Duration.zero);
      final save = sync.exclusive(() async => order.add('save'));
      await Future<void>.delayed(Duration.zero);
      expect(order, ['sync start']);
      release.complete();
      await Future.wait([syncDone, save]);
      expect(order, ['sync start', 'sync end', 'save']);
      expect(sync.revision.value, 1);
      sync.dispose();
    });

    test('a failing sync reports its error and releases the lock', () async {
      final sync = ApprovalsSyncCoordinator(runSync: () async => 'offline');
      await sync.syncNow();
      expect(sync.lastError.value, 'offline');
      expect(await sync.exclusive(() async => 42), 42);
      sync.dispose();
    });
  });

  group('WebApprovalsSite lock screen', () {
    late _MapStore store;
    late TokenVault vault;

    setUp(() {
      store = _MapStore();
      vault = TokenVault(
          store: store, crypto: _FakeCrypto(), delay: (_) async {});
    });

    Future<void> pumpSite(WidgetTester tester,
        {required Future<int> Function(String, void Function(String))
            loadData}) async {
      await tester.pumpWidget(MaterialApp(
        home: WebApprovalsSite(vault: vault, loadData: loadData, lock: () {}),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a new browser asks for the token and a long password',
        (tester) async {
      await pumpSite(tester, loadData: (_, __) async => 0);
      expect(find.text('Set up approvals'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('site-token')), 'tok');
      await tester.enterText(find.byKey(const Key('site-password')), 'short');
      await tester.enterText(find.byKey(const Key('site-confirm')), 'short');
      await tester.tap(find.text('Save and open'));
      await tester.pumpAndSettle();
      expect(find.text('Use at least 12 characters'), findsOneWidget);
      expect(store.data, isEmpty);
    });

    testWidgets('a wrong password says only "Wrong password", the right one '
        'loads the account', (tester) async {
      await tester.runAsync(
          () => vault.create('secret-token-123', 'correct horse battery'));
      String? loadedWith;
      await pumpSite(tester, loadData: (token, _) async {
        loadedWith = token;
        throw StateError('offline');
      });
      expect(find.text('Unlock'), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('site-password')), 'wrong password!');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong password'), findsOneWidget);
      expect(loadedWith, isNull);

      await tester.enterText(
          find.byKey(const Key('site-password')), 'correct horse battery');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(loadedWith, 'secret-token-123');
      // The load failed (offline): back on the lock screen, saying why.
      expect(find.text('Unlock'), findsOneWidget);
      expect(find.textContaining('offline'), findsOneWidget);
    });

    testWidgets('a banned browser keeps showing a normal lock screen',
        (tester) async {
      await tester.runAsync(() async {
        await vault.create('secret-token-123', 'correct horse battery');
        for (final guess in ['guess number one', 'guess number two']) {
          await expectLater(vault.unlock(guess),
              throwsA(isA<WrongPasswordException>()));
        }
      });
      var loaded = false;
      await pumpSite(tester, loadData: (_, __) async {
        loaded = true;
        return 0;
      });
      expect(find.text('Unlock'), findsOneWidget);
      await tester.enterText(
          find.byKey(const Key('site-password')), 'correct horse battery');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Wrong password'), findsOneWidget);
      expect(loaded, isFalse);

      await tester.tap(find.text('Forget this browser'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forget'));
      await tester.pumpAndSettle();
      expect(find.text('Unlock'), findsOneWidget);
      expect(find.text('Set up approvals'), findsNothing);
    });
  });
}
