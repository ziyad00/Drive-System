# Simple Drive

A simple object storage service with a single HTTP API in front of multiple,
swappable storage backends: **S3-compatible storage** (spoken natively over
HTTP with a hand-rolled AWS Signature V4 — no S3 SDK), a **database table**,
the **local file system**, and **FTP**.

## API

All requests require Bearer token authentication.

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
| `STORAGE_BACKEND` | `s3`, `database`, `local` or `ftp` | `local` |
| `SIMPLE_DRIVE_API_TOKEN` | Bearer token accepted by the API | `dev-token` (development only) |
| `LOCAL_STORAGE_PATH` | Directory for the local backend | `storage/blobs` |
| `S3_ENDPOINT` | e.g. `https://s3.amazonaws.com` or `http://localhost:9000` | — |
| `S3_BUCKET` / `S3_REGION` | Bucket and region | region: `us-east-1` |
| `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` | Credentials | — |
| `FTP_HOST` / `FTP_PORT` / `FTP_USER` / `FTP_PASSWORD` / `FTP_BASE_DIR` | FTP settings | port: `21` |

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

## Tests

```sh
bin/rails test
```

Covers the API end to end (auth, round-trip, validation errors, duplicates,
404s), each storage adapter, and the SigV4 signer. S3 tests stub HTTP with
WebMock, so no external service is needed.
