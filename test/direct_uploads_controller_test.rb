# frozen_string_literal: true

require "test_helper"

class DirectUploadsControllerTest < ActionDispatch::IntegrationTest
  PARAMS = { policy: "avatars", filename: "me.png", content_type: "image/png", byte_size: 11 }.freeze

  test "routes are mounted under the engine" do
    assert_equal "/asset_hutch/uploads", asset_hutch.uploads_path
    assert_equal "/asset_hutch/uploads/#{ApiStubs::FILE_ID}/complete", asset_hutch.complete_upload_path(ApiStubs::FILE_ID)
  end

  test "is closed until an authorizer is configured" do
    post "/asset_hutch/uploads", params: PARAMS, as: :json, headers: { "X-User" => "andy" }
    assert_response :forbidden
    assert_match(/authorize_direct_upload/, response.parsed_body.dig("error", "message"))
  end

  test "the authorizer sees the controller and the policy" do
    AssetHutch.config.authorize_direct_upload = ->(controller, policy) { controller.current_user == "andy" && policy == "avatars" }
    stub_upload_flow

    post "/asset_hutch/uploads", params: PARAMS, as: :json
    assert_response :forbidden

    post "/asset_hutch/uploads", params: PARAMS.merge(policy: "documents"), as: :json, headers: { "X-User" => "andy" }
    assert_response :forbidden

    post "/asset_hutch/uploads", params: PARAMS, as: :json, headers: { "X-User" => "andy" }
    assert_response :created
    body = response.parsed_body
    assert_equal ApiStubs::FILE_ID, body.dig("upload", "id")
    assert_equal "PUT", body.dig("upload", "method")
    assert_equal "pending", body.dig("file", "status")
    assert_requested :post, "#{ApiStubs::BASE}/api/v1/uploads", body: PARAMS.to_json
  end

  test "a one-argument authorizer works too" do
    AssetHutch.config.authorize_direct_upload = ->(controller) { controller.current_user.present? }
    stub_upload_flow
    post "/asset_hutch/uploads/#{ApiStubs::FILE_ID}/complete", headers: { "X-User" => "andy" }
    assert_response :success
    assert_equal "ready", response.parsed_body.dig("file", "status")
  end

  test "api errors pass through with their status and code" do
    AssetHutch.config.authorize_direct_upload = ->(*) { true }
    stub_request(:post, "#{ApiStubs::BASE}/api/v1/uploads").to_return(json(error_json("policy_violation", "too big"), 422))
    post "/asset_hutch/uploads", params: PARAMS, as: :json
    assert_response :unprocessable_entity
    assert_equal({ "code" => "policy_violation", "message" => "too big" }, response.parsed_body["error"])

    # An authorizer declared with a splat is handed the policy like any other,
    # so completing looks the file up to find out what it was uploaded under.
    stub_file
    stub_request(:post, "#{ApiStubs::BASE}/api/v1/uploads/#{ApiStubs::FILE_ID}/complete").to_timeout
    post "/asset_hutch/uploads/#{ApiStubs::FILE_ID}/complete"
    assert_response :unprocessable_entity
    assert_equal "error", response.parsed_body.dig("error", "code")
  end

  test "missing params are a 400" do
    AssetHutch.config.authorize_direct_upload = ->(*) { true }
    post "/asset_hutch/uploads", params: { policy: "avatars" }, as: :json
    assert_response :bad_request
  end

  test "the stimulus controller ships as an asset" do
    path = AssetHutch::Engine.root.join("app/assets/javascripts/asset_hutch/direct_upload_controller.js")
    assert path.exist?
    assert_match(/export default class extends Controller/, path.read)
    assert_match(/export async function directUpload/, path.read)
  end

  test "complete authorizes against the policy the file was actually uploaded under" do
    AssetHutch.config.authorize_direct_upload = ->(controller, policy) { controller.current_user == "andy" && policy == "avatars" }
    stub_upload_flow
    stub_file(ApiStubs::FILE_ID, policy: "avatars")

    post "/asset_hutch/uploads/#{ApiStubs::FILE_ID}/complete", as: :json, headers: { "X-User" => "andy" }
    assert_response :success

    # The policy is looked up, never taken from the client, so naming an allowed
    # one cannot finalize an upload made under a policy the user may not use.
    stub_file(ApiStubs::FILE_ID, policy: "documents")
    post "/asset_hutch/uploads/#{ApiStubs::FILE_ID}/complete", params: { policy: "avatars" }, as: :json, headers: { "X-User" => "andy" }
    assert_response :forbidden
  end

  test "an authorizer that only checks the user costs no policy lookup on complete" do
    AssetHutch.config.authorize_direct_upload = ->(controller) { controller.current_user == "andy" }
    stub_upload_flow

    post "/asset_hutch/uploads/#{ApiStubs::FILE_ID}/complete", as: :json, headers: { "X-User" => "andy" }
    assert_response :success
    assert_not_requested :get, "#{ApiStubs::BASE}/api/v1/files/#{ApiStubs::FILE_ID}"
  end
end
