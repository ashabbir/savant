# frozen_string_literal: true

module Support
  class FakeCache
    def initialize
      @h = {}
    end

    def [](key)
      @h[key]
    end

    def []=(key, value)
      @h[key] = value
    end

    def save!
      true
    end
  end
end
