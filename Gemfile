source "https://rubygems.org"

gem 'maestro_plugin', '>= 0.0.17'

#gem "fog", ">=1.20.0"
# Temporary, for serviceAccounts
gem "fog-maestrodev", "~> 1.20.0.20140305101839"

# Constraint here to avoid conflicts with other plugins that require
# mime-types 1.x. We consider that a system requirement of Maestro until it
# can be upgraded everywhere.
gem "mime-types", "~> 1.16"

gem "rbvmomi", ">=1.3.0" # for vmware
gem "google-api-client", ">=0.6.4" # for google compute engine
gem "unf" # for AWS unicode

group :development do
  gem 'maestro-plugin-rake-tasks'
  gem 'json'
end

group :test do
  gem 'rspec'
end
