class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate!

  private

  def authenticate!
    authenticate_or_request_with_http_token do |token, _options|
      expected = Storage.config[:api_token].to_s
      expected.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
    end
  end

  # Render 401 as JSON instead of the default plain-text body.
  def request_http_token_authentication(realm = "Application", message = nil)
    headers["WWW-Authenticate"] = %(Bearer realm="#{realm.tr('"', "")}")
    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
