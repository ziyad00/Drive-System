Rails.application.routes.draw do
  namespace :v1 do
    # Blob ids are arbitrary strings and may contain slashes or dots, so the
    # id segment greedily matches everything after /v1/blobs/.
    resources :blobs, only: %i[index create show], param: :id,
                      constraints: { id: /.+/ }, format: false
    resources :backends, only: :index
    put "backends/default" => "backends#set_default"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
