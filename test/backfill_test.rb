# frozen_string_literal: true

require "test_helper"

class BackfillTest < ActiveSupport::TestCase
  ID2 = "file_ZYXWVUTSRQ9876543210"

  # Stands in for an Active Storage attachment: the backfill only needs
  # attached?, and a blob with key, filename, content_type and open.
  Blob = Struct.new(:key, :filename, :content_type) do
    def open = yield(StringIO.new("bytes of #{key}"))
  end

  Attachment = Struct.new(:blob) do
    def attached? = !blob.nil?
  end

  # A model with an Active Storage-shaped `legacy` beside has_hutch :report.
  class Record < ActiveRecord::Base
    self.table_name = "documents"
    has_hutch :report, policy: "documents", dependent: false, verify: false

    def legacy
      Attachment.new(legacy_ref && Blob.new(legacy_ref, "#{legacy_ref}.pdf", "application/pdf"))
    end
  end

  setup { Record.delete_all }

  test "streams each attached blob into FileHutch and fills the column" do
    uploads = stub_upload_flow
    with_blob = Record.create!(legacy_ref: "blob-key-1")
    without = Record.create!(legacy_ref: nil)

    result = FileHutch::Backfill.new(model: Record, from: :legacy, to: :report).call

    assert_equal [ 1, 1, 0 ], [ result.done, result.skipped, result.failed ]
    assert_equal ApiStubs::FILE_ID, with_blob.reload.report_file_id
    assert_nil without.reload.report_file_id
    assert_requested uploads.first, times: 1
  end

  test "with adopt_from, registers each blob where it is instead of copying it" do
    adopt = stub_request(:post, "#{ApiStubs::BASE}/api/v1/files/adopt").with(headers: ApiStubs::AUTH,
      body: hash_including("storage_connection" => "conn_as", "key" => "blob-key-1",
                           "filename" => "blob-key-1.pdf", "policy" => "documents"))
      .to_return(json({ "file" => file_json, "adopted" => true }, 201))
    record = Record.create!(legacy_ref: "blob-key-1")

    FileHutch::Backfill.new(model: Record, from: :legacy, to: :report, adopt_from: "conn_as").call

    assert_equal ApiStubs::FILE_ID, record.reload.report_file_id
    assert_requested adopt
    assert_not_requested :post, "#{ApiStubs::BASE}/api/v1/uploads"
  end

  test "rows already filled are left alone, so a second run only does what the first did not" do
    stub_upload_flow
    Record.create!(legacy_ref: "blob-key-1", report_file_id: ID2)

    result = FileHutch::Backfill.new(model: Record, from: :legacy, to: :report).call

    assert_equal 0, result.done
    assert_not_requested :post, "#{ApiStubs::BASE}/api/v1/uploads"
  end

  test "a file that fails is counted, left blank, and picked up by the next run" do
    stub_request(:post, "#{ApiStubs::BASE}/api/v1/uploads")
      .to_return(json({ "error" => { "code" => "policy_violation", "message" => "too big" } }, 422)).then
      .to_return(json({ "upload" => upload_json, "file" => file_json(status: "pending") }, 201))
    stub_request(:put, "#{ApiStubs::STORAGE}/#{ApiStubs::FILE_ID}?sig=1").to_return(status: 200, body: "")
    stub_request(:post, "#{ApiStubs::BASE}/api/v1/uploads/#{ApiStubs::FILE_ID}/complete").to_return(json("file" => file_json))
    record = Record.create!(legacy_ref: "blob-key-1")

    first = FileHutch::Backfill.new(model: Record, from: :legacy, to: :report).call
    assert_equal 1, first.failed
    assert_nil record.reload.report_file_id

    second = FileHutch::Backfill.new(model: Record, from: :legacy, to: :report).call
    assert_equal 1, second.done
    assert_equal ApiStubs::FILE_ID, record.reload.report_file_id
  end

  test "an attachment the model does not declare is refused up front" do
    assert_raises(ArgumentError) { FileHutch::Backfill.new(model: Record, from: :legacy, to: :nope) }
  end

  # A fresh Rake application, so the task can only come from the engine, which
  # loads its own lib/tasks: the gem's own Rakefile is not in the picture.
  test "the engine gives the app a file_hutch:backfill task" do
    require "rake"
    previous, Rake.application = Rake.application, Rake::Application.new

    Rails.application.load_tasks

    assert Rake::Task.task_defined?("file_hutch:backfill")
    assert_equal 1, Rake::Task["file_hutch:backfill"].actions.size,
      "the engine loads lib/tasks itself; loading it again as well would run a backfill twice"
  ensure
    Rake.application = previous
  end
end
