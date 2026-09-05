# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class CLITest < ActiveSupport::TestCase
  CONFIG = { "uploads" => { "exports" => { "types" => [ "text/csv" ], "max_size" => "1MB" } } }.freeze

  def run_cli(*argv, input: "")
    out, err = StringIO.new, StringIO.new
    status = FileHutch::CLI.new(argv, out: out, err: err, input: StringIO.new(input)).run
    [ status, out.string, err.string ]
  end

  def with_config_file(config = CONFIG)
    Dir.mktmpdir do |dir|
      path = ::File.join(dir, "file_hutch.yml")
      ::File.write(path, YAML.dump(config))
      yield path
    end
  end

  def plan_json(changes, prune: false)
    summary = %w[create update delete noop].to_h { |a| [ a, changes.count { |c| c["action"] == a } ] }
    { "plan" => { "prune" => prune, "changes" => changes, "summary" => summary } }
  end

  test "help and version" do
    assert_equal [ 0, true ], run_cli.then { |s, out, _| [ s, out.include?("Usage: file_hutch") ] }
    assert_equal [ 0, "file_hutch #{FileHutch::VERSION}\n" ], run_cli("version").first(2)
    status, _, err = run_cli("dance")
    assert_equal 2, status
    assert_match(/Unknown command "dance"/, err)
  end

  test "plan prints one line per change and a summary" do
    stub_request(:post, "#{ApiStubs::BASE}/api/v1/config/plan").to_return(json(plan_json([
      { "resource" => "upload_policy", "name" => "exports", "action" => "create", "to" => {} },
      { "resource" => "upload_policy", "name" => "avatars", "action" => "update", "diff" => { "maximum_size" => [ 5_242_880, 10_485_760 ] } },
      { "resource" => "transform", "name" => "hero", "action" => "delete" },
      { "resource" => "environment", "name" => "production", "action" => "noop" }
    ], prune: true)))

    with_config_file do |path|
      status, out, err = run_cli("plan", path, "--prune")
      assert_equal 0, status, err
      assert_equal <<~TEXT, out
        + upload_policy exports
        ~ upload_policy avatars  maximum_size: 5242880 → 10485760
        - transform hero
        = 1 unchanged
        Plan: 1 to create, 1 to update, 1 to delete.
      TEXT
    end
    assert_requested(:post, "#{ApiStubs::BASE}/api/v1/config/plan") { |req| body = JSON.parse(req.body); body["prune"] == true && body["config"] == CONFIG }
  end

  test "apply reports each line and exits non-zero when something failed" do
    stub_request(:post, "#{ApiStubs::BASE}/api/v1/config/apply").to_return(json("apply" => {
      "prune" => false,
      "results" => [
        { "resource" => "upload_policy", "name" => "exports", "action" => "create", "status" => "applied" },
        { "resource" => "environment", "name" => "review", "action" => "create", "status" => "failed", "error" => "The Small plan has one environment per project." }
      ],
      "summary" => { "applied" => 1, "failed" => 1, "noop" => 3 }
    }))

    with_config_file do |path|
      status, out, = run_cli("apply", path)
      assert_equal 1, status
      assert_match(/\+ upload_policy exports  ok/, out)
      assert_match(/\+ environment review  FAILED: The Small plan/, out)
      assert_match(/Applied 1, failed 1, unchanged 3\./, out)
    end
  end

  test "apply --prune asks before deleting unless --yes" do
    stub_request(:post, "#{ApiStubs::BASE}/api/v1/config/plan").to_return(json(plan_json([
      { "resource" => "transform", "name" => "hero", "action" => "delete" }
    ], prune: true)))
    apply = stub_request(:post, "#{ApiStubs::BASE}/api/v1/config/apply").to_return(json("apply" => {
      "prune" => true, "results" => [ { "resource" => "transform", "name" => "hero", "action" => "delete", "status" => "applied" } ],
      "summary" => { "applied" => 1, "failed" => 0, "noop" => 0 }
    }))

    with_config_file do |path|
      status, out, = run_cli("apply", path, "--prune", input: "n\n")
      assert_equal 1, status
      assert_match(/Delete 1 resource\? \[y\/N\]/, out)
      assert_match(/Nothing applied/, out)
      assert_not_requested apply

      status, = run_cli("apply", path, "--prune", input: "y\n")
      assert_equal 0, status
      assert_requested apply, times: 1

      status, = run_cli("apply", path, "--prune", "--yes")
      assert_equal 0, status
      assert_requested apply, times: 2
    end
  end

  test "a missing or malformed config file is a usage error" do
    status, _, err = run_cli("plan", "/nope/file_hutch.yml")
    assert_equal 2, status
    assert_match(/No config file at \/nope/, err)

    Dir.mktmpdir do |dir|
      path = ::File.join(dir, "file_hutch.yml")
      ::File.write(path, "- just\n- a list\n")
      status, _, err = run_cli("plan", path)
      assert_equal 2, status
      assert_match(/must be a YAML mapping/, err)
    end
  end

  test "export prints the config as YAML" do
    stub_request(:get, "#{ApiStubs::BASE}/api/v1/config").to_return(json("config" => {
      "uploads" => { "documents" => { "types" => [ "application/pdf" ], "max_size" => 26_214_400, "visibility" => "private" } },
      "transforms" => {}, "environments" => [ "production" ]
    }))
    status, out, = run_cli("export")
    assert_equal 0, status
    assert_equal({ "uploads" => { "documents" => { "types" => [ "application/pdf" ], "max_size" => 26_214_400, "visibility" => "private" } },
                   "transforms" => {}, "environments" => [ "production" ] }, YAML.safe_load(out))
    assert_not out.start_with?("---")
  end

  test "inspect summarizes the project" do
    stub_request(:get, "#{ApiStubs::BASE}/api/v1/project").to_return(json("project" => project_json.merge(
      "environment" => { "id" => "env_x", "name" => "staging" }, "environments" => %w[production staging],
      "plan" => { "key" => "pro", "name" => "Pro", "storage_bytes" => 300 * 1024**3, "project_limit" => 10 },
      "usage" => { "storage_bytes_used" => 5 * 1024**2, "projects_used" => 2 }
    )))
    status, out, = run_cli("inspect")
    assert_equal 0, status
    assert_match(/Demo \(proj_x\)/, out)
    assert_match(/environment: staging of production, staging/, out)
    assert_match(/storage:\s+cloudflare_r2 \(managed\)/, out)
    assert_match(/plan:\s+Pro, 5\.0 MB of 300 GB used, 2 of 10 projects/, out)
    assert_match(/policies:\s+documents \(private, 24 MB\), avatars \(public, 4\.8 MB\)/, out)
    assert_match(/transforms:\s+avatar, thumb/, out)
  end

  test "upload runs the three-step flow and prints the id" do
    stub_request(:post, "#{ApiStubs::BASE}/api/v1/uploads").to_return(json("upload" => upload_json, "file" => file_json(status: "pending")))
    stub_request(:put, "#{ApiStubs::STORAGE}/#{ApiStubs::FILE_ID}?sig=1").to_return(status: 200)
    stub_request(:post, "#{ApiStubs::BASE}/api/v1/uploads/#{ApiStubs::FILE_ID}/complete").to_return(json("file" => file_json))

    status, out, = run_cli("upload", file_fixture("sample.pdf").to_s, "--policy", "documents")
    assert_equal 0, status
    assert_equal "#{ApiStubs::FILE_ID}\n", out

    status, _, err = run_cli("upload", file_fixture("sample.pdf").to_s)
    assert_equal 2, status
    assert_match(/--policy NAME/, err)
  end

  test "manifest follows pages and prints one JSON object per line" do
    stub_request(:get, "#{ApiStubs::BASE}/api/v1/manifest").to_return(json(
      "object" => "manifest", "files" => [ { "id" => "file_1", "storage" => { "key" => "k/1" } } ], "has_more" => true, "next_after" => "file_1"
    ))
    stub_request(:get, "#{ApiStubs::BASE}/api/v1/manifest?after=file_1").to_return(json(
      "object" => "manifest", "files" => [ { "id" => "file_2", "storage" => { "key" => "k/2" } } ], "has_more" => false, "next_after" => nil
    ))
    status, out, = run_cli("manifest")
    assert_equal 0, status
    assert_equal %w[file_1 file_2], out.lines.map { JSON.parse(_1)["id"] }
  end

  test "api and configuration errors are short and exit non-zero" do
    stub_request(:get, "#{ApiStubs::BASE}/api/v1/config").to_return(status: 403, body: error_json("read_only_key", "This API key is read-only").to_json, headers: { "Content-Type" => "application/json" })
    status, _, err = run_cli("export")
    assert_equal 1, status
    assert_match(/FileHutch said no \(read_only_key\): This API key is read-only/, err)

    FileHutch.config.api_key = nil
    status, _, err = run_cli("inspect")
    assert_equal 2, status
    assert_match(/FILE_HUTCH_API_KEY/, err)
  end
end
