require "test_helper"

class Engine::WorkersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    # Clean up test data
    @redis.keys('savant:workers:heartbeat:*').each { |k| @redis.del(k) }
  end

  teardown do
    # Clean up after tests
    @redis.keys('savant:workers:heartbeat:*').each { |k| @redis.del(k) }
  end

  test "should get index" do
    get engine_workers_url
    assert_response :success
    assert_select "h1", "Engine Workers"
  end

  test "should display active workers" do
    # Add heartbeats for two workers
    @redis.setex('savant:workers:heartbeat:worker1:1234', 30, Time.now.to_f.to_s)
    @redis.setex('savant:workers:heartbeat:worker2:5678', 30, Time.now.to_f.to_s)
    
    get engine_workers_url
    assert_response :success
    assert_select "tr", minimum: 3 # header + 2 workers
    assert_select "td", /worker1:1234/
    assert_select "td", /worker2:5678/
  end

  test "should show worker status as alive" do
    # Add recent heartbeat
    @redis.setex('savant:workers:heartbeat:alive-worker:9999', 30, Time.now.to_f.to_s)
    
    get engine_workers_url
    assert_response :success
    assert_select "td", /alive/
  end

  test "should show worker status as dead for old heartbeat" do
    # Add old heartbeat (2 minutes ago)
    old_time = (Time.now - 120).to_f
    @redis.setex('savant:workers:heartbeat:dead-worker:1111', 30, old_time.to_s)
    
    get engine_workers_url
    assert_response :success
    assert_select "td", /dead/
  end

  test "should handle no workers" do
    get engine_workers_url
    assert_response :success
    # Should only have header row
    assert_select "tr", count: 1
  end
end
