# Optional remote configuration tooling

This infrastructure is included for transparency and future integration. `lib/main.dart` does not construct `RemoteConfigService` or `AdController`, so the running UI does not fetch configuration, apply platform switches/notices, or show config-driven interstitials.

## Defaults and configuration

The service has no default endpoint. With an empty URL, refresh returns without a network request. A custom integration can supply `configUrl` to the constructor or build with `--dart-define=REMOTE_CONFIG_URL=https://example.com/config`. A build flag alone does not integrate the service into the app.

The service loads cached plaintext JSON from SharedPreferences, then attempts a refresh when initialized. Fetches time out after five seconds. Callers can explicitly refresh or check whether the cache is at least 15 minutes old; there is no background polling timer. Bad HTTP responses, invalid JSON, decryption failures, and older configuration versions keep the cached or compiled defaults. Equal versions are accepted. This fallback does not guarantee a disabled platform will remain disabled after cache loss.

JSON can hold platform flags/messages, ad enable flags and unit IDs, interstitial frequency, rewarded ad-free duration, and a notice. See `config.example.json` and `lib/models/remote_config.dart` for the schema and defaults. Example ad IDs are Google's public test IDs.

## Local use

Create an isolated Python environment and install the optional tools:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r tools/remote_config/requirements.txt
cp tools/remote_config/config.example.json tools/remote_config/config.json
.venv/bin/python tools/remote_config/encrypt_config.py
.venv/bin/python tools/remote_config/decrypt_config.py --file tools/remote_config/jadugame
```

Encryption generates a local random 32-byte `secret.key` if absent and a `.last_version` tracker. Increase `configVersion` for each encryption. The output name `jadugame` is retained for format compatibility; it is simply an encrypted JSON file.

`--print-key-parts` emits two Dart XOR lists to paste into `_assembleKey` for a custom client. The shipped lists are all-zero placeholders and will not decrypt a randomly generated key's output. Do not commit production keys or private configuration. Treat printed key parts as key material too.

To inspect an explicitly chosen remote blob:

```sh
.venv/bin/python tools/remote_config/decrypt_config.py --url https://example.com/config
```

The optional encrypt flag `--push /path/to/config-repository` copies `jadugame` into that local Git repository, stages it, creates a commit, and pushes using that repository's credentials and Git author identity. It is an explicit publishing action; check the destination and author metadata before using it. There is no built-in account or destination. The tool does not publish private plaintext/key files.

## Format and security limits

The format is one line of `base64(nonce[12] || ciphertext || GCM authentication tag[16])`, with AES-256-GCM and no additional authenticated data. Python uses `cryptography` and Dart uses `encrypt`.

A symmetric decryption key embedded in a distributed app can be recovered; XOR splitting is obfuscation. Anyone with the recovered key can read and forge matching blobs. HTTPS provides transport protection for the configured endpoint, but this scheme is not a trusted digital signature. Never use it for secrets, payment authorization, or license enforcement. Cached decrypted JSON is not encrypted at rest by this project. A future integration should use verifiable signatures if configuration authenticity is a requirement.

The scripts, source, schema, behavior, and limitations are public. Local `config.json`, `secret.key`, `.last_version`, and generated `jadugame` are ignored by Git.
