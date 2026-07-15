Rails.application.routes.draw do
  namespace :v1 do
    # Blob ids are arbitrary strings and may contain slashes or dots, so the
    # id segment greedily matches everything after /v1/blobs/.
    resources :blobs, only: %i[index create show], param: :id,
                      constraints: { id: /.+/ }, format: false
    resources :backends, only: :index
    put "backends/default" => "backends#set_default"

    # File tree: path-based reads, id-based mutations.
    get "fs(/*path)" => "fs#show", format: false, defaults: { path: "" }
    get "dl/*path" => "downloads#show", format: false
    resources :folders, only: :create
    resources :files, only: :create
    put "files" => "files#update"
    resources :nodes, only: %i[update destroy] do
      member { post :copy }
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
