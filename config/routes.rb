Rails.application.routes.draw do
  resources :users, only: [:new, :create, :show]
  
  resource :account, only: [:show] do
    post 'deposit'
    post 'withdraw'
    post 'send_money'
  end

  root 'users#new'
end
