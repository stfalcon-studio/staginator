class TerminalSecurity

  def initialize(terminal_secret)
    require 'digest/sha2'
    require 'date'
    @terminal_secret = terminal_secret
  end

  def security_token(p_name)
    Digest::SHA2.hexdigest "#{day_prefix}#{@terminal_secret}#{p_name}"
  end

  private

  def day_prefix
    time = DateTime.now
    "#{time.day}#{time.month}#{time.year}"
  end

end