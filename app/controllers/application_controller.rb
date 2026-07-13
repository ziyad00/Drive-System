class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :authenticate!

  attr_reader :current_user

  private

  def authenticate!
    authenticate_or_request_with_http_token do |token, _options|
      @current_user = ApiUser.authenticate(token)
      @current_user.present?
    end
  end

  # Render 401 as JSON instead of the default plain-text body.
  def request_http_token_authentication(realm = "Application", message = nil)
    headers["WWW-Authenticate"] = %(Bearer realm="#{realm.tr('"', "")}")
    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
