module Blackboard
  class Session
    include Mongoid::Document
    include Mongoid::Timestamps

    field :session_id, type: String
    field :type, type: String # chat | council | workflow
    field :actors, type: Array, default: []
    field :state, type: String, default: 'active' # active | paused | completed
    field :metadata, type: Hash, default: {}

    index({ session_id: 1 }, { unique: true })
    
    validates :session_id, presence: true, uniqueness: true
    validates :type, inclusion: { in: %w[chat council workflow] }
    validates :state, inclusion: { in: %w[active paused completed] }
  end
end
