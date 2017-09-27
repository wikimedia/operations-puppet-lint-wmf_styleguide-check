# puppet-lint-wmf_styleguide check
Puppet-lint plugin to check for violations of the WMF puppet coding style guide.

There are quite a few prescriptions for how to write puppet manifests in the
puppet coding page at https://wikitech.wikimedia.org/wiki/Puppet_coding.

While most of the coding style requirements are already covered by puppet-lint,
quite a few of them are not, specifically our own flavour of the role/profile
pattern.

This plugin checks those specific violations, so we have specific checks for
classes, roles, profiles and defined types. Let's see which in order.

For classes in modules, we check that:
* no hiera() call is made
* no class inclusion or declaration happens across modules
* no system::role call is made

For roles, we check that:
* no hiera() call is made
* no class is included that is not a profile
* no class is explicitly declared [TODO]
* one and only one system::role call is made

For profiles, our checks are:
* Every parameter has an explicit hiera() call
* No hiera() call is made outside of parameters
* No classes are included that are not globals or profiles
* No system::role declaration

For defined types, we check that:
* no hiera() call is made
* no class from other modules is either included or declared (except for defined
  types in the profile module, which can declare classes from other modules).

While some of the rules are not enforced right now (so we don't check for
defines from other modules), that can be refined in the future.

This plugin will output a ton of errors when ran on the operations/puppet
repository as it stands now, and that's good as it gives us a good measure of
where we are in the transition, and will help enforce the style guide afterwards.
