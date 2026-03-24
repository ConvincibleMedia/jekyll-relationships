require "bundler/gem_tasks"

spec = Gem::Specification.load(Dir["*.gemspec"].first)

task :confirm_release do
  print "Release #{spec.name} #{spec.version} to RubyGems? [y/N]: "
  answer = STDIN.gets.strip.downcase
  abort("Release cancelled.") unless answer == "y"
end

Rake::Task["release"].enhance(["confirm_release"])