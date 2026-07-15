# Simple Drive

A simple object storage service with a single HTTP API in front of multiple,
swappable storage backends: **S3-compatible storage** (spoken natively over
HTTP with a hand-rolled AWS Signature V4 — no S3 SDK), a **database table**,
the **local file system**, and **FTP**. Includes a React frontend
(`frontend/`) for storing and browsing blobs from the browser.

## API

All requests require Bearer token authentication. Tokens belong to API users
(only a SHA-256 digest is stored). Mint one with:

```sh
bin/rails simple_drive:create_user[alice]
```

Development seeds a ready-made user with token `dev-token`
(`bin/rails db:seed`).

The service is multi-tenant: blobs belong to the user that stored them, all
reads are owner-scoped, and ids are unique per user — two users can store
under the same id without seeing or overwriting each other's data.

### Store a blob

```
POST /v1/blobs
Authorization: Bearer <token>
Content-Type: application/json

{
  "id": "any_valid_string_or_identifier",
  "data": "SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh"
}
```

`id` is an arbitrary unique string (UUID, path, anything). `data` must be
valid Base64; the request is rejected with `422` otherwise. Duplicate ids are
rejected with `409`, missing fields with `400`.

An optional `"backend"` field stores this blob in a specific backend
(`s3`, `database`, `local`, `ftp`). Without it, the authenticated user's
default backend applies, falling back to the system default.

### Choose a backend

```
GET /v1/backends                 -> { "available": [...], "default": "...",
                                      "user_default": ..., "system_default": "..." }
PUT /v1/backends/default         { "backend": "database" }   # personal default
PUT /v1/backends/default         { "backend": null }         # back to system default
```

### Files and folders

A hierarchical namespace layered over the same storage (the flat blob API
above stays exactly as the spec defines it):

```
POST  /v1/folders            {"path": "/docs/reports"}          # mkdir -p
POST  /v1/files              {"path": "/docs/q3.pdf", "data": "<base64>",
                              "content_type": "...", "client_mtime": "...",
                              "backend": "..."}                 # parents auto-created
GET   /v1/fs/<path>          # folder -> metadata + children; file -> metadata + data
PUT   /v1/files              create-or-replace; honors If-Match (412 on
                              mismatch), last-write-wins without it
GET   /v1/dl/<path>          raw binary download; Range/If-Range partial
                              reads (206), ?disposition=attachment
POST  /v1/uploads            {"path", "size", ...} start a resumable upload
PATCH /v1/uploads/:id        binary chunk at Upload-Offset (409 on mismatch);
                              the final chunk creates/replaces the file
HEAD  /v1/uploads/:id        resume point (Upload-Offset / Upload-Length)
DELETE /v1/uploads/:id       abort and discard staged bytes
PATCH /v1/nodes/:id          {"name": ...} rename / {"parent_id": ...} move
POST  /v1/nodes/:id/copy     {"parent_id": ..., "name": ...}    # folders copy recursively
DELETE /v1/nodes/:id[?recursive=true]                           # purges file bytes
```

The tree is an adjacency list, so moving a subtree of any size is one
atomic column update, and renames/moves never touch storage — bytes are
addressed by immutable blob ids, not paths. Sibling names are unique per
folder; MIME types are sniffed from content when not supplied. File
responses carry a strong ETag (SHA-256 of content): reads honor
`If-None-Match` (304), replacements honor `If-Match` (412 on mismatch).

### Retrieve a blob

```
GET /v1/blobs/<id>
Authorization: Bearer <token>
```

```json
{
  "id": "any_valid_string_or_identifier",
  "data": "SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh",
  "size": "27",
  "created_at": "2026-07-13T20:52:01Z"
}
```

## Architecture

```
V1::BlobsController      HTTP layer: validation, auth, JSON rendering
        │
      Blob               metadata table (id, size, backend, created_at)
        │
   Storage.current       factory — picks the configured adapter
        │
   Storage::Base         common adapter interface: store(id, data) / retrieve(id)
   ├── Storage::S3       raw Net::HTTP + Storage::S3::Signer (SigV4, no SDK)
   ├── Storage::Database blob_contents table, separate from metadata
   ├── Storage::Local    sharded files under a configured directory
   └── Storage::Ftp      files on an FTP server (net-ftp)
```

Each blob's metadata records which backend it was written to, so retrieval
keeps working for previously stored blobs even after the configured backend
changes.

Blob ids are arbitrary strings, so adapters never use them directly as file
names or object keys — they address content by the SHA-256 of the id, and the
original id lives only in the metadata table.

## Configuration

Everything is configured via `config/simple_drive.yml`, with environment
variable overrides:

