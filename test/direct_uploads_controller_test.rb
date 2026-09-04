# frozen_string_literal: true

require "test_helper"

class DirectUploadsControllerTest < ActionDispatch::IntegrationTest
  PARAMS = { policy: "avatars", filename: "me.png", content_type: "image/png", byte_size: 11 }.freeze

  test "routes are mounted under the engine" do
    assert_equal "/assetboar/uploads", assetboar.uploads_path
    assert_equal "/assetboar/uploads/#{ApiStubs::FILE_ID}/complete", assetboar.complete_upload_path(ApiStubs::FILE_ID)
  end

  test "is closed until an authorizer is configured" do
    post "/assetboar/uploads", params: PARAMS, as: :json, headers: { "X-User" => "andy" }
    assert_response :forbidden
    assert_match(/authorize_direct_upload/, response.parsed_body.dig("error", "message"))
  end

  test "the authorizer sees the controller and the policy" do
    Assetboar.config.authorize_direct_upload = ->(controller, policy) { controller.current_user == "andy" && policy == "avatars" }
    stub_upload_flow

    post "/assetboar/uploads", params: PARAMS, as: :json
    assert_response :forbidden

    post "/assetboar/uploads", params: PARAMS.merge(policy: "documents"), as: :json, headers: { "X-User" => "andy" }
    assert_response :forbidden

    post "/assetboar/uploads", params: PARAMS, as: :json, headers: { "X-User" => "andy" }
    assert_response :created
    body = response.parsed_body
    assert_equal ApiStubs::FILE_ID, body.dig("upload", "id")
    assert_equal "PUT", body.dig("upload", "method")
    assert_equal "pending", body.dig("file", "status")
    assert_requested :post, "#{ApiStubs::BASE}/api/v1/uploads", body: PARAMS.to_json
  end

  test "a one-argument authorizer works too" do
    Assetboar.config.authorize_direct_upload = ->(controller) { controller.current_user.present? }
    stub_upload_flow
    post "/assetboar/uploads/#{ApiStubs::FILE_ID}/complete", headers: { "X-User" => "andy" }
    assert_response :success
    assert_equal "ready", response.parsed_body.dig("file", "status")
  end

  test "api errors pass through with their status and code" do
    Assetboar.config.authorize_direct_upload = ->(*) { true }
    stub_request(:post, "#{ApiStubs::BASE}/api/v1/uploads").to_return(json(error_json("policy_violation", "too big"), 422))
    post "/assetboar/uploads", params: PARAMS, as: :json
    assert_response :unprocessable_entity
    assert_equal({ "code" => "policy_violation", "message" => "too big" }, response.parsed_body["error"])

    stub_request(:post, "#{ApiStubs::BASE}/api/v1/uploads/#{ApiStubs::FILE_ID}/complete").to_timeout
    post "/assetboar/uploads/#{ApiStubs::FILE_ID}/complete"
    assert_response :unprocessable_entity
    assert_equal "error", response.parsed_body.dig("error", "code")
  end

  test "missing params are a 400" do
    Assetboar.config.authorize_direct_upload = ->(*) { true }
    post "/assetboar/uploads", params: { policy: "avatars" }, as: :json
    assert_response :bad_request
  end

  test "the stimulus controller ships as an asset" do
    path = Assetboar::Engine.root.join("app/assets/javascripts/assetboar/direct_upload_controller.js")
    assert path.exist?
    assert_match(/export default class extends Controller/, path.read)
    assert_match(/export async function directUpload/, path.read)
  end
end
