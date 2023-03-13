# frozen_string_literal: true

# Class to manage puppet resources.
# See how we extend PuppetLint::Lexer::Token below to understand how we filter
# tokens within a parsed resource.
class PuppetResource
  attr_accessor :profile_module, :role_module

  def initialize(resource_hash)
    # Input should be a resource coming from
    # the resource index
    @resource = resource_hash
    @params = parse_params
  end

  def type
    if class?
      'class'
    else
      'defined type'
    end
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength
  def parse_params
    # Parse parameters and return a hash containing
    # the parameter name as a key and a hash of tokens as value:
    #  :param => the parameter token
    #  :value => All the code tokens that represent the value of the parameter
    res = {}
    current_param = nil
    in_value = false
    return res unless @resource[:param_tokens]
    @resource[:param_tokens].each do |token|
      case token.type
      when :VARIABLE
        current_param = token.value
        res[current_param] ||= { param: token, value: [] }
      when :COMMA
        current_param = nil
        in_value = false
      when :EQUALS
        in_value = true
      when *PuppetLint::Lexer::FORMATTING_TOKENS
        # Skip non-code tokens
        next
      else
        res[current_param][:value] << token if in_value && token
      end
    end
    res
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength

  def params
    # Lazy-load and return all the parameters of the resource
    @params || parse_params
  end

  def profile_module
    # Return the name of the module where profiles are located
    @profile_module || 'profile'
  end

  def role_module
    # Return the name of the module where roles are located
    @role_module || 'role'
  end

  def class?
    # True if this is a class,
    @resource[:type] == :CLASS
  end

  def name
    # Extract a normalized resource name (without the :: prefix if present)
    @resource[:name_token].value.gsub(/^::/, '')
  end

  def path
    # Path of the resource
    @resource[:path]
  end

  def filename
    # File name of the resource
    @resource[:filename]
  end

  def module_name
    # Module containing this resource
    name.split('::')[0]
  end

  def profile?
    # True if the resource is in the profile module
    class? && (module_name == profile_module)
  end

  def role?
    # True if the resource is in the role module
    class? && (module_name == role_module)
  end

  def lookup_calls
    # Returns an array of all the tokens referencing calls to lookup
    @resource[:tokens].select(&:lookup?)
  end

  def legacy_hiera_calls
    # Returns an array of all the tokens referencing calls to hiera
    @resource[:tokens].select(&:legacy_hiera?)
  end

  def legacy_validate_calls
    # Returns an array of all the tokens referencing calls to a stdlib legacy validate function
    @resource[:tokens].select(&:legacy_validate?)
  end

  def included_classes
    # Returns an array of all the classes included (with require/include)
    @resource[:tokens].map(&:included_class).compact
  end

  def declared_classes
    # Returns an array of all the declared classes
    @resource[:tokens].map(&:declared_class).compact
  end

  def declared_resources
    # Returns an array of all the declared classes
    @resource[:tokens].select(&:declared_type?)
  end

  def resource?(name)
    # Arguments:
    #   name (string) Name of the resource we want to search
    # Returns an array of all the defines of the specified resource
    @resource[:tokens].select { |t| t.declared_type? && t.value.gsub(/^::/, '') == name }
  end
end

class PuppetLint
  class Lexer
    # Add some utility functions to the PuppetLint::Lexer::Token class
    class Token
      # Extend the basic token with utility functions
      def function?
        # A function is something that has a name and is followed by a left parens
        [:NAME, :FUNCTION_NAME].include?(@type) && @next_code_token.type == :LPAREN
      end

      def legacy_hiera?
        # Using old hiera call
        function? && ['hiera', 'hiera_array', 'hiera_hash'].include?(@value)
      end

      def lookup?
        # A function call specifically calling lookup
        function? && ['lookup'].include?(@value)
      end

      def legacy_validate?
        # A function calling one of the legacy stdlib validate functions
        function? && @value.start_with?('validate_')
      end

      def class_include?
        # Check for include-like objects
        @type == :NAME && ['include', 'require', 'contain'].include?(@value) && @next_code_token.type != :FARROW
      end

      def included_class
        # Fetch the token describing the included class
        return unless class_include?
        return @next_code_token.next_code_token if @next_code_token.type == :LPAREN
        @next_code_token
      end

      def declared_class
        return unless @type == :CLASS
        # In a class declaration, the first token is the class declaration itself.
        return if @next_code_token.type != :LBRACE
        @next_code_token.next_code_token
      end

      def declared_type?
        # The token is a name and the next token is a {, while the previous one is not "class"
        @type == :NAME && @next_code_token.type == :LBRACE && @prev_code_token.type != :CLASS
      end

      def node_def?
        [:SSTRING, :STRING, :NAME, :REGEX].include?(@type)
      end

      def role_keyword?
        # This is a function with name "role"
        @type == :NAME && @value = 'role' && @next_code_token.type == :LPAREN
      end
    end
  end
end

