# asset_hutch

Ruby and Rails client for [AssetHutch](https://assethutch.com), file infrastructure for apps that
aren't Netflix. Your app persists an opaque file id (`file_…`). AssetHutch owns uploads, private
files, signed URLs, and delivery. Your storage, or AssetHutch's, sits behind it.

```ruby
file = AssetHutch.upload("report.pdf", policy: "documents")   # bytes go straight to storage
file.id                       # => "file_8fK2…"  ← the only thing you store
file.signed_url(expires_in: 600)
AssetHutch::File.find(file.id).delete
```

Stdlib only at runtime. Rails integration switches on when Rails is present.

## Install

```ruby
gem "asset_hutch"
```

```sh
bin/rails generate asset_hutch:install     # initializer, mounts the engine, importmap pin
export ASSET_HUTCH_API_KEY=ah_…             # Dashboard → API keys (project-scoped)
export ASSET_HUTCH_URL=https://…            # only when not using AssetHutch cloud
```

Without Rails: `AssetHutch.configure { |c| c.api_key = "ah_…" }`.

## Client

```ruby
client = AssetHutch.client                       # or AssetHutch::Client.new(api_key:, url:)

client.project                                  # => AssetHutch::Project (storage status, policies)
client.upload(path_or_io, policy: "documents", metadata: { order_id: "ord_1" })
client.file("file_…")                           # => AssetHutch::File
client.signed_url("file_…", expires_in: 3600, disposition: "attachment")  # => SignedUrl(url, expires_at)
client.transforms                               # => [AssetHutch::Transform] (avatar, thumb, hero…)
client.transform_url("file_…", transform: "avatar", expires_in: 600)     # => SignedUrl (expires_at nil if public)
client.delete_file("file_…")                    # => true; the id then reads as status "deleted"

# The three steps, explicit:
upload = client.create_upload(policy: "avatars", filename: "me.png", content_type: "image/png", byte_size: bytes.bytesize)
upload.put(bytes).complete                      # => ready AssetHutch::File
```

`upload` accepts a path, `Pathname`, `File`, `Tempfile`, `StringIO`, an
`ActionDispatch::Http::UploadedFile`, or raw bytes with `filename:`. Content type comes from the
source, then Marcel if loaded, then the extension.

`AssetHutch::File`: `id filename content_type byte_size checksum visibility status metadata policy
url transforms created_at`, plus `ready? pending? failed? deleted? public? private? image? pdf?`,
`signed_url`, `url_or_signed_url`, `transform_url`, `reload`, `delete`.

### Image transforms

Transforms are **named** in the AssetHutch dashboard — `avatar`, `thumb`, `hero` — and your code
only ever says the name. No width, no format, no provider URL syntax, so resizing every avatar in
your app is one dashboard edit.

```ruby
file.transforms                       # => {"avatar" => "https://…", "thumb" => "https://…"}
file.transform_url("avatar")          # public images: free, the URL is already on the payload
file.transform_url("avatar", expires_in: 600)   # private images: signed, one request
```

`AssetHutch::Transform` (`client.transforms`, `project.transform("avatar")`) carries `name width
height fit quality format` so you can render a `srcset` or a picture element from the definitions.

Rendering depends on the project's storage. Where it cannot be done, you get a
`TransformsUnsupportedError` whose message says what to set up — never a URL that 404s.

### Errors

Every failure is an `AssetHutch::Error`. API errors carry `code`, `status`, and `details`.

| Class | When |
| --- | --- |
| `ConfigurationError` | no API key / URL |
| `ConnectionError` | timeout, DNS, reset |
| `AuthenticationError` | 401 |
| `NotFoundError` | unknown id |
| `InvalidRequestError` → `PolicyError` | bad params; content type or size the policy refuses |
| `StorageNotReadyError` | project has no verified storage |
| `InvalidStateError` | not ready, already deleted, not public |
| `PlanLimitError` | 402: the team is out of storage or projects on its plan |
| `TransformError` → `TransformsUnsupportedError` | unknown transform or non-image; storage that cannot render |
| `UploadError` | storage rejected the PUT, upload expired or incomplete, size mismatch |
| `StorageError` | AssetHutch could not reach the bucket |
| `RateLimitError`, `ServerError` | 429, 5xx |

## Webhooks

AssetHutch signs every delivery: `AssetHutch-Signature: t=<unix>,v1=<hex>`
where `v1 = HMAC-SHA256(secret, "<t>.<body>")`. Verify before trusting the
body, and deduplicate on the event `id` (deliveries are at-least-once):

```ruby
class AssetHutchWebhooksController < ActionController::API
  def create
    event = AssetHutch::Webhook.construct_event(
      request.raw_post, request.headers["AssetHutch-Signature"], ENV.fetch("ASSET_HUTCH_WEBHOOK_SECRET")
    )
    case event["type"]
    when "file.created" then Document.find_by(asset_hutch_file_id: event.dig("data", "file", "id"))&.update!(ready: true)
    when "file.deleted" then Document.where(asset_hutch_file_id: event.dig("data", "file", "id")).destroy_all
    end
    head :ok
  rescue AssetHutch::SignatureVerificationError
    head :bad_request
  end
end
```

`construct_event` rejects signatures older than five minutes; pass
`tolerance:` to change that.

## Rails

### Model

One string column per attachment. Nothing about storage lands in your schema.

```sh
bin/rails generate asset_hutch:attachment User avatar    # adds users.avatar_file_id
```

```ruby
class User < ApplicationRecord
  has_asset_hutch_file :avatar, policy: "avatars"
  has_asset_hutch_file :contract, policy: "documents", dependent: false
end

user.avatar = params[:avatar]           # uploaded IO → uploaded to storage on save
user.avatar = "file_…"                  # id from a browser direct upload → verified on save
user.avatar                             # => AssetHutch::File or nil (fetched lazily, cached)
user.avatar?                            # id present
user.avatar_url                         # public URL (public policies only)
user.avatar_signed_url(expires_in: 600) # any file
user.avatar_transform_url("thumb")      # a named transform
user.purge_avatar                       # delete remotely, clear the column
```

Options: `column:` (default `<name>_file_id`), `dependent: :delete` (default; delete the file when
the record is destroyed or the attachment is replaced) or `false`, `verify: true` (default; an
id assigned from a form must be a ready file uploaded under this policy).

Staged uploads are checked against the policy locally before save, so a wrong content type or an
oversized file becomes a validation error, not a round trip.

### Browser-direct uploads

The browser talks to your app for the two control-plane calls (your app holds the API key) and
PUTs the bytes straight to storage.

```ruby
# config/routes.rb (the install generator adds this)
mount AssetHutch::Engine => "/asset_hutch"

# config/initializers/asset_hutch.rb — closed until you say who may upload
AssetHutch.config.authorize_direct_upload = ->(controller, policy) do
  controller.current_user.present? && %w[avatars documents].include?(policy)
end
```

The authorizer runs on both calls. On the first, `policy` is the one being requested. On the
second there is no policy in the request, so it is **looked up from the file being finalized** —
never taken from the client, which could otherwise name a policy it likes to finish an upload made
under one it may not use. An authorizer that only checks the user (`->(controller) { … }`) skips
that lookup, and so costs nothing extra.

Register the Stimulus controller (importmap users get the pin from the generator; jsbundling users
copy `app/assets/javascripts/asset_hutch/direct_upload_controller.js`):

```js
import DirectUploadController from "asset_hutch/direct_upload_controller"
application.register("asset-hutch-direct-upload", DirectUploadController)
```

```erb
<%= form_with model: @user do |f| %>
  <div data-controller="asset-hutch-direct-upload" data-asset-hutch-direct-upload-policy-value="avatars">
    <input type="file" accept="image/*" data-action="asset-hutch-direct-upload#upload">
    <%= f.hidden_field :avatar_file_id, data: { asset_hutch_direct_upload_target: "fileId" } %>
    <progress value="0" max="100" hidden data-asset-hutch-direct-upload-target="progress"></progress>
    <p data-asset-hutch-direct-upload-target="status"></p>
  </div>
  <%= f.submit %>
<% end %>
```

Submit buttons are disabled while uploading. The element dispatches `asset-hutch:start`,
`asset-hutch:progress`, `asset-hutch:complete`, and `asset-hutch:error`. `directUpload(file, { url,
policy, onProgress })` is exported for use without Stimulus.

On save, `has_asset_hutch_file` verifies the submitted id is a ready file under the declared policy,
so a client cannot attach someone else's upload to the wrong field.

### Coming from Active Storage

| Active Storage | asset_hutch |
| --- | --- |
| `has_one_attached :avatar` | `has_asset_hutch_file :avatar, policy: "avatars"` |
| `active_storage_blobs` + `attachments` tables | `users.avatar_file_id` |
| `url_for(user.avatar)` | `user.avatar_url` / `user.avatar_signed_url` |
| `user.avatar.variant(resize_to_fill: [200, 200])` | `user.avatar_transform_url("avatar")`, defined once in the dashboard |
| `user.avatar.purge` | `user.purge_avatar` |
| `DirectUpload` JS | `asset_hutch/direct_upload_controller` |
| service.yml, CORS, signed URL code | policies in the AssetHutch dashboard |

## Development

```sh
bundle install
bin/test                        # unit + dummy Rails app
bundle exec rubocop
```

Against a live AssetHutch — a project with a private `documents` policy, a public `avatars` policy,
and a public base URL on its storage connection:

```sh
export ASSET_HUTCH_URL=http://localhost:3000 ASSET_HUTCH_API_KEY=ah_…
export PDF_PATH=test/fixtures/files/sample.pdf IMAGE_PATH=test/fixtures/files/sample.png

bin/dogfood         # the client: the seven-step acceptance flow
bin/dogfood-rails   # everything built on it, through the dummy app
```

`bin/dogfood-rails` runs the Rails integration against a real server rather than WebMock:
attaching an upload and saving it, signed URLs from the record, a policy violation caught locally
before any round trip, replacement deleting the file it replaced, public URLs and named
transforms, the engine's endpoints refusing an unauthorized browser and never returning the API
key, an id uploaded under the wrong policy being refused, and `purge` deleting remotely.

Worth running before a release: it is what found the engine authorizing `complete` with no policy
at all, which the unit suite could not see because it only ever exercised `create` that way.

## Releasing

Bump `AssetHutch::VERSION`, write the entry in `CHANGELOG.md`, then tag:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

The release workflow refuses a tag that disagrees with the constant, runs the suite and RuboCop,
and publishes through RubyGems trusted publishing — no API key lives in this repository. Configure
it once at https://rubygems.org/gems/asset_hutch/trusted_publishers against this repository,
`.github/workflows/release.yml`, and the `rubygems` environment.

## License

MIT
