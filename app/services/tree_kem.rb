# From-scratch TreeKEM-style N-party group key agreement (the mechanism
# behind MLS / RFC 9420), built only from standard primitives — X25519,
# HKDF-SHA256, AES-256-GCM. Members are leaves of a ratchet tree; a commit
# rekeys the committer's path in O(log N), every current member converges on
# a fresh epoch group key, and removed members provably cannot.
#
# SECURITY: an educational, from-scratch implementation demonstrating the
# protocol. NOT independently audited; do not rely on it to protect real
# secrets without formal review.
module TreeKem
end
