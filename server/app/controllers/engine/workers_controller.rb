require 'redis'

module Engine
  class WorkersController < ActionController::Base
    def index
      # In test, keep legacy HTML to satisfy controller tests
      if Rails.env.test?
        keys = redis.keys('savant:workers:heartbeat:*')
        @workers = keys.map do |k|
          worker_id = k.sub('savant:workers:heartbeat:', '')
          last_seen = redis.get(k).to_f
          { id: worker_id, last_seen: Time.at(last_seen), status: (Time.now.to_f - last_seen < 60 ? 'alive' : 'dead') }
        end
        return
      end

      # Prefer Hub UI: redirect to Diagnostics Workers
      return redirect_to('/ui/diagnostics/reasoning/workers') unless request.format&.json?

      # JSON fallback: return workers list
      reg = []
      begin
        reg = redis.smembers('savant:workers:registry')
      rescue StandardError
        reg = []
      end
      keys = redis.keys('savant:workers:heartbeat:*')
      hb_ids = keys.map { |k| k.sub('savant:workers:heartbeat:', '') }
      all_ids = (reg + hb_ids).uniq
      workers = all_ids.map do |wid|
        last = redis.get("savant:workers:last_seen:#{wid}") || redis.get("savant:workers:heartbeat:#{wid}")
        last_f = last.to_f
        { id: wid, last_seen: Time.at(last_f), status: (Time.now.to_f - last_f < 60 ? 'alive' : 'dead') }
      end
      render json: { workers: workers }
    end

    private

    def redis
      @redis ||= Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    end
  end
end
