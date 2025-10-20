module Support
  class FakeCache
    def initialize
      @h = {}
    end

    def [](k)
      @h[k]
    end

    def []=(k, v)
      @h[k] = v
    end

    def save!; true; end
  end
end

