module V1
  # Raw binary downloads with HTTP range support — partial reads for video
  # seeking and sync clients live here, not in the Base64 JSON API.
  class DownloadsController < ApplicationController
    include BlobRequests
    include TreeNavigation

    # GET /v1/dl/*path
    #   Range: bytes=0-1023 | bytes=500- | bytes=-500   -> 206 partial
    #   If-Range: "<etag>" -> full 200 when the ETag no longer matches
    #   ?disposition=attachment -> download instead of inline
    def show
      node = resolve_path(params[:path])
      return render json: { error: "no such path" }, status: :not_found unless node
      return render json: { error: "#{node.path} is a folder" }, status: :bad_request if node.folder?

      data = Storage.backend(node.blob.backend).retrieve(node.blob.storage_id)
      node.blob.backfill_checksum!(data)
      etag_header!(node.blob)
      response.headers["Accept-Ranges"] = "bytes"

      range = requested_range(data.bytesize)
      if range == :unsatisfiable
        response.headers["Content-Range"] = "bytes */#{data.bytesize}"
        return head :range_not_satisfiable
      end

      if range
        first, last = range
        response.headers["Content-Range"] = "bytes #{first}-#{last}/#{data.bytesize}"
        send_body(node, data.byteslice(first..last), :partial_content)
      else
        send_body(node, data, :ok)
      end
    end

    private

    def send_body(node, bytes, status)
      send_data bytes,
                status: status,
                type: node.content_type || "application/octet-stream",
                filename: node.name,
                disposition: params[:disposition] == "attachment" ? "attachment" : "inline"
    end

    # nil -> serve the full body; :unsatisfiable -> 416; [first, last] -> 206.
    # A malformed Range header is ignored per RFC 9110; If-Range with a
    # stale validator also falls back to the full body.
    def requested_range(size)
      header = request.headers["Range"]
      return nil if header.blank?
      return nil if stale_if_range?

      match = header.match(/\Abytes=(\d*)-(\d*)\z/)
      return nil unless match

      first_part, last_part = match[1], match[2]

      if first_part.empty?
        return nil if last_part.empty?

        suffix_length = last_part.to_i
        return :unsatisfiable if suffix_length.zero? || size.zero?

        [ [ size - suffix_length, 0 ].max, size - 1 ]
      else
        first = first_part.to_i
        return :unsatisfiable if first >= size

        last = last_part.empty? ? size - 1 : [ last_part.to_i, size - 1 ].min
        return nil if last < first

        [ first, last ]
      end
    end

    def stale_if_range?
      header = request.headers["If-Range"]
      header.present? && header.strip != response.headers["ETag"]
    end
  end
end
