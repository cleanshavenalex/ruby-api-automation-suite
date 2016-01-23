class Common
  # get the host name from the environment variables
  # e.g. "Config["panda"]["host"]=dev-panda.xx.com rake" to run
  # the tests with dev-panda.

  def self.get_host_name(env)
    env =~ /^https?:\/\// ? env : "http://#{env}"
  end

  def self.generate_email
    "astest_#{random_uuid}@xx.com"
  end

  def self.random_uuid
    SecureRandom.uuid
  end
end
