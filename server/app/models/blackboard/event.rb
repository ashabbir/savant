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
      # Fan-out event_id to Redis
      redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')
      redis = Redis.new(url: redis_url)
      
      # Channel naming: blackboard:session:<session_id>:events
      # And a global channel: blackboard:events
      redis.publish("blackboard:events", { event_id: event_id, session_id: session_id, type: type }.to_json)
      redis.publish("blackboard:session:#{session_id}:events", { event_id: event_id, type: type }.to_json)
    ensure
      redis&.close
    end
  end
end
