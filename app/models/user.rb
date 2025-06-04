class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
#   has_secure_password

  has_one :account, dependent: :destroy
  validates :email, presence: true, uniqueness: true

  after_create :create_account_with_zero_balance

  private

  def create_account_with_zero_balance
    create_account(balance: 0.0)
  end
end
