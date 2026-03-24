require "bundler/gem_tasks"
require "rubygems"

desc "Push the built gem to RubyGems"
task :push do
	spec = Gem::Specification.load(Dir["*.gemspec"].first)
	gem_file = "pkg/#{spec.name}-#{spec.version}.gem"

	abort "Gem not built: #{gem_file}. Run `rake build` first." unless File.exist?(gem_file)

	print "Push #{spec.name} #{spec.version}? [y/N]: "
	exit unless STDIN.gets.strip.downcase == "y"

	sh "gem push #{gem_file}"
end