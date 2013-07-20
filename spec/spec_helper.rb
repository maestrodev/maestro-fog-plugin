require 'rubygems'
require 'rspec'
require 'fog'
require_relative 'helpers'

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/../src') unless $LOAD_PATH.include?(File.dirname(__FILE__) + '/../src')

RSpec.configure do |config|

  config.include Helpers

  config.before(:each) do
    Fog.mock!
    # reduce timeout for tests that force failure
    Fog.timeout = 3
  end
end

def context_outputs(provider, ids=[])
  server_meta = []
  ids.each { |id| server_meta << { 'id' => id, 'provider' => provider } }

  { 'servers' => server_meta }
end
