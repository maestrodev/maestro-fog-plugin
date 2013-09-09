source "https://rubygems.org"

gem 'maestro_plugin', '>= 0.0.5'

#dependencies
gem "fog", ">=1.15.0"
gem "rbvmomi", ">=1.3.0"
gem "excon", "<0.25.3" # 0.25.3 is broken in JRuby jars https://github.com/geemus/excon/issues/257


group :development do
  gem 'maestro-plugin-rake-tasks'
  gem 'json'
end

group :test do
  gem 'rspec'
end
