require 'rubygems'
require 'rspec'
require 'fog'
require_relative 'helpers'
require 'maestro_plugin/logging_stdout'

$LOAD_PATH.unshift(File.dirname(__FILE__) + '/../src') unless $LOAD_PATH.include?(File.dirname(__FILE__) + '/../src')

RSpec.configure do |config|

  # Only run focused specs:
  config.filter_run :focus => true
  config.filter_run_excluding :disabled => true

  # Yep, if there is nothing filtered, run the whole thing.
  config.run_all_when_everything_filtered = true

  config.include Helpers

  config.before(:each) do
    Fog.mock!
    # reduce timeout for tests that force failure
    Fog.timeout = 3
    Maestro::MaestroWorker.mock!
  end
end

def context_outputs(provider, ids=[])
  server_meta = []
  ids.each { |id| server_meta << { 'id' => id, 'provider' => provider } }

  { 'servers' => server_meta }
end
