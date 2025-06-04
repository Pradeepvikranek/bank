class UsersController < ApplicationController
  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to account_path, notice: 'Account created successfully'
    else
      render :new
    end
  end

  def show
    @user = User.find(params[:id])
    @account = @user.account
    @transactions = @account.transactions.order(created_at: :desc)
  end

  private

  def user_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation)
  end
end