# Checks and functions
def check_profile(klass)
  # All parameters of profiles should have a default value that is a lookup
  params_without_lookup_defaults klass
  # All lookup lookups should be in parameters
  lookup_not_in_params klass
  # Only a few selected classes should be included in a profile
  profile_illegal_include klass
  # System::role only goes in roles
  check_no_system_role klass
end

def check_role(klass)
  # Hiera lookups within a role are forbidden
  lookup klass
  # A role should only include profiles
  include_not_profile klass
  # A call, and only one, to system::role will be done
  check_system_role klass
  # No defines should be present in a role
  check_no_defines klass
end

def check_class(klass)
  # No lookup lookups allowed in a class.
  lookup klass
  # Cannot include or declare classes from other modules
  class_illegal_include klass
  illegal_class_declaration klass
  # System::role only goes in roles
  check_no_system_role klass
end

def check_define(define)
  # No lookup calls are admitted in defines. ever.
  lookup define
  # No class can be included in defines, like in classes
  class_illegal_include define
  # Non-profile defines should respect the rules for classes
  illegal_class_declaration define unless define.module_name == 'profile'
end

def lookup(klass)
  # Searches for lookup calls inside classes and defines.
  lookup_errors(klass.lookup_calls, klass)
end

def legacy_hiera(klass)
  # No calls to legacy hiera
  tokens = klass.legacy_hiera_calls
  tokens.each do |token|
    msg = {
      message: "wmf-style: Found deprecated function (#{token.value}) " \
               "in #{klass.type} '#{klass.name}', use lookup instead",
      line: token.line,
      column: token.column
    }
    notify :error, msg
  end
end

def params_without_lookup_defaults(klass)
  # Finds parameters that have no lookup-defined default value.
  klass.params.each do |name, data|
    next unless data[:value].select(&:lookup?).empty?
    common = "wmf-style: Parameter '#{name}' of class '#{klass.name}'"
    message = if data[:value].select(&:legacy_hiera?).empty?
                "#{common} has no call to lookup"
              else
                "#{common} hiera is deprecated use lookup"
              end
    token = data[:param]
    msg = { message: message, line: token.line, column: token.column }
    notify :error, msg
  end
end

def lookup_not_in_params(klass)
  # Checks if a lookup call is not in a parameter declaration. Used to check profiles
  # Any lookup call that is not inside a parameter declaration is a violation
  tokens = klass.lookup_calls.reject do |token|
    maybe_param = token.prev_code_token.prev_code_token
    klass.params.keys.include?(maybe_param.value)
  end
  lookup_errors(tokens, klass)
end

def lookup_errors(tokens, klass)
  # Helper for printing lookup errors nicely
  tokens.each do |token|
    # lookup ( 'some::label' )
    value = token.next_code_token.next_code_token.value
    msg = {
      message: "wmf-style: Found lookup call in #{klass.type} '#{klass.name}' for '#{value}'",
      line: token.line,
      column: token.column
    }
    notify :error, msg
  end
end

def legacy_validate_errors(klass)
  # Helper for printing errors nicely
  klass.legacy_validate_calls.each do |token|
    msg = {
      message: "wmf-style: Found legacy function (#{token.value}) call in #{klass.type} '#{klass.name}'",
      line: token.line,
      column: token.column
    }
    notify :error, msg
  end
end

def profile_illegal_include(klass)
  # Check if a profile includes any class that's not allowed there.
  # Allowed are: any other profile, or a class from the passwords module,
  # plus a couple parameter classes
  modules_include_ok = ['profile', 'passwords']
  classes_include_ok = ['lvs::configuration', 'network::constants']
  klass.included_classes.each do |token|
    class_name = token.value.gsub(/^::/, '')
    next if classes_include_ok.include? class_name
    module_name = class_name.split('::')[0]
    next if modules_include_ok.include? module_name
    msg = {
      message: "wmf-style: profile '#{klass.name}' includes non-profile class #{class_name}",
      line: token.line,
      column: token.column
    }
    notify :error, msg
  end
end

def class_illegal_include(klass)
  # A class should only include classes from the same module.
  modules_include_ok = [klass.module_name]
  klass.included_classes.each do |token|
    class_name = token.value.gsub(/^::/, '')
    module_name = class_name.split('::')[0]
    next if modules_include_ok.include? module_name
    msg = {
      message: "wmf-style: #{klass.type} '#{klass.name}' includes #{class_name} from another module",
      line: token.line,
      column: token.column
    }
    notify :error, msg
  end
end

def include_not_profile(klass)
  # Checks that a role only includes other roles and profiles
  modules_include_ok = ['role', 'profile']
  klass.included_classes.each do |token|
    class_name = token.value.gsub(/^::/, '')
    module_name = class_name.split('::')[0]
    next if modules_include_ok.include? module_name
    msg = {
      message: "wmf-style: role '#{klass.name}' includes #{class_name} which is neither a role nor a profile",
      line: token.line,
      column: token.column
    }
    notify :error, msg
  end
end

