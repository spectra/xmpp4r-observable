class ThreadStore
	def initialize(max = 100)
		@store = []
		@max = max
		@cycles = 0
		@killer_thread = Thread.new do
			loop do
				sleep 2 while @store.empty?
				sleep 1
				@store.each_with_index do |thread, i|
					th = @store.delete_at(i) if thread.nil? or ! thread.alive?
					th = nil
				end
				@cycles += 1
			end
		end
	end

	def inspect
		sprintf("#<%s:0x%x @max=%d, @size=%d @cycles=%d>", self.class.name, __id__, @max, size, @cycles)
	end

	def add(thread)
		if thread.respond_to?(:alive?)
			@store << thread
			if @store.length > @max
				th = @store.shift
				th.kill
			end
		end
  end

	attr_reader :cycles, :max
	def size; @store.length; end

end # of class ThreadStore
