# frozen_string_literal: true

require "test_helper"

class ClientTest < ActiveSupport::TestCase
  setup { @client = Assetboar::Client.new }

  test "requires an api key" do
    error = assert_raises(Assetboar::ConfigurationError) { Assetboar::Client.new(api_key: nil) }
    assert_match(/ASSETBOAR_API_KEY/, error.message)
  end

  test "keyword overrides win over the global configuration" do
    client = Assetboar::Client.new(url: "https://other.test/")
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
    assert_equal file, Assetboar::File.new(file.to_h)
  end

  test "sends the user agent, bearer token, and json accept header" do
    stub = stub_request(:get, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}")
      .with(headers: ApiStubs::AUTH.merge("Accept" => "application/json", "User-Agent" => /assetboar-ruby\/#{Assetboar::VERSION}/))
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
    assert_equal "image/webp", Assetboar::Client::Source.guess_content_type(nil, "x.webp")
    assert_equal "application/octet-stream", Assetboar::Client::Source.guess_content_type(nil, "x.unknownext")
  end

  test "a storage rejection raises UploadError with the storage status" do
    stub_upload_flow
    stub_request(:put, "#{ApiStubs::STORAGE}/#{ApiStubs::FILE_ID}?sig=1").to_return(status: 403, body: "<Error>SignatureDoesNotMatch</Error>")
    error = assert_raises(Assetboar::UploadError) { @client.upload(file_fixture("sample.pdf"), policy: "documents") }
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
    assert_equal signed.url, Assetboar::File.new(file_json).url_or_signed_url
    assert_equal "https://pub.test/a.png", Assetboar::File.new(file_json(url: "https://pub.test/a.png")).url_or_signed_url
  end

  test "delete returns true and File#delete reloads as deleted" do
    stub_delete
    assert @client.delete_file(ApiStubs::FILE_ID)
    stub_file(status: "deleted")
    assert Assetboar::File.new(file_json, client: @client).delete.deleted?
  end

  test "accepts resources anywhere an id is expected and rejects junk ids" do
    stub_delete
    assert @client.delete_file(Assetboar::File.new(file_json))
    assert_raises(ArgumentError) { @client.file("") }
    assert_raises(ArgumentError) { @client.file("a/b") }
  end

  test "maps api error codes to typed errors" do
    {
      [ 401, "unauthorized" ] => Assetboar::AuthenticationError,
      [ 404, "not_found" ] => Assetboar::NotFoundError,
      [ 422, "invalid" ] => Assetboar::InvalidRequestError,
      [ 422, "policy_violation" ] => Assetboar::PolicyError,
      [ 409, "storage_not_ready" ] => Assetboar::StorageNotReadyError,
      [ 410, "already_deleted" ] => Assetboar::InvalidStateError,
      [ 409, "upload_incomplete" ] => Assetboar::UploadError,
      [ 502, "storage_error" ] => Assetboar::StorageError,
      [ 429, nil ] => Assetboar::RateLimitError,
      [ 500, nil ] => Assetboar::ServerError
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
    error = assert_raises(Assetboar::ConnectionError) { @client.project }
    assert_match(/assetboar.test/, error.message)
    stub_request(:get, "#{ApiStubs::BASE}/api/v1/project").to_raise(Errno::ECONNREFUSED)
    assert_raises(Assetboar::ConnectionError) { @client.project }
  end

  test "module-level helpers use the shared client" do
    stub_file
    assert_equal ApiStubs::FILE_ID, Assetboar.file(ApiStubs::FILE_ID).id
    assert_equal ApiStubs::FILE_ID, Assetboar::File.find(ApiStubs::FILE_ID).id
    stub_project
    assert_equal "proj_x", Assetboar.project.id
    stub_upload_flow
    assert Assetboar.upload(file_fixture("sample.pdf"), policy: "documents").ready?
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
    Assetboar.configure { |c| c.logger = Logger.new(io) }
    stub_project
    Assetboar.project
    assert_match(/GET \/api\/v1\/project -> 200/, io.string)
  end
end
