module Blackboard
  class Artifact
    include Mongoid::Document
    include Mongoid::Timestamps

    field :artifact_id, type: String
    field :type, type: String # message | opinion | summary | diff | json
    field :content_ref, type: String # file:// | s3:// | inline
    field :produced_by, type: String # actor_id
    field :metadata, type: Hash, default: {}

    index({ artifact_id: 1 }, { unique: true })

    validates :artifact_id, presence: true, uniqueness: true
    validates :type, presence: true
    validates :produced_by, presence: true
  end
end
