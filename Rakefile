require 'git'
require 'puppet-lint'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop)

task default: [:spec, :rubocop]

task test: [:default]

def git_changed_in_head(path)
  g = Git.open(path)
  diff = g.diff('HEAD^')
  diffs = diff.name_status.select { |_, status| 'ACM'.include? status }
  diffs.keys.map { |filename| File.join(path, filename) }
end

def puppet_changed_files(changed_files)
  changed_files.select { |x| File.fnmatch('*.pp', x) }
end

desc 'Check errors in commit'
task :check_commit do
  if ARGV.length < 2
    puts 'Need a puppet directory to act upon'
    exit 2
  end
  puppet_dir = ARGV[1]
  # Only enable the wmf_styleguide
  PuppetLint.configuration.checks.each do |check|
    if check == :wmf_styleguide
      PuppetLint.configuration.send('enable_wmf_styleguide')
    else
      PuppetLint.configuration.send("disable_#{check}")
    end
  end
  linter = PuppetLint.new
  puppet_changed_files(git_changed_in_head(puppet_dir)).each do |puppet_file|
    linter.file = puppet_file
    linter.run
  end
  linter.print_problems
end
