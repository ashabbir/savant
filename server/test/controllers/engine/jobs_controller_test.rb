require "test_helper"

class Engine::JobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    # Clean up test data
    @redis.del('savant:queue:reasoning')
    @redis.del('savant:jobs:running')
    @redis.del('savant:jobs:completed')
    @redis.del('savant:jobs:failed')
  end

  teardown do
    # Clean up after tests
    @redis.del('savant:queue:reasoning')
    @redis.del('savant:jobs:running')
    @redis.del('savant:jobs:completed')
    @redis.del('savant:jobs:failed')
  end

  test "should get index" do
    get engine_jobs_url
    assert_response :success
    assert_select "h1", "Engine Jobs"
  end

  test "should display queue length" do
    # Add some jobs to queue
    @redis.rpush('savant:queue:reasoning', '{"job_id":"test1"}')
    @redis.rpush('savant:queue:reasoning', '{"job_id":"test2"}')
    
    get engine_jobs_url
    assert_response :success
    assert_select "p", /Queue Length: 2/
  end

  test "should display running jobs" do
    @redis.sadd('savant:jobs:running', 'job-123')
    @redis.sadd('savant:jobs:running', 'job-456')
    
    get engine_jobs_url
    assert_response :success
    assert_select "p", /Running: 2/
  end

  test "should display completed jobs" do
    completed_job = {
      job_id: 'completed-1',
      status: 'ok',
      ts: Time.now.to_f
    }
    @redis.lpush('savant:jobs:completed', completed_job.to_json)
    
    get engine_jobs_url
    assert_response :success
    assert_select "h2", "Recent Completed"
    assert_select "td", /completed-1/
  end

  test "should display failed jobs" do
    failed_job = {
      job_id: 'failed-1',
      error: 'Test error',
      ts: Time.now.to_f
    }
    @redis.lpush('savant:jobs:failed', failed_job.to_json)
    
    get engine_jobs_url
    assert_response :success
    assert_select "h2", "Recent Failed"
    assert_select "td", /failed-1/
    assert_select "td", /Test error/
  end

  test "should show job result" do
    job_id = 'show-test-1'
    result = {
      status: 'ok',
      intent_id: 'intent-123',
      tool_name: 'context.fts_search',
      finish: false
    }
    @redis.set("savant:result:#{job_id}", result.to_json)
    
    get engine_job_url(job_id)
    assert_response :success
    assert_select "h1", "Job #{job_id}"
    assert_select "p", /Status: ok/
  end

  test "should handle missing job result" do
    get engine_job_url('nonexistent-job')
    assert_response :success
    assert_select "p", /Job result not found/
  end
end
