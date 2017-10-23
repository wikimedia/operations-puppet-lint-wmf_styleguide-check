require 'spec_helper'

class_ok = <<-EOF
class foo {
      notice("foo!")
      include ::foo::configuration
      sysctl::setting { 'something':
          value => 10,
      }
}
EOF

class_ko = <<-EOF
class foo($t=hiera('foo::title')) {
       $msg = hiera( "foo::bar")
       notice($msg)
       notice($t)
       include ::passwords::redis
       class { 'bar': }
}
EOF

profile_ok = <<-EOF
class profile::foobar ($test=hiera('profile::foobar::test')) {
      require ::profile::foo
      include ::passwords::redis
      class { '::bar': }
}
EOF

profile_ko = <<-EOF
class profile::fixme (
      $test,
) {
    include ::apache2::common
    $role = hiera('role')
    system::role { $role: }
}
EOF

role_ok = <<-EOF
class role::fizzbuz {
      include standard
      include ::profile::base
      include ::profile::bar
      system::role { 'fizzbuzz': }
}
EOF

role_ko = <<-EOF
class role::fixme () {
      include ::monitoring::host
      include ::profile::base
      class { '::role::something': }
}
EOF

define_ok = <<-EOF
define foo::bar (
       sysctl::setting { 'test': }
       file { 'something':
          content => template('something.erb')
       }
)
EOF

describe 'wmf_styleguide' do
  context 'class correctly written' do
    let(:code) { class_ok }
    it 'should not detect any problems' do
      puts(problems)
      expect(problems).to have(0).problems
    end
  end
  context 'profile correctly written' do
    let(:code) { profile_ok }
    it 'should not detect any problems' do
      expect(problems).to have(0).problems
    end
  end
  context 'role correctly written' do
    let(:code) { role_ok }
    it 'should not detect any problems' do
      expect(problems).to have(0).problems
    end
  end

  context 'class with errors' do
    let(:code) { class_ko }
    it 'should create errors for hiera declarations' do
      expect(problems).to contain_error("wmf-style: Found hiera call in class 'foo' for 'foo::title'").on_line(1).in_column(14)
      expect(problems).to contain_error("wmf-style: Found hiera call in class 'foo' for 'foo::bar'").on_line(2).in_column(15)
    end
    it 'should create errors for included classes' do
      expect(problems).to contain_error("wmf-style: class 'foo' includes passwords::redis from another module").on_line(5).in_column(16)
      expect(problems).to contain_error("wmf-style: class 'foo' declares class bar from another module").on_line(6).in_column(16)
    end
  end

  context 'profile with errors' do
    let(:code) { profile_ko }
    it 'should create errors for parameters without hiera defaults' do
      expect(problems).to contain_error("wmf-style: Parameter 'test' of class 'profile::fixme' has no call to hiera").on_line(2).in_column(7)
    end
    it 'should create errors for hiera calls in body' do
      expect(problems).to contain_error("wmf-style: Found hiera call in class 'profile::fixme' for 'role'").on_line(5).in_column(13)
    end
    it 'should create errors for use of system::role' do
      expect(problems).to contain_error("wmf-style: class 'profile::fixme' declares system::role, which should only be used in roles").on_line(6).in_column(5)
    end
    it 'should create errors for non-explicit class inclusion' do
      expect(problems).to contain_error("wmf-style: profile 'profile::fixme' includes non-profile class apache2::common").on_line(4).in_column(13)
    end
  end

  context 'role with errors' do
    let(:code) { role_ko }
    it 'should generate errors for non-profile class inclusion' do
      expect(problems).to contain_error("wmf-style: role 'role::fixme' includes monitoring::host which is neither a role nor a profile")
    end
  end
  context 'defined type with no errors' do
    let(:code) { define_ok }
    it 'should not detect any problems' do
      expect(problems).to have(0).problems
    end
  end
end
