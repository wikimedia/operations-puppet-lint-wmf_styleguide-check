# Class to manage puppet resources.
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
    @params || parse_params
  end

  def profile_module
    @profile_module || 'profile'
  end

  def role_module
    @role_module || 'role'
  end

  def class?
    @resource[:type] == :CLASS
  end

  def name
    @resource[:name_token].value.gsub(/^::/, '')
  end

  def path
    @resource[:path]
  end

  def filename
    puts @resource
    @resource[:filename]
  end

  def module_name
    name.split('::')[0]
  end

  def profile?
    class? && (module_name == profile_module)
  end

  def role?
    class? && (module_name == role_module)
  end

  def hiera_calls
    @resource[:tokens].select(&:hiera?)
  end

  def included_classes
    @resource[:tokens].map(&:included_class).compact
  end

  def declared_classes
    @resource[:tokens].map(&:declared_class).compact
  end

  def declared_resources
    @resource[:tokens].select(&:declared_type?)
  end

  def resource?(name)
    @resource[:tokens].select { |t| t.declared_type? && t.value.gsub(/^::/, '') == name }
  end
end

class PuppetLint
  class Lexer
    # Add some utility functions to the PuppetLint::Lexer::Token class
    class Token
      # Extend the basic token with utility functions
      def function?
        @type == :NAME && @next_code_token.type == :LPAREN
      end

      def hiera?
        function? && @value == 'hiera'
      end

      def class_include?
        @type == :NAME && ['include', 'require'].include?(@value) && @next_code_token.type != :FARROW
      end

      def included_class
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
        @type == :NAME && @next_code_token.type == :LBRACE && @prev_code_token.type != :CLASS
      end
    end
  end
end

# Checks and functions
def check_profile(klass)
  # All parameters of profiles should have a default value that is a hiera lookup
  params_without_hiera_defaults klass
  # All hiera lookups should be in parameters
  hiera_not_in_params klass
  # Only a few selected classes should be included in a profile
  profile_illegal_include klass
  # System::role only goes in roles
  check_no_system_role klass
end

def check_role(klass)
  # Hiera lookups within a role are forbidden
  hiera klass
  # A role should only include profiles
  include_not_profile klass
  # A call, and only one, to system::role will be done
  check_system_role klass
  # No defines should be present in a role
  check_no_defines klass
end

def check_class(klass)
  # No hiera lookups allowed in a class.
  hiera klass
  # Cannot include or declare classes from other modules
  class_illegal_include klass
  illegal_class_declaration klass
  # System::role only goes in roles
  check_no_system_role klass
end

def check_define(define)
  # No hiera calls are admitted in defines. ever.
  hiera define
  # No class can be included in defines, like in classes
  class_illegal_include define
  # Non-profile defines should respect the rules for classes
  illegal_class_declaration define unless define.module_name == 'profile'
end

def hiera(klass)
  hiera_errors(klass.hiera_calls, klass)
end

def params_without_hiera_defaults(klass)
  # Finds parameters that have no hiera-defined default value.
  klass.params.each do |name, data|
    next unless data[:value].select(&:hiera?).empty?
    token = data[:param]
    msg = {
      message: "wmf-style: Parameter '#{name}' of class '#{klass.name}' has no call to hiera",
      line: token.line,
      column: token.column
    }
    notify :error, msg
  end
end

def hiera_not_in_params(klass)
  tokens = klass.hiera_calls.reject do |token|
    maybe_param = token.prev_code_token.prev_code_token
    klass.params.keys.include?(maybe_param.value)
  end
  hiera_errors(tokens, klass)
end

def hiera_errors(tokens, klass)
  tokens.each do |token|
    value = token.next_code_token.next_code_token.value
    msg = {
      message: "wmf-style: Found hiera call in #{klass.type} '#{klass.name}' for '#{value}'",
      line: token.line,
      column: token.column
    }
    notify :error, msg
  end
end

def profile_illegal_include(klass)
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
  modules_include_ok = ['role', 'profile', 'standard']
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
  return if klass.resource?('system::role').length == 1
  msg = {
    message: "wmf-style: role '#{klass.name}' should declare system::role once",
    line: 1,
    column: 1
  }
  notify :error, msg
end

def check_no_defines(klass)
  return if klass.declared_resources == klass.resource?('system::role')
  msg = {
    message: "wmf-style: role '#{klass.name}' should not include defines",
    line: 1,
    column: 1
  }
  notify :error, msg
end

PuppetLint.new_check(:wmf_styleguide) do
  def check
    # Modules whose classes can be included elsewhere
    class_indexes.each do |cl|
      klass = PuppetResource.new(cl)
      if klass.profile?
        check_profile klass
      elsif klass.role?
        check_role klass
      else
        check_class klass
      end
    end
    defined_type_indexes.each do |df|
      define = PuppetResource.new(df)
      check_define define
    end
  end
end
