require "test_helper"

class Blackboard::EventTest < ActiveSupport::TestCase
  test "should be valid with required fields" do
    event = Blackboard::Event.new(
      event_id: "test-event",
      session_id: "test-session",
      type: "message_posted",
      actor_id: "actor-1",
      actor_type: "human"
    )
    assert event.valid?
  end

  test "should require event_id" do
    event = Blackboard::Event.new(session_id: "s", type: "t", actor_id: "a", actor_type: "human")
    assert_not event.valid?
  end

  test "should validate actor_type inclusion" do
    event = Blackboard::Event.new(event_id: "e", session_id: "s", type: "t", actor_id: "a", actor_type: "invalid")
    assert_not event.valid?
  end

  test "should validate visibility inclusion" do
    event = Blackboard::Event.new(event_id: "e", session_id: "s", type: "t", actor_id: "a", actor_type: "human", visibility: "secret")
    assert_not event.valid?
  end
end
