require "test_helper"

class Blackboard::SessionTest < ActiveSupport::TestCase
  test "should be valid with required fields" do
    session = Blackboard::Session.new(session_id: "test-session", type: "chat")
    assert session.valid?
  end

  test "should require session_id" do
    session = Blackboard::Session.new(type: "chat")
    assert_not session.valid?
  end

  test "should validate type inclusion" do
    session = Blackboard::Session.new(session_id: "test", type: "invalid")
    assert_not session.valid?
  end

  test "should validate state inclusion" do
    session = Blackboard::Session.new(session_id: "test", type: "chat", state: "invalid")
    assert_not session.valid?
  end
end
