# Changelog

## 0.1.0 — 2026-09-11

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
