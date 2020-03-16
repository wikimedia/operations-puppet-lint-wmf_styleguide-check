# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name        = 'puppet-lint-wmf_styleguide-check'
  spec.version     = '1.0.5'
  spec.homepage    = 'https://github.com/lavagetto/puppet-lint-wmf_styleguide-check'
  spec.license     = 'GPL-3.0'
  spec.author      = 'Giuseppe Lavagetto'
  spec.email       = 'lavagetto@gmail.com'
  spec.files       = Dir[
    'README.md',
    'LICENSE',
    'lib/**/*',
    'spec/**/*',
  ]
  spec.test_files  = Dir['spec/**/*']
  spec.summary     = 'A puppet-lint plugin to check code adheres to the WMF coding guidelines'
  spec.description = <<-EOF
    A puppet-lint plugin to check that the code adheres to the WMF coding guidelines:

    * Check for hiera in non-profiles, and in the body of those
    * Check for roles with declared resources that are not profiles
    * Check for parametrized roles
    * Check for node declarations not using the role keyword
    * Check for system::role calls outside of roles
    * Check for cross-module class inclusion
    * Check for the use of the include keyword in profiles
    * Check for wmf-deprecated resources usage
  EOF

  spec.add_dependency 'puppet-lint', '~> 2.0.0'
  spec.add_development_dependency 'git', '~> 1.3'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rspec-its', '~> 1.0'
  spec.add_development_dependency 'rspec-collection_matchers', '~> 1.0'
  spec.add_development_dependency 'rake', '~> 12.0'
  spec.add_development_dependency 'rubocop', '~> 0.49.1'
end
