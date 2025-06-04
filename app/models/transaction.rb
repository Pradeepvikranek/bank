class Transaction < ApplicationRecord
  belongs_to :account

  TRANSACTION_TYPES = %w[deposit withdraw transfer]

  validates :transaction_type, inclusion: { in: TRANSACTION_TYPES }
  validates :amount, numericality: { greater_than: 0 }

  after_create :update_account_balance

  private

  def update_account_balance
    case transaction_type
    when 'deposit'
      account.increment!(:balance, amount)
    when 'withdraw'
      if account.balance >= amount
        account.decrement!(:balance, amount)
      else
        errors.add(:amount, 'Insufficient funds')
        raise ActiveRecord::Rollback
      end
    when 'transfer'
      # handled separately in controller or service
    end
  end
end
