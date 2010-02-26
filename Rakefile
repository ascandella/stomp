#   Copyright 2005-2006 Brian McCallister
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

require 'rubygems'
require 'rake'
require 'rake/testtask'
require 'spec/rake/spectask'
require "lib/stomp/version"

begin
  require "hanna/rdoctask"
rescue LoadError => e
  require "rake/rdoctask"
end

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "stomp"
    gem.version = Stomp::Version::STRING
    gem.summary = %Q{Ruby client for the Stomp messaging protocol}
    gem.description = %Q{Ruby client for the Stomp messaging protocol}
    gem.email = ["brianm@apache.org", 'marius@stones.com', 'morellon@gmail.com']
    gem.homepage = "http://stomp.codehaus.org/"
    gem.authors = ["Brian McCallister", 'Marius Mathiesen', 'Thiago Morello']
    gem.add_development_dependency "rspec"
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler not available. Install it with: gem install jeweler"
end

desc 'Run the specs'
Spec::Rake::SpecTask.new(:spec) do |t|
  t.spec_opts = ['--colour --format specdoc --loadby mtime --reverse']
  t.spec_files = FileList['spec/**/*_spec.rb']
end

desc "Rspec : run all with RCov"
Spec::Rake::SpecTask.new('spec:rcov') do |t|
  t.spec_files = FileList['spec/**/*.rb']
  t.rcov = true
  t.rcov_opts = ['--exclude', 'gems', '--exclude', 'spec']
end

Rake::RDocTask.new do |rdoc|
  rdoc.main = "README.rdoc"
  rdoc.rdoc_dir = "doc"
  rdoc.title = "Stomp"
  rdoc.options += %w[ --line-numbers --inline-source --charset utf-8 ]
  rdoc.rdoc_files.include("README.rdoc", "CHANGELOG.rdoc")
  rdoc.rdoc_files.include("lib/**/*.rb")
end

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/test*.rb']
  t.verbose = true
end

task :default => :spec



