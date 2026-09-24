# Changelog

## 0.3.0

### Removed

- `has_file_hutch_file`, deprecated in 0.2.0 as promised. Rename it to `has_hutch`; the options
  are the same.

### Rails

- `bin/rails file_hutch:backfill MODEL=… FROM=…` moves an Active Storage attachment onto its
  `has_hutch` column: streams each blob through FileHutch, or with `ADOPT_FROM=conn_…` registers
  blobs in place when the Active Storage bucket is connected. Restartable; fills only blank rows.
  Backed by `FileHutch::Backfill`.

### Client

- `adopt(key:, storage_connection:)` registers an object already in a connected bucket as a file,
  without copying it. Idempotent: adopting the same key again returns the same file.

## 0.2.0 — 2026-09-16

### Rails

- `has_file_hutch_file` is now `has_hutch`, with the same options. The old name still works and
  logs a deprecation warning; it will be removed in 0.3.

## 0.1.0 — 2026-09-15

First release.

### Client

- `FileHutch::Client`: project, uploads (create, complete, and a one-call `upload` that streams
  straight to storage), files, signed URLs, named transforms, delete.
- Typed errors mapped from the API's `error.code`, so callers match on a class or a code rather
  than a message.

### Rails

- `has_file_hutch_file` for Active Record. One `<name>_file_id` column; nothing about storage
  reaches your schema.
- `FileHutch::Engine` mounts the two direct-upload endpoints, keeping the API key on the server
  behind an authorizer you define.
- A Stimulus controller and a framework-neutral `directUpload` function.
- `file_hutch:install` and `file_hutch:attachment` generators.

### Image transforms

- Transforms are named in the FileHutch dashboard; your code only ever says the name.
  `file.transforms`, `file.transform_url("avatar")`, `user.avatar_transform_url("thumb")`,
  `client.transforms`, `project.transform("avatar")`.
- `TransformsUnsupportedError` carries the message naming what to set up, rather than handing back
  a URL that would 404.

### Fixed before release, by dogfooding against a live server

- The engine authorized `complete` with no policy at all, so every authorizer that checked one —
  including the example in this README — rejected every completion. The policy is now looked up
  from the file being finalized, never taken from the client.
- `put_to_storage` could not accept an upload rebuilt from JSON, as a browser flow returns it,
  because it asked for a filename such an upload does not carry.
