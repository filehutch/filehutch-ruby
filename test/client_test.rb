# frozen_string_literal: true

require "test_helper"

class ClientTest < ActiveSupport::TestCase
  setup { @client = Assethutch::Client.new }

  test "requires an api key" do
    error = assert_raises(Assethutch::ConfigurationError) { Assethutch::Client.new(api_key: nil) }
    assert_match(/ASSETHUTCH_API_KEY/, error.message)
  end

  test "keyword overrides win over the global configuration" do
    client = Assethutch::Client.new(url: "https://other.test/")
    stub_request(:get, "https://other.test/api/v1/project").to_return(json("project" => project_json))
    assert_equal "proj_x", client.project.id
  end

  test "project returns policies and storage info" do
    stub_project
    project = @client.project
    assert project.storage_ready?
    assert_equal "managed", project.storage_mode
    assert_equal %w[documents avatars], project.upload_policies.map(&:name)
    assert @client.project.upload_policy("avatars").allows_content_type?("image/png")
    assert_not @client.project.upload_policy("documents").allows_content_type?("image/png")
    assert_not @client.project.upload_policy("documents").allows_byte_size?(25_000_001)
  end

  test "file wraps the payload with typed accessors" do
    stub_file
    file = @client.file(ApiStubs::FILE_ID)
    assert_equal ApiStubs::FILE_ID, file.id
    assert file.ready?
    assert file.private?
    assert file.pdf?
    assert_nil file.url
    assert_equal Time.utc(2026, 9, 4, 12), file.created_at
    assert_equal ApiStubs::FILE_ID, file.to_param
    assert_equal file, Assethutch::File.new(file.to_h)
  end

  test "sends the user agent, bearer token, and json accept header" do
    stub = stub_request(:get, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}")
      .with(headers: ApiStubs::AUTH.merge("Accept" => "application/json", "User-Agent" => /assethutch-ruby\/#{Assethutch::VERSION}/))
      .to_return(json("file" => file_json))
    @client.file(ApiStubs::FILE_ID)
    assert_requested stub
  end

  test "upload runs the three steps and streams bytes straight to storage" do
    stub_upload_flow
    path = file_fixture("sample.pdf")
    file = @client.upload(path, policy: "documents", metadata: { order: 1 })

    assert file.ready?
    assert_requested(:post, "#{ApiStubs::BASE}/api/v1/uploads", times: 1) do |req|
      JSON.parse(req.body) == { "policy" => "documents", "filename" => "sample.pdf", "content_type" => "application/pdf", "byte_size" => 12, "metadata" => { "order" => 1 } }
    end
    assert_requested(:put, "#{ApiStubs::STORAGE}/#{ApiStubs::FILE_ID}?sig=1", times: 1) do |req|
      req.headers["Content-Type"] == "application/pdf" && req.headers["Content-Length"] == "12" && req.body == File.binread(path)
    end
    assert_requested :post, "#{ApiStubs::BASE}/api/v1/uploads/#{ApiStubs::FILE_ID}/complete"
  end

  test "upload accepts IOs, uploaded files, and raw bytes" do
    stub_upload_flow
    assert @client.upload(StringIO.new("%PDF-1.4 hi"), policy: "documents", filename: "a.pdf").ready?
    assert @client.upload("%PDF-1.4 hi".b, policy: "documents", filename: "a.pdf", content_type: "application/pdf").ready?
    uploaded = ActionDispatch::Http::UploadedFile.new(tempfile: File.open(file_fixture("sample.png"), "rb"), filename: "me.png", type: "image/png")
    assert @client.upload(uploaded, policy: "avatars").ready?
    assert_requested :post, "#{ApiStubs::BASE}/api/v1/uploads", times: 1 do |req|
      JSON.parse(req.body).values_at("filename", "content_type") == [ "me.png", "image/png" ]
    end
    assert_raises(ArgumentError) { @client.upload("%PDF".b, policy: "documents") }
    assert_raises(ArgumentError) { @client.upload(42, policy: "documents") }
  end

  test "upload guesses content types from the extension when Marcel is absent" do
    assert_equal "image/webp", Assethutch::Client::Source.guess_content_type(nil, "x.webp")
    assert_equal "application/octet-stream", Assethutch::Client::Source.guess_content_type(nil, "x.unknownext")
  end

  test "a storage rejection raises UploadError with the storage status" do
    stub_upload_flow
    stub_request(:put, "#{ApiStubs::STORAGE}/#{ApiStubs::FILE_ID}?sig=1").to_return(status: 403, body: "<Error>SignatureDoesNotMatch</Error>")
    error = assert_raises(Assethutch::UploadError) { @client.upload(file_fixture("sample.pdf"), policy: "documents") }
    assert_equal 403, error.status
    assert_equal "storage_rejected", error.code
    assert_match(/SignatureDoesNotMatch/, error.message)
    assert_not_requested :post, "#{ApiStubs::BASE}/api/v1/uploads/#{ApiStubs::FILE_ID}/complete"
  end

  test "signed_url returns url and expiry, and File#signed_url the url" do
    stub_signed_url
    signed = @client.signed_url(ApiStubs::FILE_ID, expires_in: 600, disposition: "attachment")
    assert_equal "#{ApiStubs::STORAGE}/#{ApiStubs::FILE_ID}?signed=1", signed.url
    assert_equal Time.utc(2026, 9, 4, 13), signed.expires_at
    assert_requested :post, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}/signed_url", body: { expires_in: 600, disposition: "attachment" }.to_json

    stub_file
    assert_equal signed.url, @client.file(ApiStubs::FILE_ID).signed_url
    assert_equal signed.url, Assethutch::File.new(file_json).url_or_signed_url
    assert_equal "https://pub.test/a.png", Assethutch::File.new(file_json(url: "https://pub.test/a.png")).url_or_signed_url
  end

  test "delete returns true and File#delete reloads as deleted" do
    stub_delete
    assert @client.delete_file(ApiStubs::FILE_ID)
    stub_file(status: "deleted")
    assert Assethutch::File.new(file_json, client: @client).delete.deleted?
  end

  test "accepts resources anywhere an id is expected and rejects junk ids" do
    stub_delete
    assert @client.delete_file(Assethutch::File.new(file_json))
    assert_raises(ArgumentError) { @client.file("") }
    assert_raises(ArgumentError) { @client.file("a/b") }
  end

  test "maps api error codes to typed errors" do
    {
      [ 401, "unauthorized" ] => Assethutch::AuthenticationError,
      [ 404, "not_found" ] => Assethutch::NotFoundError,
      [ 422, "invalid" ] => Assethutch::InvalidRequestError,
      [ 422, "policy_violation" ] => Assethutch::PolicyError,
      [ 409, "storage_not_ready" ] => Assethutch::StorageNotReadyError,
      [ 410, "already_deleted" ] => Assethutch::InvalidStateError,
      [ 409, "upload_incomplete" ] => Assethutch::UploadError,
      [ 502, "storage_error" ] => Assethutch::StorageError,
      [ 429, nil ] => Assethutch::RateLimitError,
      [ 500, nil ] => Assethutch::ServerError
    }.each do |(status, code), klass|
      body = code ? error_json(code, "boom", details: { "x" => 1 }) : nil
      stub_request(:get, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}").to_return(status: status, body: body&.to_json || "<html>", headers: { "Content-Type" => "application/json" })
      error = assert_raises(klass, "#{status} #{code}") { @client.file(ApiStubs::FILE_ID) }
      assert_equal status, error.status
      if code
        assert_equal code, error.code
        assert_equal({ "x" => 1 }, error.details)
        assert_equal "boom", error.message
      else
        assert_nil error.code
        assert_match(/HTTP #{status}/, error.message)
      end
    end
  end

  test "network failures become ConnectionError" do
    stub_request(:get, "#{ApiStubs::BASE}/api/v1/project").to_timeout
    error = assert_raises(Assethutch::ConnectionError) { @client.project }
    assert_match(/assethutch.test/, error.message)
    stub_request(:get, "#{ApiStubs::BASE}/api/v1/project").to_raise(Errno::ECONNREFUSED)
    assert_raises(Assethutch::ConnectionError) { @client.project }
  end

  test "module-level helpers use the shared client" do
    stub_file
    assert_equal ApiStubs::FILE_ID, Assethutch.file(ApiStubs::FILE_ID).id
    assert_equal ApiStubs::FILE_ID, Assethutch::File.find(ApiStubs::FILE_ID).id
    stub_project
    assert_equal "proj_x", Assethutch.project.id
    stub_upload_flow
    assert Assethutch.upload(file_fixture("sample.pdf"), policy: "documents").ready?
  end

  test "Upload#put and #complete drive the explicit flow" do
    stub_upload_flow
    upload = @client.create_upload(policy: "documents", filename: "a.pdf", content_type: "application/pdf", byte_size: 11)
    assert upload.file.pending?
    assert_equal "PUT", upload.method
    assert_not upload.expired?
    assert upload.put("%PDF-1.4 hi".b).complete.ready?
  end

  test "configure resets the shared client and logs requests" do
    io = StringIO.new
    Assethutch.configure { |c| c.logger = Logger.new(io) }
    stub_project
    Assethutch.project
    assert_match(/GET \/api\/v1\/project -> 200/, io.string)
  end

  test "transforms lists the project's named sizes" do
    stub_transforms
    transforms = @client.transforms

    assert_equal %w[avatar thumb], transforms.map(&:name)
    thumb = transforms.last
    assert_equal 400, thumb.width
    assert_nil thumb.height
    assert_equal "scale_down", thumb.fit
    assert_equal "webp", thumb.format
  end

  test "project exposes transforms by name alongside policies" do
    stub_project
    assert_equal 200, @client.project.transform("avatar").width
    assert_nil @client.project.transform("nope")
  end

  test "transform_url sends only the name and parses an expiring URL" do
    stub_transform_url
    result = @client.transform_url(ApiStubs::FILE_ID, transform: "avatar", expires_in: 600)

    assert_equal Time.utc(2026, 9, 4, 13), result.expires_at
    assert_match %r{/cdn-cgi/image/}, result.to_s
    assert_requested :post, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}/transform_url",
      body: { transform: "avatar", expires_in: 600 }.to_json
  end

  test "a public transform URL has no expiry" do
    stub_transform_url(expires_at: nil)
    assert_nil @client.transform_url(ApiStubs::FILE_ID, transform: "avatar").expires_at
  end

  test "a public image serves transform URLs off the payload without another request" do
    stub_file(visibility: "public", content_type: "image/png",
      transforms: { "avatar" => "https://cdn.test/cdn-cgi/image/width=200/x.png" })

    assert_equal "https://cdn.test/cdn-cgi/image/width=200/x.png", @client.file(ApiStubs::FILE_ID).transform_url("avatar")
    assert_not_requested :post, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}/transform_url"
  end

  test "a private image falls through to the API for a signed transform URL" do
    stub_file(content_type: "image/png")
    stub_transform_url

    assert_match %r{/cdn-cgi/image/}, @client.file(ApiStubs::FILE_ID).transform_url("avatar", expires_in: 60)
    assert_requested :post, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}/transform_url"
  end

  test "transform errors map to typed exceptions" do
    stub_file(content_type: "image/png")
    stub_request(:post, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}/transform_url")
      .to_return(json(error_json("transforms_unsupported", "Amazon S3 cannot render image transforms."), 409))

    error = assert_raises(Assethutch::TransformsUnsupportedError) { @client.file(ApiStubs::FILE_ID).transform_url("avatar") }
    assert_match(/cannot render image transforms/, error.message)
    assert_kind_of Assethutch::TransformError, error

    stub_request(:post, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}/transform_url")
      .to_return(json(error_json("transform_not_found", "No transform named \"nope\""), 422))
    assert_raises(Assethutch::TransformError) { @client.file(ApiStubs::FILE_ID).transform_url("nope") }
  end
end
