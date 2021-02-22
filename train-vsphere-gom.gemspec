lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'train-vsphere-gom'

Gem::Specification.new do |spec|
  spec.name          = 'train-vsphere-gom'
  spec.version       = TrainPlugins::VsphereGom::VERSION
  spec.authors       = ['Thomas Heinen']
  spec.email         = ['theinen@tecracer.de']
  spec.summary       = 'Train transport for vSphere GOM'
  spec.description   = 'Execute commands via VMware Tools (without need for network)'
  spec.homepage      = 'https://github.com/tecracer-chef/train-vsphere-gom'
  spec.license       = 'Apache-2.0'

  spec.files = %w[
    README.md train-vsphere-gom.gemspec Gemfile
  ] + Dir.glob(
    'lib/**/*', File::FNM_DOTMATCH
  ).reject { |f| File.directory?(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '~> 2.6'

  # If you only need certain gems during development or testing, list
  # them in Gemfile, not here.

  # Do not list inspec as a dependency of a train plugin.
  # Do not list train or train-core as a dependency of a train plugin.
  spec.add_dependency "net-ping", ">= 2.0.0", "< 3.0"
  spec.add_dependency "rbvmomi", ">= 1.11", "< 4.0"
end
