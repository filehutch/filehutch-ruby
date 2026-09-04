# assetboar

Ruby and Rails client for [AssetBoar](https://assetboar.com), file infrastructure for apps that
aren't Netflix. Your app persists an opaque file id (`file_…`). AssetBoar owns uploads, private
files, signed URLs, and delivery. Your storage, or AssetBoar's, sits behind it.

```ruby
file = Assetboar.upload("report.pdf", policy: "documents")   # bytes go straight to storage
file.id                       # => "file_8fK2…"  ← the only thing you store
file.signed_url(expires_in: 600)
Assetboar::File.find(file.id).delete
```

Stdlib only at runtime. Rails integration switches on when Rails is present.

## Install

```ruby
gem "assetboar"
```

```sh
bin/rails generate assetboar:install     # initializer, mounts the engine, importmap pin
export ASSETBOAR_API_KEY=ab_…             # Dashboard → API keys (project-scoped)
export ASSETBOAR_URL=https://…            # only when not using AssetBoar cloud
```

Without Rails: `Assetboar.configure { |c| c.api_key = "ab_…" }`.

## Client

```ruby
client = Assetboar.client                       # or Assetboar::Client.new(api_key:, url:)

client.project                                  # => Assetboar::Project (storage status, policies)
client.upload(path_or_io, policy: "documents", metadata: { order_id: "ord_1" })
client.file("file_…")                           # => Assetboar::File
client.signed_url("file_…", expires_in: 3600, disposition: "attachment")  # => SignedUrl(url, expires_at)
client.delete_file("file_…")                    # => true; the id then reads as status "deleted"

# The three steps, explicit:
upload = client.create_upload(policy: "avatars", filename: "me.png", content_type: "image/png", byte_size: bytes.bytesize)
upload.put(bytes).complete                      # => ready Assetboar::File
```

`upload` accepts a path, `Pathname`, `File`, `Tempfile`, `StringIO`, an
`ActionDispatch::Http::UploadedFile`, or raw bytes with `filename:`. Content type comes from the
source, then Marcel if loaded, then the extension.

`Assetboar::File`: `id filename content_type byte_size checksum visibility status metadata policy
url created_at`, plus `ready? pending? failed? deleted? public? private? image? pdf?`,
`signed_url`, `url_or_signed_url`, `reload`, `delete`.

### Errors

Every failure is an `Assetboar::Error`. API errors carry `code`, `status`, and `details`.

| Class | When |
| --- | --- |
| `ConfigurationError` | no API key / URL |
| `ConnectionError` | timeout, DNS, reset |
| `AuthenticationError` | 401 |
| `NotFoundError` | unknown id |
| `InvalidRequestError` → `PolicyError` | bad params; content type or size the policy refuses |
| `StorageNotReadyError` | project has no verified storage |
| `InvalidStateError` | not ready, already deleted, not public |
| `UploadError` | storage rejected the PUT, upload expired or incomplete, size mismatch |
| `StorageError` | AssetBoar could not reach the bucket |
| `RateLimitError`, `ServerError` | 429, 5xx |

## Rails

### Model

One string column per attachment. Nothing about storage lands in your schema.

```sh
bin/rails generate assetboar:attachment User avatar    # adds users.avatar_file_id
```

```ruby
class User < ApplicationRecord
  has_assetboar_file :avatar, policy: "avatars"
  has_assetboar_file :contract, policy: "documents", dependent: false
end

user.avatar = params[:avatar]           # uploaded IO → uploaded to storage on save
user.avatar = "file_…"                  # id from a browser direct upload → verified on save
user.avatar                             # => Assetboar::File or nil (fetched lazily, cached)
user.avatar?                            # id present
user.avatar_url                         # public URL (public policies only)
user.avatar_signed_url(expires_in: 600) # any file
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
mount Assetboar::Engine => "/assetboar"

# config/initializers/assetboar.rb — closed until you say who may upload
Assetboar.config.authorize_direct_upload = ->(controller, policy) do
  controller.current_user.present? && %w[avatars documents].include?(policy)
end
```

Register the Stimulus controller (importmap users get the pin from the generator; jsbundling users
copy `app/assets/javascripts/assetboar/direct_upload_controller.js`):

```js
import DirectUploadController from "assetboar/direct_upload_controller"
application.register("assetboar-direct-upload", DirectUploadController)
```

```erb
<%= form_with model: @user do |f| %>
  <div data-controller="assetboar-direct-upload" data-assetboar-direct-upload-policy-value="avatars">
    <input type="file" accept="image/*" data-action="assetboar-direct-upload#upload">
    <%= f.hidden_field :avatar_file_id, data: { assetboar_direct_upload_target: "fileId" } %>
    <progress value="0" max="100" hidden data-assetboar-direct-upload-target="progress"></progress>
    <p data-assetboar-direct-upload-target="status"></p>
  </div>
  <%= f.submit %>
<% end %>
```

Submit buttons are disabled while uploading. The element dispatches `assetboar:start`,
`assetboar:progress`, `assetboar:complete`, and `assetboar:error`. `directUpload(file, { url,
policy, onProgress })` is exported for use without Stimulus.

On save, `has_assetboar_file` verifies the submitted id is a ready file under the declared policy,
so a client cannot attach someone else's upload to the wrong field.

### Coming from Active Storage

| Active Storage | assetboar |
| --- | --- |
| `has_one_attached :avatar` | `has_assetboar_file :avatar, policy: "avatars"` |
| `active_storage_blobs` + `attachments` tables | `users.avatar_file_id` |
| `url_for(user.avatar)` | `user.avatar_url` / `user.avatar_signed_url` |
| `user.avatar.purge` | `user.purge_avatar` |
| `DirectUpload` JS | `assetboar/direct_upload_controller` |
| service.yml, CORS, signed URL code | policies in the AssetBoar dashboard |

## Development

```sh
bundle install
bin/test                        # unit + dummy Rails app
bundle exec rubocop

# Against a live AssetBoar (project with private "documents" and public "avatars" policies):
ASSETBOAR_URL=http://localhost:3000 ASSETBOAR_API_KEY=ab_… \
  PDF_PATH=test/fixtures/files/sample.pdf IMAGE_PATH=test/fixtures/files/sample.png bin/dogfood
```

## License

MIT
