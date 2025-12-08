class RepoFile < ApplicationRecord
  self.table_name = 'files'
  belongs_to :repo
end

