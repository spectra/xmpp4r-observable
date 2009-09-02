class Observer
	attr_accessor :delete
	attr_reader :last, :last_args
	def initialize(name, time = 0)
		@name = name
		@last = ""
		@last_args = []
		@delete = false
		@time = time
	end

	def update(thing, *args)
		sleep @time if @time > 0
		@last = "#{@name}: got an update on #{thing} with args = #{args.join(', ')}"
		@last_args = args
		return :delete_me if @delete
	end

	def check(str)
		@last == str
	end

	def clear
		@last.clear
		@last_args.clear
	end
end

