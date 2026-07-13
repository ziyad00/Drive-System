module V1
  class BackendsController < ApplicationController
    # GET /v1/backends — what this user can store to, and where blobs go
    # when no backend is specified on the request.
    def index
      render json: backends_json
    end

    # PUT /v1/backends/default — set the current user's default backend.
    # A null/empty backend clears the personal default so the system
    # default applies again.
    def set_default
      name = params[:backend].presence&.to_s

      if name && !Storage.available_backends.include?(name)
        return render json: {
          error: "backend #{name.inspect} is not available (available: #{Storage.available_backends.join(', ')})"
        }, status: :unprocessable_entity
      end

      current_user.update!(default_backend: name)
      render json: backends_json
    end

    private

    def backends_json
      {
        available: Storage.available_backends,
        default: current_user.effective_backend,
        user_default: current_user.default_backend,
        system_default: Storage.default_backend
      }
    end
  end
end
