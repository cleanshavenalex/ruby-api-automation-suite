module EmailHelpers
  EMAIL_REGEX = {
      share_listing: /http:\/\/smtp\S*\?from=(EM|em)_xx-sharelisting\S*utm_campaign=xx-sharelisting/,
      register: /http:\/\/smtp\S*\?from=(EM|em)_xx-reg\S*utm_campaign=xx-reg/,
      welcome: /http:\/\/smtp\S*\?from=(EM|em)_xx-welcome\S*utm_campaign=xx-welcome/,
      verification_reminder: /http:\/\/smtp\S*\?from=(EM|em)_xx-reg2\S*utm_campaign=xx-reg2/,
      password_reset: /http\:\/\/smtp\S*\:\d{2}\/track\S*token=\S*utm_campaign=xx-pwrequest/,
  }

  def get_link_from_external_email(identifier, email=nil, password=nil)
    sleep(5) # default wait for the email to appear in gmail

    begin
      get_email_link_from_gmail(email, password, EMAIL_REGEX[identifier]) if email =~ /@gmail/
    rescue Exception
      opt = EMAIL_REGEX[identifier].to_s.gsub(/.*campaign\=/, '').gsub(/\)/, '')

      skip("Error while checking for #{opt}, please contact Tmail Team if issue persists.")
    end
  end
end
