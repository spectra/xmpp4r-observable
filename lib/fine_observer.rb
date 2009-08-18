# This was based on Observable module from Ruby
module FineObservable
	def add_observer(thing, observer, func = :update)
		@things = {} unless defined? @things
		@things[thing] = {} unless ! @things[thing].nil?
		unless observer.respond_to? func
			raise NoMethodsError, "observer does not respond to `#{func.to_s}'"
		end
		@things[thing][observer] = func
	end

	def delete_observer(thing, observer)
		@things[thing].delete observer if defined? @things and ! @things[thing].nil?
	end

	def delete_observers(thing = nil)
		if thing.nil?
			@things.clear if defined? @things
		else
			@things[thing].clear if defined? @things and ! @things[thing].nil?
		end
	end

	def count_observers(thing = nil)
		return 0 if ! defined? @things
		size = 0
		if thing.nil?
			@things.each { |thing, hash|
				size += hash.size
			}
		else
			size = @things[thing].size unless @things[thing].nil?
		end
		size
	end

	def count_notifications(thing)
		return 0 if (! defined?(@things_counter)) or (! @things_counter.include?(thing))
		@things_counter[thing]
	end

	def changed(thing, state = true)
		@things_state = {} unless defined? @things_state
		@things_state[thing] = state
	end

	def changed?(thing)
		if defined? @things_state and @things_state[thing]
			true
		else
			false
		end
	end

	def notify_observers(thing, *arg)
		if defined? @things_state and @things_state[thing]
			if defined? @things and ! @things[thing].nil?
				@things[thing].each { |observer, func|
					increase_counter(thing)
					observer.send(func, thing, *arg)
				}
			end
			@things_state[thing] = false
		end
	end

	private
	def increase_counter(thing)
		@things_counter = {} unless defined? @things_counter
		@things_counter[thing] = 0 unless @things_counter.include?(thing)
		@things_counter[thing] += 1
	end
end
