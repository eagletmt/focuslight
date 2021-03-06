require "focuslight"

module Focuslight
  module Validator
    # Validator.validate(params, {
    #   :request_param_key_name => { # single key, single value
    #     :default => default_value,
    #     :rule => [
    #       Validator.rule(:not_null),
    #       Validator.rule(:int_range, 0..10),
    #     ],
    #   },
    #   :array_value_key_name => { # single key, array value
    #     :array => true
    #     :size => 1..10 # default is unlimited (empty also allowed)
    #     # default cannot be used
    #     :rule => [ ... ]
    #   }
    #   # ...
    #   [:param1, :param2, :param3] => {
    #     # default cannot be used
    #     :rule => Validator::Rule.new(->(p1, p2, p3){ ... }, "error_message")
    #   },
    # }
    def self.validate(params, spec)
      result = Result.new
      spec.each do |key, specitem|
        if key.is_a?(Array)
          validate_multi_key(result, params, key, specitem)
        elsif specitem[:array]
          validate_array(result, params, key, specitem)
        else
          validate_single(result, params, key, specitem)
        end
      end
      result
    end

    def self.validate_single(result, params, key_arg, spec)
      key = key_arg.to_sym

      value = params[key]
      if spec.has_key?(:default) && value.nil?
        value = spec[:default]
      end
      if spec[:excludable] && value.nil?
        result[key] = nil
        return
      end

      rules = [spec[:rule]].flatten.compact

      errors = []
      valid = true
      formatted = value

      rules.each do |rule|
        if rule.check(value)
          formatted = rule.format(value)
        else
          result.error(key, rule.message)
          valid = false
        end
      end

      if valid
        result[key] = formatted
      end
    end

    def self.validate_array(result, params, key_arg, spec)
      key = key_arg.to_sym

      values = params[key]
      if spec.has_key?(:default)
        raise ArgumentError, "array parameter cannot have :default"
      end
      if spec[:excludable] && value.nil?
        result[key] = []
      end

      if spec.has_key?(:size)
        if (values.nil? || values.size == 0) && !spec[:size].include?(0)
          result.error(key, "not allowed for empty")
          return
        end
        if !spec[:size].include?(values.size)
          result.error(key, "doesn't have values specified: #{spec[:size]}")
          return
        end
      end

      unless values.is_a?(Array)
        values = [values]
      end

      rules = [spec[:rule]].flatten.compact

      error_values = []
      valid = true
      formatted_values = []

      values.each do |value|
        errors = []
        formatted = nil
        rules.each do |rule|
          if rule.check(value)
            formatted = rule.format(value)
          else
            result.error(key, rule.message)
            valid = false
          end
        end
        error_values += errors
        formatted_values.push(formatted) if formatted
      end

      if valid
        result[key] = formatted_values
      end
    end

    def self.validate_multi_key(result, params, keys, spec)
      values = keys.map{|key| params[key.to_sym]}
      if spec.has_key?(:default)
        raise ArgumentError, "multi key validation spec cannot have :default"
      end

      rules = [spec[:rule]].flatten.compact
      errors = []

      rules.each do |rule|
        unless rule.check(*values)
          result.error(keys.map{|s| s.to_s}.join(','), rule.message)
        end
      end
    end

    class Rule
      attr_reader :message

      def initialize(checker, invalid_message, formatter=nil)
        @checker = checker
        @message = invalid_message
        @formatter = formatter
      end

      def check(*values)
        @checker.(*values)
      end

      def format(value)
        if @formatter && @formatter.is_a?(Symbol)
          value.send(@formatter)
        elsif @formatter
          @formatter.(value)
        else
          value
        end
      end
    end

    def self.rule(type, *args)
      args.flatten!
      case type
      when :not_blank
        Rule.new(->(v){not v.nil? and not v.strip.empty?}, "missing or blank", :strip)
      when :choice
        Rule.new(->(v){args.include?(v)}, "invalid value")
      when :int
        Rule.new(->(v){v =~ /^-?\d+$/}, "invalid integer", :to_i)
      when :uint
        Rule.new(->(v){v =~ /^\d+$/}, "invalid integer (>= 0)", :to_i)
      when :natural
        Rule.new(->(v){v =~ /^\d+$/ && v.to_i >= 1}, "invalid integer (>= 1)", :to_i)
      when :float, :double, :real
        Rule.new(->(v){v =~ /^\-?(\d+\.?\d*|\.\d+)(e[+-]\d+)?$/}, "invalid floating point num", :to_f)
      when :int_range
        Rule.new(->(v){args.first.include?(v.to_i)}, "invalid number in range #{args.first}", :to_i)
      when :bool
        Rule.new(->(v){v =~ /^(0|1|true|false)$/i}, "invalid bool value", ->(v){!!(v =~ /^(1|true)$/i)})
      when :regexp
        Rule.new(->(v){v =~ args.first}, "invalid input for pattern #{args.first.source}")
      when :lambda
        Rule.new(*args)
      else
        raise ArgumentError, "unknown validator rule: #{type}"
      end
    end

    class Result
      attr_reader :errors

      def initialize
        @errors = {}
        @params = {}
      end

      def hash
        @params.dup
      end

      def [](name)
        @params[name.to_sym]
      end

      def []=(name, value)
        @params[name.to_sym] = value
      end

      def error(param, message)
        @errors[param.to_sym] = "#{param}: " + message
      end

      def has_error?
        not @errors.empty?
      end
    end
  end
end
