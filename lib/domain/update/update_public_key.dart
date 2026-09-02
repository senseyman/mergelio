/// Public half of the release-signing key. The update manifest is rejected
/// unless it carries a matching Ed25519 signature, so a compromised download
/// host still cannot point the app at a foreign build.
///
/// Raw 32-byte Ed25519 public key, base64. Rotating it invalidates every
/// manifest signed with the previous key.
const String kUpdatePublicKeyBase64 = '+sdKhMN5GQQlHcqSuDvPC4XRgN6hXZ5/P5xBWKAy4J0=';
