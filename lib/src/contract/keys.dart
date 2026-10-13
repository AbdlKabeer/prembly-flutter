import 'constants.dart';
import 'errors.dart';

enum Environment { live, sandbox }

class KeyInfo {
  const KeyInfo(this.publishableKey, this.environment);

  final String publishableKey;

  /// Decided by the key prefix only: live_pk_ is live, test_pk_ is sandbox.
  final Environment environment;
}

const String _keyHelp =
    'Prembly.init: publishableKey must be your public key (live_pk_... or test_pk_...). '
    'Never put a secret key (live_sk_ / test_sk_) in a browser or an app.';

/// Accepts only publishable keys. Anything else (secret keys, garbage, empty) throws.
KeyInfo parsePublishableKey(Object? input) {
  final key = input is String ? input.trim() : '';
  if (key.startsWith(liveKeyPrefix)) return KeyInfo(key, Environment.live);
  if (key.startsWith(sandboxKeyPrefix)) {
    return KeyInfo(key, Environment.sandbox);
  }
  throw PremblyError(ErrorCode.invalidKey, _keyHelp);
}
