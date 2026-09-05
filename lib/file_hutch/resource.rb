# frozen_string_literal: true

module FileHutch
  # Thin, immutable wrapper over an API JSON object.
  class Resource
    attr_reader :attributes, :client

    def initialize(attributes, client: nil)
      @attributes = (attributes || {}).transform_keys(&:to_s).freeze
      @client = client
    end

    def [](key) = attributes[key.to_s]
    def id = self["id"]
    def to_h = attributes.dup
    def to_param = id
    def to_s = id.to_s
    def as_json(*) = to_h
    def to_json(*args) = to_h.to_json(*args)
    def ==(other) = other.class == self.class && other.attributes == attributes
    alias eql? ==
    def hash = [ self.class, attributes ].hash
    def inspect = "#<#{self.class.name} #{attributes.map { |k, v| "#{k}=#{v.inspect}" }.join(' ')}>"

    def self.attribute(*names)
      names.each { |name| define_method(name) { self[name] } }
    end

    def self.time_attribute(*names)
      names.each do |name|
        define_method(name) do
          value = self[name]
          value && Time.iso8601(value)
        end
      end
    end

    private

    def client!
      client || FileHutch.client
    end
  end
end
