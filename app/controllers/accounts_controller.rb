require 'uri'
# Ruby 3.1:
# Set is not part of Ruby core class by default — add require 'set'
# require 'set'
# ************** END **************

# Ruby 3.2:
# Set is part of the ruby core class (no longer needs require 'set')
# require 'set'

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
  # ruby 3.1:
  # module_eval - defining methods/constants inside module, no need to pass parameters
  # TransactionLogger.module_eval do
  #   def log_transaction_summary(type, amount, ref)
  #     log_dir  = Rails.root.join('log')
  #     log_file = log_dir.join("#{Rails.env}.log")

  #     # ruby 3.1:
  #     # File.exists? still works
  #     # Dir.exists? still works
  #     # if Dir.exists?(log_dir) && File.exists?(log_file)
  #     #   Rails.logger.info("[#{type.upcase}] Amount: #{amount}, Ref: #{ref}, Time: #{Time.now}")
  #     # end

  #     # ruby 3.2:
  #     # use File.exist? instead
  #     # use Dir.exist? instead
  #     # Check “log” folder exists and specific log file exists
  #     if Dir.exist?(log_dir) && File.exist?(log_file)
  #       Rails.logger.info("[#{type.upcase}] Amount: #{amount}, Ref: #{ref}, Time: #{Time.now}")
  #     end
  #   end
  # end
  # ************** END **************

  log_dir  = Rails.root.join('log')
  log_file = log_dir.join("#{Rails.env}.log")

  # ruby 3.2:
  # use module_exec to pass parameters or configuration into a block for dynamic behavior
  TransactionLogger.module_exec(log_dir, log_file) do |dir, file|
    define_method :log_transaction_summary do |type, amount, ref|
      if Dir.exist?(dir) && File.exist?(file)
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
    amount = validate_input(params[:amount]).to_d
    log_integer_type(amount.to_i)
    ref = generate_transaction_ref

    deposit_timestamp = Time.now

    Rails.logger.info("Before assignment - DepositTimestamp.timestamp: #{DepositTimestamp.timestamp.inspect}")

    deposit_ref_string = "Ref based on timestamp: #{DepositTimestamp.timestamp.inspect}"

    Rails.logger.info("Generated deposit_ref_string BEFORE assignment: #{deposit_ref_string.inspect}")

    # ruby 3.1: Constant assignment evaluation order - Multiple assignment that behaves differently in Ruby 3.1 vs 3.2
    # Ruby evaluates right-hand side first, then the left-hand side
    # DepositTimestamp.timestamp, DepositReference.reference = deposit_timestamp, deposit_ref_string
    # ************** END **************

    # ruby 3.2:
    # Ruby evaluates left-hand side before right-hand side, like method assignments
    DepositTimestamp.timestamp = deposit_timestamp
    DepositReference.reference = deposit_ref_string

    Rails.logger.info("After assignment - DepositTimestamp.timestamp: #{DepositTimestamp.timestamp.inspect}")
    Rails.logger.info("After assignment - DepositReference.reference: #{DepositReference.reference.inspect}")

    # ruby 3.1: Hash#shift behavior
    # returns default value or calling the default proc
    # deposit_memo = validate_input(Hash.new(params[:memo]).shift)
    # ************** END **************

    # ruby 3.2:
    # returns nil if the hash is empty
    deposit_memo = validate_input(Hash.new(params[:memo]).shift)

    # fall back to the original params[:memo] If shift returned nil
    memo = params[:memo] if deposit_memo.nil?
    Rails.logger.info("Deposit metadata extracted via shift: #{memo.inspect}")

    # ruby 3.1:
    # Struct Keyword Initialization - Initialize Struct using keyword arguments, need to explicitly specify keyword_init: true
    # struct which allows mutable fields can lead to bugs if you accidentally change state
    # bankUser = Struct.new(:name, :email, keyword_init: true)
    # ************** END **************

    # ruby 3.2:
    # Introduction of immutable Data class, there's no need to use struct for immutable data types
    # supports keyword arguments without the need for keyword_init: true
    bankUser = Data.define(:name, :email)
    person = bankUser.new(name: @account.user.name, email: @account.user.email)
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
    amount = validate_input(params[:amount]).to_d
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
    recipient_email = params[:recipient_email]
    memo = params[:memo].to_s

    # ruby 3.1:
    # Grab raw email string and escape it
    # safe_recipient = URI.parser.escape(recipient_email)
    # Rails.logger.info("Escaped recipient: #{safe_recipient}")
    # ************** END **************

    # ruby 3.2:
    # URI.parser.escape removed
    # use URI::DEFAULT_PARSER.escape
    safe_recipient = URI::DEFAULT_PARSER.escape(raw_email)
    # ruby 3.1:
    # no built-in timeout handling; unsafe regex can hang or crash the process
    # regex = /(a+)+$/
    # Rails.logger.info("Testing catastrophic backtracking on memo...")
    # start_time = Time.now
    # match = regex.match(memo)
    # elapsed = Time.now - start_time
    # Rails.logger.info("Completed regex match")
    # Rails.logger.info("Time taken: #{elapsed} seconds")
    # ************** END **************

    # ruby 3.2:
    # use Regexp.timeout to improve Performance for complex regex and protect against catastrophic backtracking
    regex = Regexp.new(regex_pattern, timeout: 1.0)

    begin
      puts "Running regex match..."
      start_time = Time.now
      regex.match(input)
      puts "Completed without interruption"
      puts "Time taken: #{Time.now - start_time} seconds"
    rescue Regexp::TimeoutError => e
      puts "Regexp timeout occurred: #{e.message}"
      match = nil
    ensure
      Regexp.timeout = nil
    end

    # ruby 3.1:
    # MatchData - Need to perform manual calculations of byte positions with begin() and end()
    # String Enhancements - Need to manually handle byte offsets and slicing
    # Regexp Timeout - No built-in timeout handling; unsafe regex can hang or crash the process
    # if match
    #   start_char_index = match.begin(0)
    #   end_char_index   = match.end(0)

    #   start_byte_offset = memo.byteslice(0, start_char_index).bytesize
    #   end_byte_offset   = memo.byteslice(0, end_char_index).bytesize

    #   Rails.logger.info("Simulated MatchData#byteoffset (Ruby 3.1)")
    #   Rails.logger.info("Byte offsets for match: start=#{start_byte_offset}, end=#{end_byte_offset}")

    #   substring = memo[start_char_index...end_char_index]
    #   substring_char_index = memo.index(substring)
    #   substring_byte_index = memo.byteslice(0, substring_char_index).bytesize

    #   Rails.logger.info("Simulated String#byteindex: byte index of '#{substring}' = #{substring_byte_index}")
    # else
    #   Rails.logger.info("No match found in memo")
    # end
    # ************** END **************

    # ruby 3.2:
    # use MatchData#byteoffset (Ruby 3.2+) to get byte positions directly
    # Use String#byteindex to find the byte offset of that substring without manual byteslice/bytesize
    # use String#bytesplice to replace those bytes if needed
    if match
      start_byte_offset, end_byte_offset = match.byteoffset(0)
      Rails.logger.info("MatchData#byteoffset (Ruby 3.2+): start=#{start_byte_offset}, end=#{end_byte_offset}")

      start_char_index = match.begin(0)
      end_char_index   = match.end(0)

      substring = memo[start_char_index...end_char_index]

      substring_byte_index = memo.byteindex(substring)
      Rails.logger.info("String#byteindex: byte index of '#{substring}' = #{substring_byte_index}")

      replacement = "Deposited/withdrawn/Money transfered"
      memo.bytesplice(substring_byte_index, substring.bytesize, replacement)
      Rails.logger.info("After bytesplice: #{memo.inspect}")
    else
      Rails.logger.info("No match found in memo")
    end

    amount = validate_input(params[:amount]).to_d
    log_integer_type(amount.to_i)
    if @account.balance < amount
      redirect_to account_path, flash: { transfer_alert: "Insufficient balance for withdrawal." }
      return
    end

    recipient_user = User.find_by(email: safe_recipient)
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

  # ruby 3.1:
  # proc argument handling for logging transaction input - Ruby automatically splatted array into the proc parameters
  # def process_with_proc(proc, args)
  #   proc.call(args)
  # end
  # ************** END **************

  # ruby 3.2: Proc adds stricter argument rules so Procs no longer automatically splat arrays/keywords
  # need to explicitly splat both positional and keyword arguments
  # use * when forwarding
  def process_with_proc(proc, args)
    proc.call(*args)
  end

  TRANSACTION_PROC = proc do |obj, **k|
    Rails.logger.info("Processing transaction: Type=#{obj[:type]}, Amount=#{obj[:amount]}, Ref=#{obj[:ref]}")
  end

  def set_account
    @account = User.first&.account
    redirect_to root_path, alert: 'No user logged in.' if @account.nil?
  end

  # ruby 3.1:
  # when use object.freeze on immutable types, Ruby will issue a warning (in verbose mode) indicating that freezing is unnecessary
  # def safe_freeze(object)
  #   Rails.logger.warn("Warning: Freezing immutable object (unnecessary): #{object.inspect}")
  #   object.freeze
  # end
  # ************** END **************

  # ruby 3.2:
  # skip calling object.freeze on immutable types to prevent unnecessary freezing and suppress warnings
  def safe_freeze(obj)
    if obj.is_a?(Array) || obj.is_a?(Hash) || obj.is_a?(String)
      obj.freeze
    else
      Rails.logger.warn "Skipping freeze for immutable object: #{obj.inspect}"
    end
  end

  # ruby 3.1:
  # Random::DEFAULT refers to a globally shared instance of the Random class
  # def generate_transaction_ref
  #   rng = Random::DEFAULT
  #   "Reference Number: #{rng.rand(100000..999999)}"
  # end
  # ************** END **************

  # ruby 3.2:
  # Random::DEFAULT removed — use Random.new
  def generate_transaction_ref
    rng = Random.new
    "Reference Number: #{rng.rand(100000..999999)}"
  end

  # ruby 3.1:
  # taint, untaint, tainted?, trust, untrust, untrusted? and Process.spawn (tainting)
  # def validate_input(input)
  #   str_input = input.to_s

  #   # Mark untrusted initially
  #   str_input.untrust if str_input.respond_to?(:untrust)
  #   Rails.logger.info("Amount after untrust: #{str_input.inspect}, untrusted?=#{str_input.untrusted?}")

  #   # Taint input
  #   str_input.taint if str_input.respond_to?(:taint)
  #   Rails.logger.info("Amount after taint: #{str_input.inspect}, tainted?=#{str_input.tainted?}")

  #   # Here you would do your validation/sanitization logic
  #   # (Assuming input is valid for this example)

  #   # Untaint after validation
  #   str_input.untaint if str_input.respond_to?(:untaint)
  #   Rails.logger.info("Amount untainted after validation: #{str_input.inspect}, tainted?=#{str_input.tainted?}")

  #   # Mark trusted after validation
  #   str_input.trust if str_input.respond_to?(:trust)
  #   Rails.logger.info("Amount trusted after validation: #{str_input.inspect}, untrusted?=#{str_input.untrusted?}")
    
  #   pid = Process.spawn("echo", str_input)
  #   Process.wait(pid)

  #   safe_freeze(str_input)
  # end
  # ************** END **************

  # ruby 3.2:
  # use Loofah to sanitize user input and prevent XSS
  def validate_input(input)
    str_input = input.to_s

    Rails.logger.info("Raw input: #{str_input.inspect}")

    sanitized = Loofah.fragment(str_input).scrub!(:prune).to_s
    Rails.logger.info("After Loofah sanitization: #{sanitized.inspect}")

    pid = Process.spawn("echo", sanitized)
    Process.wait(pid)

    safe_freeze(sanitized)
  end

  # ruby 3.1:
  # Fixnum, Bignum - used two separate classes to handle integers
  # def log_integer_type(value)
  #   if value.is_a?(Fixnum)
  #     Rails.logger.info("Amount #{value} is a Fixnum")
  #   elsif value.is_a?(Bignum)
  #     Rails.logger.info("Amount #{value} is a Bignum")
  #   else
  #     Rails.logger.info("Amount #{value} is an Integer (Ruby unification)")
  #   end
  # end
  # ************** END **************

  # ruby 3.2:
  # Fixnum and Bignum no longer exist; use Integer
  def log_integer_type(value)
    if value.is_a?(Integer)
      Rails.logger.info("Amount #{value} is an Integer")
    else
      Rails.logger.info("Amount #{value} is not an Integer")
    end
  end


  def validate_type(params)
    filtered_keys = params.keys.map(&:to_s) - %w[authenticity_token commit controller action]
    filtered_keys.each do |key|
      unless PARAMS.include?(key)
        raise ArgumentError, "Invalid parameter: #{key}"
      end
    end
  end

  # ruby 3.1:
  # Keyword arguments cleanup - use *args without the ruby2_keywords modifier. Ruby preserved keyword arguments passed through *args automatically, even without ruby2_keywords
  # def process_transaction(**kw)
  #   Rails.logger.info("Transaction details received in process_transaction: #{kw}")
  # end

  # *args becomes an array with one element: the keyword arguments hash.
  # **kwargs is not mandatory to receive keywords.
  # with ruby2_keywords correctly forward keyword arguments.
  # ruby2_keywords def safe_forward_transaction(*args)
  #   process_transaction(*args)
  # end

  # ruby2_keywords def forward_transaction(*args)
  #   safe_forward_transaction(*args)
  # end

  # ruby2_keywords def handle_transaction(*args)
  #   forward_transaction(*args)
  # end
  # ************** END **************

  # ruby 3.2:
  # remove ruby2_keywords so no need to forward keyword arguments through a splat
  # Add forwarding method as (*args, **kwargs) so Ruby captures both positional (*args) and keyword (**kwargs) arguments
  def process_transaction(**kw)
    Rails.logger.info("Transaction details received in process_transaction: #{kw}")
  end

  def safe_forward_transaction(*args, **kwargs)
    process_transaction(*args, **kwargs)
  end

  def forward_transaction(*args, **kwargs)
    safe_forward_transaction(*args, **kwargs)
  end

  def handle_transaction(*args, **kwargs)
    forward_transaction(*args, **kwargs)
  end
end
