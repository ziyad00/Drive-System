# Soft deletion. Trashing reparents a subtree's root under the user's trash
# sentinel (one atomic move, like any move), remembering where it came from;
# restore moves it back — to the tree root if the original folder is gone —
# renaming on conflict. Permanent purging destroys nodes, versions and bytes.
module Trash
  def self.retention_days
    Integer(ENV.fetch("TRASH_RETENTION_DAYS", 30))
  end

  def self.trash!(node)
    user = node.api_user
    node.update!(
      trashed_at: Time.current,
      trashed_from: node.path,
      original_name: node.name,
      original_parent_id: node.parent_id,
      parent: user.trash_node,
      name: "trashed-#{node.id}"
    )
    node
  end

  def self.restore!(node)
    user = node.api_user
    parent = restorable_parent(user, node.original_parent_id)

    node.update!(
      parent: parent,
      name: available_name(parent, node.original_name),
      trashed_at: nil,
      trashed_from: nil,
      original_name: nil,
      original_parent_id: nil
    )
    node
  end

  def self.purge_expired!
    cutoff = retention_days.days.ago
    count = 0
    Node.where(role: nil).where(trashed_at: ..cutoff).find_each do |node|
      node.destroy!
      count += 1
    end
    count
  end

  # The original folder, unless it no longer exists or is itself in the
  # trash — then the tree root.
  def self.restorable_parent(user, original_parent_id)
    parent = user.nodes.find_by(id: original_parent_id)
    return user.root_node unless parent&.folder?
    return user.root_node if in_trash?(user, parent)

    parent
  end

  def self.in_trash?(user, node)
    while node
      return true if node.role == "trash"
      return false if node.role == "root"

      node = node.parent
    end
    false
  end

  def self.available_name(parent, name)
    return name unless parent.children.exists?(name: name)

    extension = File.extname(name)
    base = File.basename(name, extension)
    counter = 1
    loop do
      suffix = counter == 1 ? " (restored)" : " (restored #{counter})"
      candidate = "#{base}#{suffix}#{extension}"
      return candidate unless parent.children.exists?(name: candidate)

      counter += 1
    end
  end
end
