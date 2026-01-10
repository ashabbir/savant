require "test_helper"

class BlackboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @session_id = "test-session-#{SecureRandom.hex(4)}"
  end

  test "should create session" do
    assert_difference -> { Blackboard::Session.count }, 1 do
      post "/blackboard/sessions", params: { session: { session_id: @session_id, type: "chat" } }, as: :json
    end
    assert_response :success
  end

  test "should append event" do
    assert_difference -> { Blackboard::Event.count }, 1 do
      post "/blackboard/events", params: { 
        event: { 
          session_id: @session_id, 
          type: "test_event", 
          actor_id: "actor-1", 
          actor_type: "human" 
        } 
      }, as: :json
    end
    assert_response :success
  end

  test "should replay events" do
    # Create an event first
    Blackboard::Event.create!(
      event_id: SecureRandom.uuid,
      session_id: @session_id,
      type: "replayed_event",
      actor_id: "actor-1",
      actor_type: "human"
    )

    get "/blackboard/events?session_id=#{@session_id}"
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json.size
    assert_equal "replayed_event", json[0]["type"]
  end

  test "should create and fetch artifact" do
    artifact_id = SecureRandom.uuid
    post "/blackboard/artifacts", params: {
      artifact: {
        artifact_id: artifact_id,
        type: "message",
        produced_by: "actor-1",
        content_ref: "inline"
      }
    }, as: :json
    assert_response :success

    get "/blackboard/artifacts/#{artifact_id}", as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "message", json["type"]
  end
end
