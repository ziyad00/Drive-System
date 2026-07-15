# An E2EE group: the server stores the public ratchet tree and the
# append-only log of commits (whose path secrets are encrypted to members).
# The server never holds a private key or the group secret — clients do.
class EncryptionGroup < ApplicationRecord
  belongs_to :owner, class_name: "ApiUser"
  has_many :group_members, dependent: :destroy
  has_many :group_commits, dependent: :destroy

  validates :name, presence: true

  # Rebuild the public TreeKem::Group from stored state + member placement,
  # so leaf ids and node ids line up with what clients see.
  def session
    group = TreeKem::Group.create(capacity: capacity)
    group.instance_variable_set(:@epoch, epoch)
    group_members.each do |member|
      leaf = group.tree.leaves.find { |l| l.id == member.leaf_id }
      leaf.member_id = member.api_user_id
    end
    group.tree.load_public_state(JSON.parse(public_state)) if public_state.present?
    group
  end

  def member?(user)
    group_members.exists?(api_user_id: user.id)
  end
end
