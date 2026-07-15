class GroupMember < ApplicationRecord
  belongs_to :encryption_group
  belongs_to :api_user
end
