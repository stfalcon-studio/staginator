class WebhookSecurity < TerminalSecurity

  def security_token(p_name)
    Digest::SHA2.hexdigest "#{@terminal_secret}#{p_name}"
  end

end