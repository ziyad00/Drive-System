# A grant that lets a user other than the owner reach one of another user's
# nodes. Sharing is pure control-plane authorization — it never touches
# stored bytes. A share on a folder covers the whole subtree beneath it.
class Share < ApplicationRecord
  PERMISSIONS = %w[read write].freeze

  belongs_to :node
  belongs_to :grantee, class_name: "ApiUser"
  belongs_to :created_by, class_name: "ApiUser"

  validates :permission, inclusion: { in: PERMISSIONS }
  validates :grantee_id, uniqueness: { scope: :node_id }
  validate :grantee_is_not_the_owner
  validate :node_is_not_a_sentinel

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def writable?
    permission == "write"
  end

  private

  def grantee_is_not_the_owner
    errors.add(:grantee, "already owns this node") if node && grantee_id == node.api_user_id
  end

  def node_is_not_a_sentinel
    errors.add(:node, "cannot be shared") if node&.sentinel?
  end
end
