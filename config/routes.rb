Rails.application.routes.draw do
  root "dashboard#index"

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
