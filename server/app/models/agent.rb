class Agent < ApplicationRecord
  self.table_name = 'agents'
  belongs_to :persona, optional: true
  belongs_to :llm_model, class_name: 'Llm::Model', optional: true, foreign_key: :model_id
end

