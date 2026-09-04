# frozen_string_literal: true

# WebMock stubs shaped exactly like the AssetHutch v1 API responses.
module ApiStubs
  BASE = "https://assethutch.test"
  STORAGE = "https://bucket.storage.test"
  FILE_ID = "file_abcdefghij0123456789"
  AUTH = { "Authorization" => "Bearer ah_testTESTtestTESTtestTESTtestTESTtestTEST" }.freeze

  def file_json(**overrides)
    {
      "id" => FILE_ID, "object" => "file", "filename" => "report.pdf", "content_type" => "application/pdf",
      "byte_size" => 11, "checksum" => "md5:abc", "visibility" => "private", "status" => "ready",
      "metadata" => {}, "policy" => "documents", "storage_connection_id" => "conn_x", "url" => nil, "transforms" => {},
      "created_at" => "2026-09-04T12:00:00.000Z", "updated_at" => "2026-09-04T12:00:01.000Z"
    }.merge(overrides.transform_keys(&:to_s))
  end

  def upload_json(id: FILE_ID)
    { "id" => id, "object" => "upload", "file_id" => id, "method" => "PUT", "url" => "#{STORAGE}/#{id}?sig=1",
      "headers" => { "Content-Type" => "application/pdf" }, "expires_at" => "2099-01-01T00:00:00.000Z" }
  end

  def project_json
    {
      "id" => "proj_x", "object" => "project", "name" => "Demo", "team_id" => "team_x", "storage_ready" => true,
      "active_storage_connection" => { "id" => "conn_x", "mode" => "managed", "provider" => "cloudflare_r2" },
      "upload_policies" => [
        { "id" => "pol_docs", "name" => "documents", "allowed_content_types" => [ "application/pdf" ], "maximum_size" => 25_000_000, "visibility" => "private" },
        { "id" => "pol_avatars", "name" => "avatars", "allowed_content_types" => [ "image/*" ], "maximum_size" => 5_000_000, "visibility" => "public" }
      ],
      "transforms" => [
        { "id" => "trn_avatar", "object" => "transform", "name" => "avatar", "width" => 200, "height" => 200, "fit" => "cover", "quality" => nil, "format" => "auto" },
        { "id" => "trn_thumb", "object" => "transform", "name" => "thumb", "width" => 400, "height" => nil, "fit" => "scale_down", "quality" => 80, "format" => "webp" }
      ],
      "created_at" => "2026-09-01T00:00:00.000Z"
    }
  end

  def error_json(code, message = "nope", details: nil)
    { "error" => { "code" => code, "message" => message, "details" => details }.compact }
  end

  def json(body, status = 200)
    { status: status, body: body.to_json, headers: { "Content-Type" => "application/json" } }
  end

  def stub_project = stub_request(:get, "#{BASE}/api/v1/project").with(headers: AUTH).to_return(json("project" => project_json))
  def stub_file(id = FILE_ID, **overrides) = stub_request(:get, "#{BASE}/api/v1/files/#{id}").with(headers: AUTH).to_return(json("file" => file_json(id: id, **overrides)))
  def stub_delete(id = FILE_ID) = stub_request(:delete, "#{BASE}/api/v1/files/#{id}").with(headers: AUTH).to_return(status: 204, body: "")

  def stub_transforms
    stub_request(:get, "#{BASE}/api/v1/transforms").with(headers: AUTH)
      .to_return(json("transforms" => project_json["transforms"]))
  end

  def stub_transform_url(id = FILE_ID, expires_at: "2026-09-04T13:00:00.000Z")
    stub_request(:post, "#{BASE}/api/v1/files/#{id}/transform_url").with(headers: AUTH)
      .to_return(json("url" => "#{STORAGE}/cdn-cgi/image/width=200/#{id}", "expires_at" => expires_at))
  end

  def stub_signed_url(id = FILE_ID)
    stub_request(:post, "#{BASE}/api/v1/files/#{id}/signed_url").with(headers: AUTH)
      .to_return(json("url" => "#{STORAGE}/#{id}?signed=1", "expires_at" => "2026-09-04T13:00:00.000Z"))
  end

  # Stubs the three legs of a direct upload. Returns the stubs so tests can assert on them.
  def stub_upload_flow(id: FILE_ID, **file_overrides)
    [
      stub_request(:post, "#{BASE}/api/v1/uploads").with(headers: AUTH)
        .to_return(json({ "upload" => upload_json(id: id), "file" => file_json(id: id, status: "pending", **file_overrides) }, 201)),
      stub_request(:put, "#{STORAGE}/#{id}?sig=1").to_return(status: 200, body: ""),
      stub_request(:post, "#{BASE}/api/v1/uploads/#{id}/complete").with(headers: AUTH)
        .to_return(json("file" => file_json(id: id, **file_overrides)))
    ]
  end
end
