# frozen_string_literal: true

require "test_helper"

class AttachableTest < ActiveSupport::TestCase
  ID2 = "file_ZYXWVUTSRQ9876543210"

  test "declares the attachment on the model" do
    assert_equal %w[documents avatars], Document.file_hutch_files.values.map { |o| o[:policy] }
    assert_equal "report_file_id", Document.file_hutch_files[:report][:column]
    assert_respond_to Document.new, :report_signed_url
  end

  test "uploads a staged IO on save and stores only the file id" do
    stub_project
    stub_upload_flow
    doc = Document.new(title: "Q1")
    doc.report = File.open(file_fixture("sample.pdf"), "rb")
    assert_nil doc.report_file_id, "nothing hits the network before save"
    assert_not_requested :post, "#{ApiStubs::BASE}/api/v1/uploads"

    assert doc.save
    assert_equal ApiStubs::FILE_ID, doc.report_file_id
    assert doc.report?
    assert_equal "report.pdf", doc.report.filename, "the completed file is cached, no extra GET"
    assert_not_requested :get, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}"
    assert_requested(:post, "#{ApiStubs::BASE}/api/v1/uploads") { |req| JSON.parse(req.body)["policy"] == "documents" }
  end

  test "rejects a staged file that the policy would refuse, without uploading" do
    stub_project
    doc = Document.new(title: "Bad")
    doc.report = ActionDispatch::Http::UploadedFile.new(tempfile: File.open(file_fixture("sample.png"), "rb"), filename: "me.png", type: "image/png")
    assert_not doc.save
    assert_match(/image\/png is not allowed/, doc.errors[:report].first)
    assert_not_requested :post, "#{ApiStubs::BASE}/api/v1/uploads"
  end

  test "policy checks are skipped when the project cannot be loaded; the server still decides" do
    stub_request(:get, "#{ApiStubs::BASE}/api/v1/project").to_return(status: 500)
    stub_upload_flow
    doc = Document.new(title: "Offline")
    doc.report = File.open(file_fixture("sample.pdf"), "rb")
    assert doc.save
  end

  test "assigning a direct-upload id verifies it is a ready file under the right policy" do
    stub_file(status: "pending")
    doc = Document.new(title: "Direct", report: ApiStubs::FILE_ID)
    assert_not doc.valid?
    assert_equal [ "Report upload is pending" ], doc.errors.full_messages

    stub_file(policy: "avatars")
    doc = Document.new(title: "Direct", report: ApiStubs::FILE_ID)
    assert_not doc.valid?
    assert_match(/avatars policy/, doc.errors[:report].first)

    stub_request(:get, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}").to_return(json(error_json("not_found"), 404))
    assert_not Document.new(report: ApiStubs::FILE_ID).valid?

    WebMock.reset_executed_requests!
    stub_file
    doc = Document.new(title: "Direct", report: ApiStubs::FILE_ID)
    assert doc.save
    assert_equal ApiStubs::FILE_ID, doc.report_file_id
    assert_requested :get, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}", times: 1
  end

  test "verify: false trusts the id" do
    doc = Document.new(avatar: ApiStubs::FILE_ID)
    assert doc.save
    assert_raises(ArgumentError) { doc.avatar = "not-an-id" }
    assert_raises(ArgumentError) { doc.avatar = 12 }
  end

  test "reader fetches lazily, caches, and returns nil for unknown ids" do
    doc = Document.create!(avatar: ApiStubs::FILE_ID)
    stub_file
    assert_equal ApiStubs::FILE_ID, doc.avatar.id
    doc.avatar
    assert_requested :get, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}", times: 1
    doc.reload.avatar
    assert_requested :get, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}", times: 2

    stub_request(:get, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}").to_return(json(error_json("not_found"), 404))
    assert_nil doc.reload.avatar
    assert_nil Document.new.avatar
    assert_nil Document.new.avatar_url
    assert_nil Document.new.avatar_signed_url
    assert_nil Document.new.avatar_transform_url("thumb")
  end

  test "url helpers" do
    doc = Document.new(avatar: ApiStubs::FILE_ID)
    stub_file(visibility: "public", url: "https://pub.test/me.png")
    stub_signed_url
    assert_equal "https://pub.test/me.png", doc.avatar_url
    assert_equal "#{ApiStubs::STORAGE}/#{ApiStubs::FILE_ID}?signed=1", doc.avatar_signed_url(expires_in: 60)
    assert_requested :post, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}/signed_url", body: { expires_in: 60 }.to_json
  end

  test "transform url helper names a transform and nothing else" do
    doc = Document.new(avatar: ApiStubs::FILE_ID)
    stub_file(visibility: "public", content_type: "image/png", url: "https://pub.test/me.png",
      transforms: { "thumb" => "https://pub.test/cdn-cgi/image/width=400/me.png" })

    assert_equal "https://pub.test/cdn-cgi/image/width=400/me.png", doc.avatar_transform_url("thumb")

    stub_transform_url
    assert_match %r{/cdn-cgi/image/}, doc.avatar_transform_url("avatar", expires_in: 60)
    assert_requested :post, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}/transform_url",
      body: { transform: "avatar", expires_in: 60 }.to_json
  end

  test "assigning an FileHutch::File uses it without refetching" do
    doc = Document.new(report: FileHutch::File.new(file_json))
    assert doc.save
    assert_equal ApiStubs::FILE_ID, doc.report_file_id
    assert_not_requested :get, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}"
  end

  test "replacing a file deletes the old one after save when dependent: :delete" do
    doc = Document.create!(report: FileHutch::File.new(file_json))
    stub_delete
    doc.report = FileHutch::File.new(file_json(id: ID2))
    assert_not_requested :delete, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}"
    doc.save!
    assert_requested :delete, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}"
    assert_equal ID2, doc.report_file_id
  end

  test "clearing deletes the old file; dependent: false leaves it alone" do
    doc = Document.create!(report: FileHutch::File.new(file_json), avatar: ID2)
    stub_delete
    doc.report = nil
    doc.avatar = nil
    doc.save!
    assert_requested :delete, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}"
    assert_not_requested :delete, "#{ApiStubs::BASE}/api/v1/files/#{ID2}"
    assert_not doc.report?
  end

  test "destroying the record deletes the file, tolerating an already-deleted file" do
    doc = Document.create!(report: FileHutch::File.new(file_json), avatar: ID2)
    stub_request(:delete, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}").to_return(json(error_json("already_deleted"), 410))
    doc.destroy!
    assert_requested :delete, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}"
    assert_not_requested :delete, "#{ApiStubs::BASE}/api/v1/files/#{ID2}"
  end

  test "purge deletes remotely and clears the column immediately" do
    doc = Document.create!(report: FileHutch::File.new(file_json))
    stub_delete
    assert doc.purge_report
    assert_nil doc.report_file_id
    assert_nil doc.reload.report_file_id
    assert_requested :delete, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}"
  end

  test "a failed save does not leave a half-assigned id" do
    stub_project
    stub_upload_flow
    stub_request(:post, "#{ApiStubs::BASE}/api/v1/uploads").to_return(json(error_json("storage_not_ready", "no bucket"), 409))
    doc = Document.new(title: "x")
    doc.report = File.open(file_fixture("sample.pdf"), "rb")
    assert_raises(FileHutch::StorageNotReadyError) { doc.save }
    assert_nil doc.report_file_id
    assert_not doc.persisted?
  end
end
