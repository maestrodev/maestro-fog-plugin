source :rubygems
source "http://maestro:maestro@lucee.maestrodev.net:8081/"

gem 'bundler', '>=1.0.21'
gem 'rake'
gem 'zippy'

gem 'maestro_agent', '0.1.5'

#dependencies
gem "fog", ">=0.11.0"
gem "rbvmomi", ">=1.3.0"

# these must be outside of :test - don't ask, it's a rake thing
gem 'rspec'
gem 'rspec-core'

group :test do

  gem 'rcov', '0.9.11'
  gem 'mocha', '0.10.0'
end
