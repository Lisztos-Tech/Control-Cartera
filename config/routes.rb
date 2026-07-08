Rails.application.routes.draw do
  mount RailsIcons::Engine, at: "/rails_icons"
  # Una sola cuenta, sin registro público. Sin reset por email (no hay SMTP);
  # la contraseña se cambia por consola: User.first.update!(password: "...")
  resource :session, only: [ :new, :create, :destroy ]
  root "dashboard#index"
  get "vencimientos", to: "vencimientos#index"

  get "up" => "rails/health#show", as: :rails_health_check

  resources :clientes, except: [ :destroy ]

  resources :polizas, except: [ :destroy ] do
    collection do
      get :canceladas
      get :revision
    end
    member do
      patch :reactivar
    end
    resources :recibos, only: [ :new, :create ], shallow: false
  end

  resources :recibos, only: [ :edit, :update, :destroy ] do
    member do
      patch :marcar_pagado
      post :crear_siguiente
    end
  end

  resources :comisiones, only: [ :index, :edit, :update ] do
    member do
      patch :marcar_pagada
    end
  end
end
