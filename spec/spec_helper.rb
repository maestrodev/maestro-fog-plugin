require 'rubygems'
require 'rspec'
require 'fog'

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/../src') unless $LOAD_PATH.include?(File.dirname(__FILE__) + '/../src')

RSpec.configure do |config|
end

Fog.mock!
# reduce timeout for tests that force failure
Fog.timeout = 3


def context_outputs(provider, ids=[])
  server_meta = []
  ids.each { |id| server_meta << { 'id' => id, 'provider' => provider } }

  { 'servers' => server_meta }
end
