class Persona < ApplicationRecord
  self.table_name = 'personas'
  has_many :agents
end

