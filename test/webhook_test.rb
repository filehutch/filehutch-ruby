# frozen_string_literal: true

require_relative "test_helper"

class WebhookTest < Minitest::Test
  SECRET = "whsec_test"
  BODY = '{"id":"whd_1","type":"file.created","data":{"file":{"id":"file_1"}}}'
  NOW = Time.at(1_800_000_000)

  def header(body: BODY, secret: SECRET, at: NOW)
    "t=#{at.to_i},v1=#{FileHutch::Webhook.compute_signature(at, body, secret)}"
  end

  def test_construct_event_verifies_and_parses
    event = FileHutch::Webhook.construct_event(BODY, header, SECRET, now: NOW + 60)
    assert_equal "file.created", event["type"]
    assert_equal "file_1", event.dig("data", "file", "id")
  end

  def test_tampering_wrong_secret_and_replay_are_refused
    assert_raises(FileHutch::SignatureVerificationError) { FileHutch::Webhook.construct_event(BODY + " ", header, SECRET, now: NOW) }
    assert_raises(FileHutch::SignatureVerificationError) { FileHutch::Webhook.construct_event(BODY, header(secret: "whsec_other"), SECRET, now: NOW) }
    assert_raises(FileHutch::SignatureVerificationError) { FileHutch::Webhook.construct_event(BODY, header, SECRET, now: NOW + 301) }
    assert FileHutch::Webhook.verify!(BODY, header, SECRET, tolerance: 600, now: NOW + 301)
  end

  def test_malformed_input_fails_closed
    [ nil, "", "garbage", "t=abc,v1=", "v1=deadbeef" ].each do |bad|
      error = assert_raises(FileHutch::SignatureVerificationError) { FileHutch::Webhook.verify!(BODY, bad, SECRET, now: NOW) }
      assert_match(/missing or malformed/, error.message)
    end
    assert_raises(FileHutch::SignatureVerificationError) { FileHutch::Webhook.verify!(BODY, header, "", now: NOW) }
  end

  def test_the_error_is_an_file_hutch_error
    assert_operator FileHutch::SignatureVerificationError, :<, FileHutch::Error
  end
end
