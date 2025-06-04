require 'loofah'
require 'set'

module DepositTimestamp
  class << self
    attr_accessor :timestamp
  end
end

module DepositReference
  class << self
    attr_accessor :reference
  end
end

class AccountsController < ApplicationController
  before_action :set_account

  PARAMS = Set.new(%w[amount recipient_email memo])

  TransactionLogger = Module.new
  TransactionLogger.module_exec do
    def log_transaction_summary(type, amount, ref)
      log_path = Rails.root.join('log', "#{Rails.env}.log")

      # Use Dir.exist? instead of deprecated Dir.exists?
      if File.exist?(log_path)
        Rails.logger.info("[#{type.upcase}] Amount: #{amount}, Ref: #{ref}, Time: #{Time.now}")
      end
    end
  end

  include TransactionLogger

  def show
    @transactions = @account.transactions.order(created_at: :desc)
  end

  def deposit
    validate_type(params)
    raw_amount = sanitize_input(params[:amount])
    amount = raw_amount.to_d
    log_integer_type(amount.to_i)
    ref = generate_transaction_ref

    deposit_timestamp = Time.now
    Rails.logger.info("Before assignment - DepositTimestamp.timestamp: #{DepositTimestamp.timestamp.inspect}")

    deposit_ref_string = "Ref based on timestamp: #{DepositTimestamp.timestamp.inspect}"
    Rails.logger.info("Generated deposit_ref_string BEFORE assignment: #{deposit_ref_string.inspect}")

    DepositTimestamp.timestamp, DepositReference.reference = deposit_timestamp, deposit_ref_string

    Rails.logger.info("After assignment - DepositTimestamp.timestamp: #{DepositTimestamp.timestamp.inspect}")
    Rails.logger.info("After assignment - DepositReference.reference: #{DepositReference.reference.inspect}")

    # Hash#shift returns nil if empty, so this safely extracts memo
    deposit_memo = sanitize_input(params[:memo].to_s)
    Rails.logger.info("Deposit metadata: #{deposit_memo.inspect}")

    # Use Data class for immutable value object instead of Struct
    UserInfo = Data.define(:name, :email)
    person = UserInfo.new(@account.user.name, @account.user.email)
    Rails.logger.info("Deposit initiated by: #{person.name}, Email: #{person.email}")

    process_with_proc(TRANSACTION_PROC, [{ type: 'deposit', amount: amount, ref: ref }])

    transaction = @account.transactions.build(
      amount: amount,
      transaction_type: 'deposit',
      details: "#{ref} - #{deposit_memo}"
    )
    if transaction.save
      log_transaction_summary('deposit', amount, ref)
      redirect_to account_path, flash: { deposit_notice: "Deposited #{amount} successfully." }
    else
      redirect_to account_path, alert: transaction.errors.full_messages.to_sentence
    end
  end

  def withdraw
    validate_type(params)
    raw_amount = sanitize_input(params[:amount])
    amount = raw_amount.to_d
    log_integer_type(amount.to_i)
    if @account.balance < amount
      redirect_to account_path, flash: { withdraw_alert: "Insufficient balance for withdrawal." }
      return
    end
    ref = generate_transaction_ref
    transaction = @account.transactions.build(
      amount: amount,
      transaction_type: 'withdraw',
      details: "Withdraw - #{ref}"
    )
    if transaction.save
      log_transaction_summary('withdraw', amount, ref)
      redirect_to account_path, flash: { withdraw_notice: "Withdrew #{amount} successfully." }
    else
      redirect_to account_path, alert: transaction.errors.full_messages.to_sentence
    end
  end

  def send_money
    handle_transaction(type: 'transfer', amount: params[:amount], recipient: params[:recipient_email], memo: params[:memo])
    validate_type(params)
    recipient_email = sanitize_input(params[:recipient_email])
    memo = sanitize_input(params[:memo].to_s)

    # Use Regexp.timeout to guard against ReDoS
    begin
      Regexp.timeout = 1.0
      regex = /(a+)+$/
      Rails.logger.info("Testing catastrophic backtracking on memo...")
      start_time = Time.now
      match = regex.match(memo)
      elapsed = Time.now - start_time
      Rails.logger.info("Completed regex match in #{elapsed} seconds")
    rescue Regexp::TimeoutError => e
      Rails.logger.warn("Regexp match timed out: #{e.message}")
      match = nil
    ensure
      Regexp.timeout = Float::INFINITY
    end

    if match
      start_byte = match.byteoffset(0)
      end_byte   = match.byteoffset(0) + match[0].bytesize
      Rails.logger.info("MatchData#byteoffset: start=#{start_byte}, end=#{end_byte}")

      substring = memo[match.begin(0)...match.end(0)]
      byte_index = memo.byteindex(substring)
      Rails.logger.info("String#byteindex for '#{substring}': #{byte_index}")
    else
      Rails.logger.info("No match found or timed out in memo")
    end

    raw_amount = sanitize_input(params[:amount])
    amount = raw_amount.to_d
    log_integer_type(amount.to_i)
    if @account.balance < amount
      redirect_to account_path, flash: { transfer_alert: "Insufficient balance for withdrawal." }
      return
    end

    recipient_user = User.find_by(email: recipient_email)
    if recipient_user.nil?
      redirect_to account_path, flash: { transfer_alert: 'Recipient not found.' }
      return
    end

    ActiveRecord::Base.transaction do
      ref = generate_transaction_ref

      withdraw_tx = @account.transactions.build(
        amount: amount,
        transaction_type: 'withdraw',
        details: "Transfer to #{recipient_email} - #{ref} - Memo: #{memo}"
      )
      withdraw_tx.save!

      deposit_tx = recipient_user.account.transactions.build(
        amount: amount,
        transaction_type: 'deposit',
        details: "Transfer from #{@account.user.email} - Ref##{ref}"
      )
      deposit_tx.save!

      log_transaction_summary('transfer', amount, ref)
    end

    redirect_to account_path, flash: { transfer_notice: "Sent #{amount} to #{recipient_email} successfully." }
  rescue ActiveRecord::RecordInvalid => e
    redirect_to account_path, alert: e.message
  end

  private

  def process_with_proc(proc, args)
    proc.call(args)
  end

  TRANSACTION_PROC = proc do |obj, **k|
    Rails.logger.info("Processing transaction: Type=#{obj[:type]}, Amount=#{obj[:amount]}, Ref=#{obj[:ref]}")
  end

  def set_account
    @account = User.first&.account
    redirect_to root_path, alert: 'No user logged in.' if @account.nil?
  end

  # Sanitize input using Loofah to replace deprecated taint/untaint
  def sanitize_input(input)
    str_input = input.to_s
    cleaned = Loofah.fragment(str_input).scrub!(:prune).to_s
    # Avoid freezing immutable types (nil, true, false, numbers, symbols)
    unless cleaned.nil? || cleaned.is_a?(Numeric) || cleaned.is_a?(Symbol)
      cleaned.freeze
    end
    cleaned
  end

  def generate_transaction_ref
    rng = Random.new
    "Reference Number: #{rng.rand(100000..999999)}"
  end

  def log_integer_type(value)
    Rails.logger.info("Amount #{value} is an Integer (Ruby 3.2 unification)")
  end

  def validate_type(params)
    filtered_keys = params.keys.map(&:to_s) - %w[authenticity_token commit controller action]
    filtered_keys.each do |key|
      unless PARAMS.include?(key)
        raise ArgumentError, "Invalid parameter: #{key}"
      end
    end
  end

  def process_transaction(**kw)
    Rails.logger.info("Transaction details received in process_transaction: #{kw}")
  end

  def safe_forward_transaction(*args)
    options = args.extract_options!
    process_transaction(**options)
  end

  def forward_transaction(*args)
    safe_forward_transaction(*args)
  end

  def handle_transaction(*args)
    forward_transaction(*args)
  end
end
