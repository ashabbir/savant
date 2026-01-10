module Blackboard
  class Event
    include Mongoid::Document
    include Mongoid::Timestamps

    field :event_id, type: String
    field :session_id, type: String
    field :type, type: String
    field :actor_id, type: String
    field :actor_type, type: String # human | agent | system | worker
    field :visibility, type: String, default: 'public' # public | agent_only | private
    field :parent_event_id, type: String
    field :payload, type: Hash, default: {}
    field :version, type: Integer, default: 1

    index({ event_id: 1 }, { unique: true })
    index({ session_id: 1, created_at: 1 })

    validates :event_id, presence: true, uniqueness: true
    validates :session_id, presence: true
    validates :type, presence: true
    validates :actor_id, presence: true
    validates :actor_type, inclusion: { in: %w[human agent system worker] }
    validates :visibility, inclusion: { in: %w[public agent_only private] }

    after_create :publish_to_redis

    private

    def publish_to_redis
      # Best-effort fan-out to Redis; do not fail persistence if Redis is unavailable
      begin
        redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
        r = Redis.new(url: redis_url)
        # Channel naming: blackboard:session:<session_id>:events and global: blackboard:events
        payload = { event_id: event_id, session_id: session_id, type: type }
        r.publish('blackboard:events', payload.to_json)
        r.publish("blackboard:session:#{session_id}:events", { event_id: event_id, type: type }.to_json)
      rescue StandardError => e
        begin
          Rails.logger.warn("blackboard.redis_publish_failed error=#{e.class} msg=#{e.message}") if defined?(Rails)
        rescue StandardError
          # ignore logger errors
        end
      ensure
        begin r&.close rescue StandardError end
      end
    end
  end
end
