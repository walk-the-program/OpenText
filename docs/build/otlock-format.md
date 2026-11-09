# .otlock format, version 1

A `.otlock` file holds one encrypted file. It can be decrypted without OpenText using only the password (or the recovery key) and standard primitives: PBKDF2-HMAC-SHA256, X25519, HKDF-SHA256, AES-256-GCM.

Reference implementation: `Packages/OpenTextKit/Sources/OpenTextKit/Locker.swift`. `testDocumentedRecipeDecrypts` re-implements the recipe below independently.

## Byte layout

All integers are big-endian.

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | Magic `OTLK` (0x4F 0x54 0x4C 0x4B) |
| 4 | 1 | Format version, `0x01` |
| 5 | 4 | `H` = length of the JSON header in bytes (uint32) |
| 9 | H | JSON header, UTF-8 (stored exactly as written; do not re-serialize) |
| 9+H | rest | Payload ciphertext followed by the 16-byte GCM tag |

`prefix` = bytes `[0, 9+H)` (magic, version, length, header). The payload is `ciphertext || tag`; split it by taking the last 16 bytes as the tag.

## JSON header

```json
{
  "version": 1,
  "cipher": "AES-256-GCM",
  "payloadNonce": "<base64, 12 bytes>",
  "password": {
    "kdf": "PBKDF2-HMAC-SHA256",
    "iterations": 600000,
    "salt": "<base64, 16 bytes>",
    "nonce": "<base64, 12 bytes>",
    "wrappedKey": "<base64, 48 bytes = 32-byte wrapped file key || 16-byte tag>"
  },
  "recovery": {
    "kdf": "X25519-HKDF-SHA256",
    "ephemeralPublicKey": "<base64, 32 bytes>",
    "salt": "<base64, 16 bytes>",
    "info": "OpenText recovery v1",
    "nonce": "<base64, 12 bytes>",
    "wrappedKey": "<base64, 48 bytes>"
  }
}
```

`recovery` is present only when a recovery public key was configured at lock time. Keys are written sorted, with no escaped slashes.

## Keys and AAD

- File key: 32 random bytes. Encrypts the payload.
- Password slot: `KEK = PBKDF2-HMAC-SHA256(password as UTF-8 bytes, salt, iterations, 32 bytes)`. No Unicode normalization. `wrappedKey = AES-256-GCM(KEK, nonce, fileKey, AAD = "OTLK1 password slot")`.
- Recovery slot: recovery key = X25519 private key (32 bytes). `shared = X25519(privateKey, ephemeralPublicKey)`; `KEK = HKDF-SHA256(ikm = shared, salt = salt, info = UTF-8(info), 32 bytes)`. `wrappedKey = AES-256-GCM(KEK, nonce, fileKey, AAD = "OTLK1 recovery slot")`.
- Payload: `AES-256-GCM(fileKey, payloadNonce, plaintext, AAD = prefix)`. Binding the whole header as AAD means any change to the header or the lengths makes the payload fail authentication.

Payload plaintext = `uint32 nameLength || name (UTF-8, original file name only) || original file bytes`.

## Recovery key text form

The 32 private-key bytes encoded as RFC 4648 Base32 (alphabet `A-Z2-7`), no padding, 52 characters, shown in groups of 4 joined with `-`. Parsing ignores case, spaces and dashes. The matching public key (base64 of the 32-byte X25519 public key) is what gets stored in settings and passed to `lock`.

## Decrypt recipe (no app needed)

```
data = read(file)
assert data[0..4] == "OTLK" and data[4] == 1
H = uint32_be(data[5..9]); header = json(data[9 .. 9+H]); prefix = data[0 .. 9+H]
body = data[9+H ..]; tag = body[-16:]; ct = body[:-16]

# password route
s = header.password
kek = pbkdf2_hmac_sha256(utf8(password), b64(s.salt), s.iterations, dklen=32)
w = b64(s.wrappedKey)
fileKey = aes_gcm_decrypt(kek, nonce=b64(s.nonce), ct=w[:-16], tag=w[-16:], aad="OTLK1 password slot")
        # tag failure here = wrong password

# recovery route (instead)
r = header.recovery
shared = x25519(recoveryPrivateKey, b64(r.ephemeralPublicKey))
kek = hkdf_sha256(ikm=shared, salt=b64(r.salt), info=utf8(r.info), length=32)
fileKey = aes_gcm_decrypt(kek, nonce=b64(r.nonce), ct=w[:-16], tag=w[-16:], aad="OTLK1 recovery slot")

# payload
plain = aes_gcm_decrypt(fileKey, nonce=b64(header.payloadNonce), ct=ct, tag=tag, aad=prefix)
        # tag failure here = damaged or tampered file
n = uint32_be(plain[0..4]); name = utf8(plain[4 .. 4+n]); original = plain[4+n ..]
```

## Errors in OpenText

Not an `OTLK` file: `notLocked`. Bad version, truncated, unparsable header, or failed payload authentication: `corruptLockedFile`. Password slot fails to open: `wrongPassword`. Recovery slot fails to open: `invalidRecoveryKey`; file has no recovery slot: `noRecoveryKeyConfigured`.

Default names: locking `a.txt` writes `a.txt.otlock`; unlocking writes the stored original name next to the locked file. Existing files are never overwritten (`name 2.ext`). The original file name is stored encrypted, and any path components in it are ignored on unlock.

## Saving back (in-memory API)

`Locker.lock(data:originalName:password:recoveryPublicKeyBase64:output:)` produces the same format as file locking (the file-based `lock` calls it). It writes atomically (temp file + replace) and overwrites `output`, so a crash never leaves a half-written `.otlock`. Every call generates a fresh file key and fresh salts, so **`lockID(of:)` changes on every save-back**; the app must re-store the Touch ID Keychain item under the new id (and delete the old one). `Locker.decrypt(_:recoveryKey:)` is the in-memory counterpart of recovery unlock. The on-disk format is unchanged.
