
module Nidyx
  class Property
    attr_reader :name, :attributes, :type, :type_name, :desc, :optional

    class UndefinedTypeError < StandardError; end
    class NonArrayEnumError < StandardError; end
    class UnsupportedEnumTypeError < StandardError; end

    # @param name [String] property name
    # @param class_name [String] class name, only for object properties
    # @param obj [Hash] the property object in schema format
    # @param optional [Boolean] true if the property can be null or empty
    def initialize(name, class_name, obj, optional)
      @name = name
      @optional = optional
      @type = process_json_type(obj)
      @attributes = ATTRIBUTES[@type]
      @type_name = lookup_type_name(@type, class_name)
      @desc = obj["description"]
    end

    # @return [Boolean] true if the obj-c property type is an object
    def is_obj?
      OBJECTS.include?(self.type)
    end

    private

    ATTRIBUTES = {
      :array      => "(strong, nonatomic)",
      :boolean    => "(assign, nonatomic)",
      :integer    => "(assign, nonatomic)",
      :unsigned   => "(assign, nonatomic)",
      :number     => "(nonatomic)",
      :number_obj => "(strong, nonatomic)",
      :string     => "(strong, nonatomic)",
      :object     => "(strong, nonatomic)",
      :id         => "(strong, nonatomic)"
    }

    # :object intentionally omitted
    TYPES = {
      :array      => "NSArray",
      :boolean    => "BOOL",
      :integer    => "NSInteger",
      :unsigned   => "NSUInteger",
      :number     => "double",
      :number_obj => "NSNumber",
      :string     => "NSString",
      :id         => "id"
    }

    # Hash and Array intentionally omitted
    ENUM_TYPES = {
      Fixnum     => "integer",
      String     => "string",
      NilClass   => "null",
      Float      => "number",
      TrueClass  => "boolean",
      FalseClass => "boolean"
    }

    OBJECTS = [ :array, :number_obj, :string, :object, :id ]

    BOXABLE_NUMBERS = [ "boolean", "integer", "number" ]

    SIMPLE_NUMBERS = [ "integer", "number" ]

    # @param type [Symbol] an obj-c property type
    # @param class_name [String] an object's type name
    # @return [String] the property's type name
    def lookup_type_name(type, class_name)
      type == :object ? class_name : TYPES[type]
    end

    # @param obj [Hash] the property object in schema format
    # @return [Symbol] an obj-c property type
    def process_json_type(obj)
      enum = obj["enum"]
      return process_enum_type(enum, obj) if enum

      type = obj["type"]
      if type.is_a?(Array)
        return process_array_type(type, obj)
      else
        return process_simple_type(type, obj)
      end
    end

    # @param enum [Array] an array of possible property values
    # @param obj [Hash] the property object in schema format
    # @return [Symbol] an obj-c property type
    def process_enum_type(enum, obj)
      raise NonArrayEnumError unless enum.is_a?(Array)

      types = enum.map { |a| a.class }.uniq
      raise UnsupportedEnumTypeError unless (types & [ Array, Hash ]).empty?

      process_array_type(types.map { |t| ENUM_TYPES[t] }, obj)
    end

    # @param type [String] a property type string
    # @param obj [Hash] the property object in schema format
    # @return [Symbol] an obj-c property type
    def process_simple_type(type, obj)
      case type
      when "boolean", "number"
        return self.optional ? :number_obj : type.to_sym

      when "integer"
        return :number_obj if self.optional
        (obj["minimum"] && obj["minimum"] >= 0) ? :unsigned : :integer

      when "null"
        @optional = true
        return :id

      when nil
        raise UndefinedTypeError

      else
        return type.to_sym
      end
    end

    # @param type [Array] an array of property types
    # @param obj [Hash] the property object in schema format
    # @return [Symbol] an obj-c property type
    def process_array_type(type, obj)
      # if the key is optional
      if type.include?("null")
        @optional = true
        type -= ["null"]
      end

      # single optional type
      return process_simple_type(type.shift, obj) if type.size == 1

      return :number if (type - SIMPLE_NUMBERS).empty? && !@optional
      return :number_obj if (type - BOXABLE_NUMBERS).empty?

      :id
    end
  end
end
