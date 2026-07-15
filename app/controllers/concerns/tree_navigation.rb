# Path resolution and serialization for the file-tree endpoints.
module TreeNavigation
  extend ActiveSupport::Concern

  class PathConflict < StandardError; end

  included do
    rescue_from PathConflict do |error|
      render json: { error: error.message }, status: :conflict
    end
  end

  private

  def split_path(path)
    path.to_s.split("/").reject(&:empty?)
  end

  # The node at +path+, or nil.
  def resolve_path(path)
    node = current_user.root_node
    split_path(path).each do |segment|
      node = node.children.find_by(name: segment)
      return nil unless node
    end
    node
  end

  # Walks +segments+ from the root, creating missing folders (mkdir -p).
  # Raises PathConflict when a segment exists but is a file.
  def ensure_folder_path(segments)
    node = current_user.root_node
    segments.each do |segment|
      child = node.children.find_by(name: segment)
      if child
        raise PathConflict, "#{child.path} is a file, not a folder" unless child.folder?

        node = child
      else
        node = current_user.nodes.create!(parent: node, kind: "folder", name: segment)
      end
    end
    node
  end

  def node_json(node)
    json = {
      id: node.id,
      kind: node.kind,
      name: node.name,
      path: node.path,
      parent_id: node.root? ? nil : node.parent_id,
      created_at: node.created_at.utc.iso8601,
      updated_at: node.updated_at.utc.iso8601
    }

    if node.file?
      json[:size] = node.blob.size.to_s
      json[:content_type] = node.content_type
      json[:client_mtime] = node.client_mtime&.utc&.iso8601
      json[:backend] = node.blob.backend
    end

    json
  end
end
