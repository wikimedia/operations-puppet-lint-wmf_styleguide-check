# frozen_string_literal: true

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
       $msg = lookup( "foo::bar")
       notice($msg)
       notice($t)
       include ::passwords::redis
       class { 'bar': }
       validate_foobar($param)
       validate_re($param, '^.*$')
       hiera('foobar')
       hiera_hash('foobar')
       hiera_array('foobar')
}
EOF

profile_ok = <<-EOF
class profile::foobar (
      $test=lookup('profile::foobar::test'),
) {
      require ::profile::foo
      include ::passwords::redis
      class { '::bar': }
}
EOF

profile_ko = <<-EOF
class profile::fixme (
      $test1,
      $test2=hiera('profile::foobar::foo')
      $test3=hiera_array('profile::foobar::foo')
      $test4=hiera_hash('profile::foobar::foo')
) {
    include ::apache2::common
    $role = lookup('role')
    system::role { $role: }
}
EOF

role_ok = <<-EOF
class role::fizzbuz {
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

define_ko = <<-EOF
define foo::fixme ($a=hiera('something')) {
       include ::foo
       class { '::bar': }
       validate_foobar($param)
       validate_re($param, '^.*$')
       hiera('foobar')
       hiera_hash('foobar')
       hiera_array('foobar')
}
EOF

node_ok = <<-EOF
node /^test1.*\\.eqiad\\./ {
     role(spare::system)
}
EOF

node_ok_wikimedia = <<-EOF
node /^test1.*\\.wikimedia\\./ {
     role(spare::system)
}
EOF

node_default = <<-EOF
node default {
     role(spare::system)
}
EOF

node_ko = <<-EOF
node 'fixme' {
     include base::firewall
     interface::mapped { 'eth0':
        foo => 'bar'
     }
     lookup('foobar')
     hiera('foobar')
     hiera_array('foobar')
     hiera_hash('foobar')
}
EOF

node_regex_with_wmf_tld = <<-EOF
node /^test1.*\\.eqiad\\.wmnet/ {
     role(spare::system)
}
EOF

node_regex_with_org_tld = <<-EOF
node /^test1.*\\.wikimedia\\.org/ {
     role(spare::system)
}
EOF

node_regex_missing_start = <<-EOF
node /test1.*\\.eqiad\\./ {
     role(spare::system)
}
EOF

node_regex_with_end = <<-EOF
node /^test1.*\\.eqiad\\.wmnet$/ {
     role(spare::system)
}
EOF

node_regex_fixed = <<-EOF
node /^test1.*\\.eqiad\\./ {
     role(spare::system)
}
EOF

node_regex_fixed_wmf_tld = <<-EOF
node /^test1.*\\.eqiad\\./ {
     role(spare::system)
}
EOF

deprecation_ko = <<-EOF
define test() {
   base::service_unit{ 'test2': }
}
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
      expect(problems).to contain_error("wmf-style: Found deprecated function (hiera) in class 'foo', use lookup instead").on_line(1).in_column(14)
      expect(problems).to contain_error("wmf-style: Found lookup call in class 'foo' for 'foo::bar'").on_line(2).in_column(15)
    end
    it 'should create errors for included classes' do
      expect(problems).to contain_error("wmf-style: class 'foo' includes passwords::redis from another module").on_line(5).in_column(16)
      expect(problems).to contain_error("wmf-style: class 'foo' declares class bar from another module").on_line(6).in_column(16)
    end
    it 'should create errors for validate_function' do
      expect(problems).to contain_error("wmf-style: Found legacy function (validate_foobar) call in class 'foo'").on_line(7).in_column(8)
      expect(problems).to contain_error("wmf-style: Found legacy function (validate_re) call in class 'foo'").on_line(8).in_column(8)
    end
    it 'should create errors for hiera function' do
      expect(problems).to contain_error("wmf-style: Found deprecated function (hiera) in class 'foo', use lookup instead").on_line(9).in_column(8)
    end
    it 'should create errors for hiera_hash function' do
      expect(problems).to contain_error("wmf-style: Found deprecated function (hiera_hash) in class 'foo', use lookup instead").on_line(10).in_column(8)
    end
    it 'should create errors for hiera_array function' do
      expect(problems).to contain_error("wmf-style: Found deprecated function (hiera_array) in class 'foo', use lookup instead").on_line(11).in_column(8)
    end
  end

