class GroupCommit < ApplicationRecord
  belongs_to :encryption_group
  belongs_to :committer, class_name: "ApiUser"
end
