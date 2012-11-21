require 'rubygems'
require 'rspec'
require 'fog'

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/../src') unless $LOAD_PATH.include?(File.dirname(__FILE__) + '/../src')

RSpec.configure do |config|
end

Fog.mock!
# reduce timeout for tests that force failure
Fog.timeout = 2
