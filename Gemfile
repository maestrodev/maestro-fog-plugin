source "https://rubygems.org"

gem 'maestro_plugin', '>= 0.0.5'

#dependencies
gem "fog", ">=1.15.0", "<1.16.0" # 1.16.0 has a dependency that doesn't work on jruby
# https://github.com/fog/fog/commit/20a0f7dd3ebe17c52b70412aed40a52ac1ee2230#commitcomment-4386123
gem "excon", "!=0.25.3" # 0.25.3 is broken in JRuby jars https://github.com/geemus/excon/issues/257

gem "rbvmomi", ">=1.3.0" # for vmware
gem "google-api-client" # for google compute engine

group :development do
  gem 'maestro-plugin-rake-tasks'
  gem 'json'
end

group :test do
  gem 'rspec'
end
