module Llm
  class Provider < ApplicationRecord
    self.table_name = 'llm_providers'
    has_many :models, class_name: 'Llm::Model', foreign_key: :provider_id
  end
end
