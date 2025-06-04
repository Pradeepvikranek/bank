# spec/controllers/accounts_controller_spec.rb

require 'rails_helper'

RSpec.describe AccountsController, type: :controller do
  let(:user)      { create(:user) }
  let(:account)   { create(:account, user: user, balance: 1000.0) }
  let(:other_user){ create(:user) }
  let(:other_account) { create(:account, user: other_user, balance: 500.0) }

  before do
    # Simulate a logged-in user by stubbing `User.first` to return our user
    allow(User).to receive(:first).and_return(user)
    allow(user).to receive(:account).and_return(account)
  end

  describe "GET #show" do
    let!(:tx1) { create(:transaction, account: account, amount: 100.0, transaction_type: 'deposit', created_at: 2.days.ago) }
    let!(:tx2) { create(:transaction, account: account, amount:  50.0, transaction_type: 'withdraw', created_at: 1.day.ago) }

    it "assigns @transactions in descending order of created_at" do
      get :show
      expect(assigns(:transactions)).to eq([tx2, tx1])
      expect(response).to render_template(:show)
    end
  end

  describe "POST #deposit" do
    context "with valid params" do
      it "creates a new deposit transaction and redirects with notice" do
        expect {
          post :deposit, params: { amount: "200.50", memo: "Test memo" }
        }.to change { account.transactions.where(transaction_type: 'deposit').count }.by(1)

        tx = account.transactions.where(transaction_type: 'deposit').order(created_at: :desc).first
        expect(tx.amount).to eq(200.50)
        expect(tx.details).to match(/#{Regexp.escape(tx.details.split(" - ").first)} - Test memo/)

        expect(flash[:deposit_notice]).to match(/Deposited 200.5 successfully/)
        expect(response).to redirect_to(account_path)
      end

      it "logs transaction summary" do
        logger_double = double("Logger")
        expect(Rails.logger).to receive(:info).at_least(:once)
        allow(Rails).to receive(:logger).and_return(logger_double)

        post :deposit, params: { amount: "150.00", memo: "Another memo" }
      end
    end

    context "with invalid parameter key" do
      it "raises ArgumentError for unexpected param" do
        expect {
          post :deposit, params: { amount: "100", foo: "bar" }
        }.to raise_error(ArgumentError, /Invalid parameter: foo/)
      end
    end
  end

  describe "POST #withdraw" do
    context "when balance is sufficient" do
      it "creates a new withdraw transaction and redirects with notice" do
        expect {
          post :withdraw, params: { amount: "300", memo: "Withdrawal memo" }
        }.to change { account.transactions.where(transaction_type: 'withdraw').count }.by(1)

        tx = account.transactions.where(transaction_type: 'withdraw').order(created_at: :desc).first
        expect(tx.amount).to eq(300.0)
        expect(tx.details).to match(/Withdraw - Reference Number: \d{6}/)

        expect(flash[:withdraw_notice]).to match(/Withdrew 300.0 successfully/)
        expect(response).to redirect_to(account_path)
      end
    end

    context "when balance is insufficient" do
      it "does not create transaction and redirects with alert" do
        expect {
          post :withdraw, params: { amount: "2000", memo: "Overdraw attempt" }
        }.not_to change { account.transactions.count }

        expect(flash[:withdraw_alert]).to eq("Insufficient balance for withdrawal.")
        expect(response).to redirect_to(account_path)
      end
    end

    context "with invalid parameter key" do
      it "raises ArgumentError for unexpected param" do
        expect {
          post :withdraw, params: { amount: "50", bar: "baz" }
        }.to raise_error(ArgumentError, /Invalid parameter: bar/)
      end
    end
  end

  describe "POST #send_money" do
    before do
      # Create a second user to receive funds
      allow(User).to receive(:find_by).with(email: other_user.email).and_return(other_user)
      allow(other_user).to receive(:account).and_return(other_account)
    end

    context "when balance is sufficient and recipient exists" do
      it "creates withdraw and deposit transactions and redirects with notice" do
        expect {
          post :send_money, params: {
            amount:         "250.75",
            recipient_email: other_user.email,
            memo:           "Rent payment"
          }
        }.to change { account.transactions.where(transaction_type: 'withdraw').count }.by(1)
         .and change { other_account.transactions.where(transaction_type: 'deposit').count }.by(1)

        withdraw_tx = account.transactions.where(transaction_type: 'withdraw').order(created_at: :desc).first
        expect(withdraw_tx.amount).to eq(250.75)
        expect(withdraw_tx.details).to include("Transfer to #{other_user.email}")
        expect(withdraw_tx.details).to include("Memo: Rent payment")

        deposit_tx = other_account.transactions.where(transaction_type: 'deposit').order(created_at: :desc).first
        expect(deposit_tx.amount).to eq(250.75)
        expect(deposit_tx.details).to include("Transfer from #{user.email}")

        expect(flash[:transfer_notice]).to match(/Sent 250.75 to #{Regexp.escape(other_user.email)} successfully/)
        expect(response).to redirect_to(account_path)
      end

      it "logs catastrophic-backtracking timing even if memo is safe" do
        # Use a short memo that won't trigger catastrophic backtracking
        allow(Rails.logger).to receive(:info)
        post :send_money, params: {
          amount:         "100",
          recipient_email: other_user.email,
          memo:           "Safe memo"
        }
        expect(Rails.logger).to have_received(:info).at_least(:once).with(/Testing catastrophic backtracking/)
      end
    end

    context "when balance is insufficient" do
      it "does not create any transactions and redirects with alert" do
        expect {
          post :send_money, params: {
            amount:         "2000",
            recipient_email: other_user.email,
            memo:           "Too big"
          }
        }.not_to change { account.transactions.count }
         .and not_to change { other_account.transactions.count }

        expect(flash[:transfer_alert]).to eq("Insufficient balance for withdrawal.")
        expect(response).to redirect_to(account_path)
      end
    end

    context "when recipient not found" do
      before do
        allow(User).to receive(:find_by).with(email: "nonexistent@example.com").and_return(nil)
      end

      it "does not create any transactions and redirects with alert" do
        expect {
          post :send_money, params: {
            amount:         "50",
            recipient_email: "nonexistent@example.com",
            memo:           "Test"
          }
        }.not_to change { account.transactions.count }

        expect(flash[:transfer_alert]).to eq("Recipient not found.")
        expect(response).to redirect_to(account_path)
      end
    end

    context "with invalid parameter key" do
      it "raises ArgumentError for unexpected param" do
        expect {
          post :send_money, params: {
            amount:         "50",
            recipient_email: other_user.email,
            memo:           "Test",
            bogus:          "value"
          }
        }.to raise_error(ArgumentError, /Invalid parameter: bogus/)
      end
    end
  end

  describe "private methods" do
    describe "#validate_input" do
      it "returns a frozen string" do
        result = controller.send(:validate_input, "123.45")
        expect(result).to be_a(String)
        expect(result.frozen?).to be(true)
      end
    end

    describe "#log_integer_type" do
      it "logs as Integer for any numeric input (Ruby 3.2 unified)" do
        expect(Rails.logger).to receive(:info).with(/Amount 42 is an Integer/)
        controller.send(:log_integer_type, 42)
      end
    end

    describe "#validate_type" do
      it "raises for invalid keys" do
        expect {
          controller.send(:validate_type, ActionController::Parameters.new(foo: "bar"))
        }.to raise_error(ArgumentError, /Invalid parameter: foo/)
      end

      it "does not raise for permitted keys" do
        expect {
          controller.send(:validate_type, ActionController::Parameters.new(amount: "10", memo: "hi", recipient_email: "a@b.com"))
        }.not_to raise_error
      end
    end
  end
end