| Variable | Meaning | Default |
| --- | --- | --- |
| `STORAGE_BACKEND` | System default backend: `s3`, `database`, `local` or `ftp` | `local` |
| `MAX_BLOB_BYTES` | Maximum decoded blob size; larger requests get `413` | `26214400` (25 MB) |
| `RATE_LIMIT_PER_MINUTE` | Requests allowed per client (token or IP) per minute; excess gets `429` | `120` |
| `LOCAL_STORAGE_PATH` | Directory for the local backend | `storage/blobs` |
| `S3_ENDPOINT` | e.g. `https://s3.amazonaws.com` or `http://localhost:9000` | — |
| `S3_BUCKET` / `S3_REGION` | Bucket and region | region: `us-east-1` |
| `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` | Credentials | — |
| `S3_OPEN_TIMEOUT` / `S3_READ_TIMEOUT` / `S3_WRITE_TIMEOUT` | Seconds before a stalled S3 endpoint fails the request | `5` / `30` / `30` |
| `FTP_HOST` / `FTP_PORT` / `FTP_USER` / `FTP_PASSWORD` / `FTP_BASE_DIR` | FTP settings | port: `21` |
| `FTP_TLS` | FTPS (explicit TLS); disable only for TLS-less servers | `true` |

## Development stack

`docker compose up -d` boots every service the app (and future designs) can
use — Postgres 17, Valkey, MinIO (bucket auto-created, console on :9001),
a dev-only plain-FTP server (set `FTP_TLS=false` to use it), and OpenBao in
dev mode with a ready `simple-drive` transit KEK (AES-256-GCM) on :8200.
Optional profiles: `--profile observability` (Prometheus :9090, Grafana
:3001, Jaeger :16686) and `--profile security` (ClamAV :3310). All
credentials are dev-only defaults; state lives in named volumes.

Run the API against the stack's MinIO with:

```sh
STORAGE_BACKEND=s3 S3_ENDPOINT=http://localhost:9000 S3_BUCKET=blobs S3_ACCESS_KEY_ID=minioadmin S3_SECRET_ACCESS_KEY=minioadmin bin/rails server
```

## Running

```sh
bundle install
bin/rails db:prepare
bin/rails server
```

Then:

```sh
curl -X POST http://localhost:3000/v1/blobs \
  -H "Authorization: Bearer dev-token" \
  -H "Content-Type: application/json" \
  -d '{"id": "hello", "data": "SGVsbG8gU2ltcGxlIFN0b3JhZ2UgV29ybGQh"}'

curl http://localhost:3000/v1/blobs/hello -H "Authorization: Bearer dev-token"
```

## Frontend

A React SPA (Vite + shadcn/ui) in `frontend/` for storing and browsing blobs
from the browser:

```sh
cd frontend
npm install
npm run dev   # http://localhost:5173, expects the API on http://localhost:3000
```

Set the API token in the header (development default: `dev-token`). Each row
shows the blob's storage key — the SHA-256 of its id rendered as a color band —
which matches the object's name in the storage backend (e.g. the folder you
see in the MinIO object browser). `VITE_API_URL` and `VITE_MINIO_CONSOLE`
override the API and MinIO console locations.

The upload form includes a storage backend picker (only configured backends
are offered) with a one-click "Make default" that saves the choice as your
per-user default. A header toggle switches between light and dark themes.

## Security notes

- **Secrets live in ENV only.** Rails' `credentials.yml.enc` is intentionally
  unused for real secrets: its master-key encryption is AES-128-GCM, below
  the AES-256 bar this project's crypto policy sets. Keep S3/FTP credentials
  and tokens in environment variables.
- **The frontend is a development console.** It keeps the API token in
  `localStorage` for convenience, which an XSS vulnerability could read
  (none is known — React escapes by default). The `dev-token` default is
  compiled out of production builds. If this UI ever fronts real data, keep
  the token in memory only.
- API tokens are stored server-side as SHA-256 digests; requests are
  throttled per client and capped in size; FTP defaults to TLS.

## Tests

```sh
bin/rails test
```

`bin/ci` (or `ruby bin/ci` on Windows) runs the full CI pipeline locally —
API tests, security scanners, and the frontend typecheck/build — the same
checks GitHub Actions runs on every PR, without the round-trip.

Four scanners guard every PR: **Brakeman** (Rails static security
analysis), **gitleaks** (secrets across the full git history; suppressions
live in `.gitleaks.toml`), **OSV-Scanner** (known vulnerabilities in
`Gemfile.lock` and `frontend/package-lock.json`), and **Trivy** (filesystem
CVEs plus IaC misconfiguration, HIGH/CRITICAL blocking). Locally, install
the binaries with `winget install Gitleaks.Gitleaks Google.OSVScanner
AquaSecurity.Trivy` (or brew); `bin/ci` skips those steps gracefully when
they're absent.

Covers the API end to end (auth, round-trip, validation errors, duplicates,
404s), each storage adapter, and the SigV4 signer. S3 tests stub HTTP with
WebMock, so no external service is needed.