def illegal_class_declaration(klass)
  # Classes and defines should NEVER declare
  # classes from other modules.
  # If a class has multiple such occurrences, it should be a profile
  klass.declared_classes.each do |token|
    class_name = token.value.gsub(/^::/, '')
    module_name = class_name.split('::')[0]
    next if klass.module_name == module_name
    msg = {
      message: "wmf-style: #{klass.type} '#{klass.name}' declares class #{class_name} from another module",
      line: token.line,
      column: token.column
    }
    notify :error, msg
  end
end

def check_no_system_role(klass)
  # The system::role define should only be used in roles
  klass.resource?('system::role').each do |token|
    msg = {
      message: "wmf-style: #{klass.type} '#{klass.name}' declares system::role, which should only be used in roles",
      line: token.line,
      column: token.column
    }
    notify :error, msg
  end
end

def check_system_role(klass)
  # Check that a role does indeed declare system::role
  return if klass.resource?('system::role').length == 1
  msg = {
    message: "wmf-style: role '#{klass.name}' should declare system::role once",
    line: 1,
    column: 1
  }
  notify :error, msg
end

def check_no_defines(klass)
  # In a role, check if there is any define apart from one system::role call
  return if klass.declared_resources == klass.resource?('system::role')
  msg = {
    message: "wmf-style: role '#{klass.name}' should not include defines",
    line: 1,
    column: 1
  }
  notify :error, msg
end

def check_deprecations(resource)
  # Check the resource for declarations of deprecated defines
  legacy_validate_errors resource
  legacy_hiera resource
  deprecated_defines = ['base::service_unit']
  deprecated_defines.each do |deprecated|
    resource.resource?(deprecated).each do |token|
      msg = {
        message: "wmf-style: '#{resource.name}' should not include the deprecated define '#{token.value}'",
        line: token.line,
        column: token.column
      }
      notify :error, msg
    end
  end
end

# rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/AbcSize, Metrics/CyclomaticComplexity
def check_node(node)
  title = node[:title_tokens].map(&:value).join(', ')
  node[:tokens].each do |token|
    msg = nil
    if token.lookup?
      msg = {
        message: "wmf-style: node '#{title}' calls lookup function",
        line: token.line,
        column: token.column
      }
    elsif token.legacy_hiera?
      msg = {
        message: "wmf-style: node '#{title}' calls legacy #{token.value} function",
        line: token.line,
        column: token.column
      }
    elsif token.class_include?
      msg = {
        message: "wmf-style: node '#{title}' includes class #{token.included_class.value}",
        line: token.line,
        column: token.column
      }
    elsif token.declared_class
      msg = {
        message: "wmf-style: node '#{title}' declares class #{token.declared_class.value}",
        line: token.line,
        column: token.column
      }
    elsif token.declared_type? && token.value != 'interface::add_ip6_mapped'
      msg = {
        message: "wmf-style: node '#{title}' declares #{token.value}",
        line: token.line,
        column: token.column
      }
    end
    notify :error, msg if msg
  end
end

PuppetLint.new_check(:wmf_styleguide) do
  def node_indexes
    # Override the faulty "node_indexes" method from puppet-lint
    result = []
    in_node_def = false
    braces_level = nil
    start = 0
    title_tokens = []
    tokens.each_with_index do |token, i|
      if token.type == :NODE
        braces_level = 0
        start = i
        in_node_def = true
        next
      end
      # If we're not within a node definition, skip this token
      next unless in_node_def
      case token.type
      when :REGEX
        if !token.value.start_with?('^') || !token.value.end_with?('$')
          msg = {
            message: "wmf-style: regex node matching must match the whole string (^...$), got: #{token.value}",
            line: token.line,
            column: token.column,
            token: token,
            problem: 'node_regex'
          }
          notify :error, msg
        end
      when :LBRACE
        title_tokens = tokens[start + 1..(i - 1)].select(&:node_def?) if braces_level.zero?
        braces_level += 1
      when :RBRACE
        braces_level -= 1
        if braces_level.zero?
          result << {
            start: start,
            end: i,
            tokens: tokens[start..i],
            title_tokens: title_tokens
          }
          in_node_def = false
        end
      end
    end
    result
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PercievedComplexity

  def check_classes
    class_indexes.each do |cl|
      klass = PuppetResource.new(cl)
      if klass.profile?
        check_profile klass
      elsif klass.role?
        check_role klass
      else
        check_class klass
      end
      check_deprecations klass
    end
  end

  def check
    check_classes
    defined_type_indexes.each do |df|
      define = PuppetResource.new(df)
      check_define define
      check_deprecations define
    end
    node_indexes.each do |node|
      check_node node
    end
  end

  def fix_node_regex(problem)
    problem[:token].value.insert(0, '^') unless problem[:token].value.start_with?('^')
    problem[:token].value << '$' unless problem[:token].value.end_with?('$')
  end

  def fix(problem)
    raise PuppetLint::NoFix unless problem[:problem] == 'node_regex'
    method = "fix_#{problem[:problem]}"
    send(method, problem) if respond_to? method
  end
end
