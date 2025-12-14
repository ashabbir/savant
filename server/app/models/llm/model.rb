module Llm
  class Model < ApplicationRecord
    self.table_name = 'llm_models'
    belongs_to :provider, class_name: 'Llm::Provider', foreign_key: :provider_id
    has_one :agent, foreign_key: :model_id
  end
end
