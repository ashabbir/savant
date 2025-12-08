class Repo < ApplicationRecord
  self.table_name = 'repos'
  has_many :files, class_name: 'RepoFile'
end

