module GmailHelpers
  def self.clear_inbox(user, password)
    # All Mail when deleted is moved to the Trash folder, and periodically must be manually removed

    gmail = Gmail.connect(user, password)
    gmail.mailbox('[Gmail]/All Mail').emails.each { |email|
      email.delete! } if gmail.mailbox('[Gmail]/All Mail').count(:all) > 0
    gmail.connection.expunge
    gmail.logout
  end

  def get_emails_from_gmail(user, password, from_email)
    xx_emails = []
    gmail = Gmail.connect(user, password)
    if from_email
      gmail.inbox.emails(:unread, :from => from_email).each do |emails|
        xx_emails << sanitized_body(emails)
      end
    else
      gmail.inbox.emails(:unread).each do |emails|
        xx_emails << sanitized_body(emails)
      end
    end
    gmail.logout

    xx_emails
  end

  def get_email_link_from_gmail(user, password, tmail_regex)
    # tmail_regex specified within tmail_helpers
    gmail = Gmail.connect(user, password)
    email = gmail.inbox.emails(:unread).first

    # wait up to an additional 20 additional seconds as needed for email to appear in Gmail
    if email.nil?
      count = 0

      while count < 10 do
        sleep(2)
        email = gmail.inbox.emails(:unread).first
        break if email
        count += 1
      end

      # The Email being sent is a function of Tmail, not Panda, if it doesn't show up,
      # the log will note this issue via this skip message, but the failure is not on Panda
      # If this is consistent, contact Jennifer Perry for the problematic tmail
      if email.nil?
        opt = tmail_regex.to_s.gsub(/.*campaign\=/, '').gsub(/\)/, '')

        skip("The Gmail inbox for #{user} is empty while checking for #{opt} email, please contact Tmail Team if issue persists.")
      end
    end

    tmail_link = sanitized_body(email).match(tmail_regex)[0] if email
    gmail.logout

    tmail_link
  end

  def get_password_token_from_email_link(email_link)
    url = URI.parse(email_link)
    request = Net::HTTP::Get.new(url.request_uri)
    response = Net::HTTP.start(url.host, url.port) { |http|
      http.request(request)
    }

    # Grabbing the password_token from the body
    token_param = response.body.match(/token=.*&/)[0]

    # For some reason, CGI.parse puts each param into an array when it isn't an array
    CGI.parse(token_param)['token'].first
  end

  private

  # current gmail templates are cray-cray!
  def sanitized_body(email)
    email.body.to_s.gsub("=\n", "").gsub("=3D", "=").gsub("&amp;", "&")
  end
end