  context 'profile with errors' do
    let(:code) { profile_ko }
    it 'should create errors for parameters without hiera defaults' do
      expect(problems).to contain_error("wmf-style: Parameter 'test1' of class 'profile::fixme' has no call to lookup").on_line(2).in_column(7)
      expect(problems).to contain_error("wmf-style: Parameter 'test2' of class 'profile::fixme' hiera is deprecated use lookup").on_line(3).in_column(7)
      expect(problems).to contain_error("wmf-style: Parameter 'test3' of class 'profile::fixme' hiera is deprecated use lookup").on_line(4).in_column(7)
      expect(problems).to contain_error("wmf-style: Parameter 'test4' of class 'profile::fixme' hiera is deprecated use lookup").on_line(5).in_column(7)
    end
    it 'should create errors for hiera calls in body' do
      expect(problems).to contain_error("wmf-style: Found lookup call in class 'profile::fixme' for 'role'").on_line(8).in_column(13)
    end
    it 'should create errors for use of system::role' do
      expect(problems).to contain_error("wmf-style: class 'profile::fixme' declares system::role, which should only be used in roles").on_line(9).in_column(5)
    end
    it 'should create errors for non-explicit class inclusion' do
      expect(problems).to contain_error("wmf-style: profile 'profile::fixme' includes non-profile class apache2::common").on_line(7).in_column(13)
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
  context 'defined type with violations' do
    let(:code) { define_ko }
    it 'should not contain hiera calls' do
      expect(problems).to contain_error("wmf-style: Found deprecated function (hiera) in defined type 'foo::fixme', use lookup instead").on_line(1)
    end
    it 'should not include or define any class' do
      expect(problems).to contain_error("wmf-style: defined type 'foo::fixme' declares class bar from another module").on_line(3)
    end
    it 'should create errors for validate_function' do
      expect(problems).to contain_error("wmf-style: Found legacy function (validate_foobar) call in defined type 'foo::fixme'").on_line(4).in_column(8)
      expect(problems).to contain_error("wmf-style: Found legacy function (validate_re) call in defined type 'foo::fixme'").on_line(5).in_column(8)
    end
    it 'should create errors for hiera function' do
      expect(problems).to contain_error("wmf-style: Found deprecated function (hiera) in defined type 'foo::fixme', use lookup instead").on_line(6).in_column(8)
    end
    it 'should create errors for hiera_hash function' do
      expect(problems).to contain_error("wmf-style: Found deprecated function (hiera_hash) in defined type 'foo::fixme', use lookup instead").on_line(7).in_column(8)
    end
    it 'should create errors for hiera_array function' do
      expect(problems).to contain_error("wmf-style: Found deprecated function (hiera_array) in defined type 'foo::fixme', use lookup instead").on_line(8).in_column(8)
    end
  end

  context 'node with no errors' do
    let(:code) { node_ok }
    it 'should not detect any problems' do
      expect(problems).to have(0).problems
    end
  end

  context 'node wikimedia.org with no errors' do
    let(:code) { node_ok_wikimedia }
    it 'should not detect any problems' do
      expect(problems).to have(0).problems
    end
  end

  context 'node default with no errors' do
    let(:code) { node_default }
    it 'should not detect any problems' do
      expect(problems).to have(0).problems
    end
  end

  context 'node with violations' do
    let(:code) { node_ko }
    it 'should not include classes directly' do
      expect(problems).to contain_error("wmf-style: node 'fixme' includes class base::firewall")
    end
    it 'should not declare any defined type' do
      expect(problems).to contain_error("wmf-style: node 'fixme' declares interface::mapped")
    end
    it 'should not call lookup' do
      expect(problems).to contain_error("wmf-style: node 'fixme' calls lookup function")
    end
    it 'should not call hiera' do
      expect(problems).to contain_error("wmf-style: node 'fixme' calls legacy hiera function")
    end
    it 'should not call hiera_array' do
      expect(problems).to contain_error("wmf-style: node 'fixme' calls legacy hiera_array function")
    end
    it 'should not call hiera_hash' do
      expect(problems).to contain_error("wmf-style: node 'fixme' calls legacy hiera_hash function")
    end
    it 'should use a regex' do
      expect(problems).to contain_error('wmf-style: node definition must use a regex, got: fixme')
    end
  end

  context 'node regex with wmnet tld violation' do
    let(:code) { node_regex_with_wmf_tld }
    it 'should not contain the wmnet tld' do
      expect(problems).to contain_error("wmf-style: node regex must not contain the '.wmnet' tld got: ^test1.*\\.eqiad\\.wmnet")
    end
  end

  context 'node regex with org tld violation' do
    let(:code) { node_regex_with_org_tld }
    it 'should not contain the wmnet tld' do
      expect(problems).to contain_error("wmf-style: node regex must not contain the '.org' tld got: ^test1.*\\.wikimedia\\.org")
    end
  end

  context 'node regex with start violation' do
    let(:code) { node_regex_missing_start }
    it 'should start the regex with ^' do
      expect(problems).to contain_error("wmf-style: node regex must match the start of the hostname with '^' got: test1.*\\.eqiad\\.")
    end
  end

  context 'node regex with end violation' do
    let(:code) { node_regex_with_end }
    it 'should not end the regex with $' do
      expect(problems).to contain_error("wmf-style: node regex must not match the end of the hostname with '$' got: ^test1.*\\.eqiad\\.wmnet$")
    end
  end

  context 'defined type with deprecations' do
    let(:code) { deprecation_ko }
    it 'should not' do
      expect(problems).to contain_error("wmf-style: 'test' should not include the deprecated define 'base::service_unit'")
    end
  end

  context 'with fix enabled' do
    before do
      PuppetLint.configuration.fix = true
    end

    after do
      PuppetLint.configuration.fix = false
    end

    context 'node regex with start violation' do
      let(:code) { node_regex_missing_start }
      it { expect(manifest).to eq(node_regex_fixed) }
    end
    context 'node regex with end violation' do
      let(:code) { node_regex_with_end }
      it { expect(manifest).to eq(node_regex_fixed) }
    end
    context 'node regex with tld violation' do
      let(:code) { node_regex_with_wmf_tld }
      it { expect(manifest).to eq(node_regex_fixed_wmf_tld) }
    end
  end
end
