require 'redis'
require 'json'

module Engine
  class JobsController < ActionController::Base
    def index
      @queue_len = redis.llen('savant:queue:reasoning')
      @running_ids = redis.smembers('savant:jobs:running')
      
      @completed = redis.lrange('savant:jobs:completed', 0, 99).map do |j| 
        JSON.parse(j) rescue {} 
      end
      
      @failed = redis.lrange('savant:jobs:failed', 0, 99).map do |j| 
        JSON.parse(j) rescue {} 
      end
    end

    def show
      @job_id = params[:id]
      @result_json = redis.get("savant:result:#{@job_id}")
      @result = JSON.parse(@result_json) rescue nil if @result_json
    end

    private

    def redis
      @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    end
  end
end
