require 'redis'

module Engine
  class WorkersController < ActionController::Base
    def index
      # Scan for heartbeats
      keys = redis.keys('savant:workers:heartbeat:*')
      @workers = keys.map do |k|
        worker_id = k.sub('savant:workers:heartbeat:', '')
        last_seen = redis.get(k).to_f
        { id: worker_id, last_seen: Time.at(last_seen), status: (Time.now.to_f - last_seen < 60 ? 'alive' : 'dead') }
      end
    end

    private

    def redis
      @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    end
  end
end
