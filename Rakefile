require 'rake/clean'
require 'rspec/core/rake_task'
require 'git'
require 'nokogiri'
require 'json'

$:.push File.expand_path("../src", __FILE__)

CLEAN.include("maestro-*-plugin-*.zip","vendor","package","tmp")

task :default => :all

desc "Run specs"
RSpec::Core::RakeTask.new do |t|
  t.pattern = "./spec/**/*_spec.rb" # don't need this, it's default.
  t.rspec_opts = "--fail-fast --format p --color --tag ~skip"
  # Put spec opts in a file named .rspec in root
end

desc "Get dependencies with Bundler"
task :bundle do
  sh "bundle package" do |ok, res|
    fail "Failed to run bundle package" unless ok
  end
end

desc "Package plugin zip"
task :package do
  f = File.open("pom.xml")
  doc = Nokogiri::XML(f.read)
  f.close
  artifactId = doc.css('artifactId').first.text
  version = doc.css('version').first.text
  
  commit = Git.open(".").log.first.sha[0..5]

  # update manifest
  files = FileList["manifests/*.json"]
  manifest = []
  files.each do |f|
    puts "Parsing #{f}"
    json = JSON.parse(IO.read(f))
    if json.kind_of? Array
      manifest.concat(json)
    else
      manifest << json
    end
  end
  manifest.each { |m| m['version'] = "#{version}-#{commit}" }
  File.open("manifest.json",'w'){ |f| f.write(JSON.pretty_generate(manifest)) }
  
  sh "zip -r #{artifactId}-#{version}.zip src vendor images LICENSE README.md manifest.json" do |ok, res|
    fail "Failed to create zip file" unless ok
  end
end

desc "Run a clean build"
task :all => [:clean, :bundle, :spec, :package]
