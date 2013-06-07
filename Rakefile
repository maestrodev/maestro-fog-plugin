require 'rake/clean'
require 'rspec/core/rake_task'
require 'git'
require 'nokogiri'
require 'json'

$:.push File.expand_path("../src", __FILE__)

CLEAN.include("manifest.json", "*-plugin-*.zip", "vendor", "package", "tmp", ".bundle")

task :default => :all

desc "Run specs"
RSpec::Core::RakeTask.new do |t|
  t.pattern = "./spec/**/*_spec.rb" # don't need this, it's default.
  t.rspec_opts = "--tag ~skip"
  # Put spec opts in a file named .rspec in root
end

desc "Get dependencies with Bundler"
task :bundle do
  sh "bundle install --without development test"
  sh "bundle package"
end

desc "Package plugin zip"
task :package do
  f = File.open("pom.xml")
  doc = Nokogiri::XML(f.read)
  f.close
  artifactId = doc.css('artifactId').first.text
  version = doc.css('version').first.text
  
  commit = Git.open(".").log.first.sha[0..5]

  # merge manifests into manifest.json
  manifest = []
  merge_manifests(manifest, "provision")
  merge_manifests(manifest, "deprovision")
  merge_manifests(manifest, "create")
  merge_manifests(manifest, "modify")
  manifest.each { |m| m['version'] = "#{version}-#{commit}" }
  File.open("manifest.json",'w'){ |f| f.write(JSON.pretty_generate(manifest)) }
  
  sh "zip -r #{artifactId}-#{version}.zip src vendor images LICENSE README.md manifest.json"
end

desc "Run a clean build"
task :all => [:clean, :spec, :bundle, :package]

# Parse all partial manifests and merge them
def merge_manifests(manifest, action)
  files = FileList["manifests/*-#{action}.json"]
  parent = JSON.parse(IO.read("manifests/#{action}.json"))
  files.each do |f|
    provider = f.match(/manifests\/(.*)-#{action}.json/)[1]
    puts "Processing file [#{provider}] #{f}"

    # merge connection options into both provision and deprovision for each provider
    connect_parent_f = "manifests/#{provider}-connect.json"
    if File.exist? connect_parent_f
      connect_parent = JSON.parse(IO.read(connect_parent_f))
      # no fields are required for deprovision, set them to nil
      connect_parent["task"]["inputs"].each{|k,v| v["value"]=nil; v["required"]=false} if action == "deprovision"
      merged = merge_manifest(parent, JSON.parse(IO.read(f)))
      merged = merge_manifest(merged, connect_parent)
    else
      merged = merge_manifest(parent, JSON.parse(IO.read(f)))
    end
    manifest << merged
  end
end

def merge_manifest(parent, json)
  json.merge(parent) do |key, jsonval, parentval|
    if parentval.kind_of?(Hash) 
      merged = merge_manifest(parentval, jsonval)
    elsif parentval.kind_of?(Array)
      jsonval.map {|i| i.kind_of?(Hash) ? merge_manifest(parentval.first, i) : jsonval}
    else
      jsonval
    end
  end
end
