require 'rake/clean'
require 'rspec/core/rake_task'
require 'zippy'
require 'pp'
require 'nokogiri'

$:.push File.expand_path("../src", __FILE__)

CLEAN.include("maestro-*-plugin-*.zip","vendor","package","tmp")

task :default => [:clean, :bundle, :spec, :package]

desc "Run specs"
RSpec::Core::RakeTask.new do |t|
  t.pattern = "./spec/**/*_spec.rb" # don't need this, it's default.
  t.rspec_opts = "--fail-fast --format p --color"
  # Put spec opts in a file named .rspec in root
end

desc "Get dependencies with Bundler"
task :bundle do
  sh "bundle package" do |ok, res|
    fail "Failed to run bundle package" unless ok
  end
end

def add_file( zippyfile, dst_dir, f )
  puts "Writing #{f} at #{dst_dir}"
  zippyfile["#{dst_dir}/#{f}"] = File.open(f)
end

def add_dir( zippyfile, dst_dir, d )
  glob = "#{d}/**/*"
  FileList.new( glob ).each { |f|
    if (File.file?(f))
      add_file zippyfile, dst_dir, f
    end
  }
end

desc "Package plugin zip"
task :package do
  f = File.open("pom.xml")
  doc = Nokogiri::XML(f.read)
  f.close
  artifactId = doc.css('artifactId').first.text
  version = doc.css('version').first.text
  
  sh "zip -r #{artifactId}-#{version}.zip src vendor LICENSE README.md manifest.json" do |ok, res|
    fail "Failed to create zip file" unless ok
  end
  # Zippy.create "#{artifactId}-#{version}.zip" do |z|
  #   add_dir z, '.', 'src'
  #   add_dir z, '.', 'vendor'
  #   add_file z, '.', 'manifest.json'
  #   add_file z, '.', 'README.md'
  #   add_file z, '.', 'LICENSE'
  # end
end
