module Config
  def self.[] key
    @config ||= YAML.load_file('config.yml')[env]
    raise "#{env} is not a valid test environment" unless @config

    @config[key]
  end

  private

  def self.env
    ENV['test_env'] || "stage"
  end
end
