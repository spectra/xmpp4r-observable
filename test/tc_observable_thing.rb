$: <<  File.dirname(__FILE__) + "/../lib"
require 'test/unit'
require 'observable_thing'
require 'simple_observer.rb'

class TestObservableThing < Test::Unit::TestCase
	include ObservableThing

	def setup
		@observer1 = Observer.new("observer 1")
		@observer2 = Observer.new("observer 2")
		@observer3 = Observer.new("observer 3", 10)
	end

	def teardown
		@things.clear if defined? @things
		@things_counter.clear if defined? @things_counter
		@things_state.clear if defined? @things_state
	end

	def test_add_observer
		self.add_observer(:one_thing, @observer1)
		assert @things.include?(:one_thing)
		assert @things[:one_thing].include?(@observer1)
		assert_equal :update, @things[:one_thing][@observer1]

		self.add_observer(:other_thing, @observer2)
		assert @things.include?(:other_thing)
		assert @things[:other_thing].include?(@observer2)
		assert_equal :update, @things[:other_thing][@observer2]

		assert_raise(NoMethodError) {
			self.add_observer(:other_thing, @observer1, :no_method)
		}
	end

	def test_delete_observer
		self.add_observer(:one_thing, @observer1)

		assert @things[:one_thing].include?(@observer1)
		self.delete_observer(:one_thing, @observer1)
		assert ! @things[:one_thing].include?(@observer1)
	end

	def test_delete_observers
		self.add_observer(:one_thing, @observer1)
		self.add_observer(:one_thing, @observer2)
		self.add_observer(:other_thing, @observer1)

		assert @things[:one_thing].include?(@observer1)
		assert @things[:one_thing].include?(@observer2)
		assert @things[:other_thing].include?(@observer1)
		self.delete_observers(:one_thing)
		assert ! @things[:one_thing].include?(@observer1)
		assert ! @things[:one_thing].include?(@observer2)
		assert @things[:other_thing].include?(@observer1)

		self.add_observer(:one_thing, @observer1)
		self.add_observer(:one_thing, @observer2)
		assert ! @things.empty?
		self.delete_observers
		assert @things.empty?
	end

	def test_count_observers
		self.add_observer(:one_thing, @observer1)
		self.add_observer(:one_thing, @observer2)
		self.add_observer(:other_thing, @observer1)

		assert_equal 3, self.count_observers
		assert_equal 2, self.count_observers(:one_thing)
		assert_equal 1, self.count_observers(:other_thing)
	end

	def test_count_notifications
		self.add_observer(:one_thing, @observer1)

		assert_equal 0, self.count_notifications(:no_thing)
		assert_equal 0, self.count_notifications(:one_thing)

		self.changed(:one_thing)
		self.notify_observers(:one_thing, :something)

		assert_equal 0, self.count_notifications(:no_thing)
		assert_equal 1, self.count_notifications(:one_thing)

		self.changed(:no_thing)
		self.notify_observers(:no_thing, :something)

		assert_equal 0, self.count_notifications(:no_thing)
	end

	def test_changed
		assert ! self.changed?(:something)
		self.changed(:something)
		assert self.changed?(:something)
	end

	def test_notify_observers
		self.add_observer(:one_thing, @observer1)
		self.add_observer(:one_thing, @observer2)
		self.add_observer(:other_thing, @observer1)
		assert @observer1.check("")
		assert @observer2.check("")

		self.changed(:one_thing)
		self.notify_observers(:one_thing, "test")
		self.wait_notifications
		assert @observer1.check("observer 1: got an update on one_thing with args = test")
		assert @observer2.check("observer 2: got an update on one_thing with args = test")

		self.changed(:other_thing)
		self.notify_observers(:other_thing, "foo", "bar")
		self.wait_notifications
		assert @observer1.check("observer 1: got an update on other_thing with args = foo, bar")
		assert @observer2.check("observer 2: got an update on one_thing with args = test")

		@observer2.delete = true
		self.changed(:one_thing)
		self.notify_observers(:one_thing, "foo", "bar")
		self.wait_notifications
		assert @observer2.check("observer 2: got an update on one_thing with args = foo, bar")
		assert @observer1.check("observer 1: got an update on one_thing with args = foo, bar")

		self.changed(:one_thing)
		self.notify_observers(:one_thing, "fooo", "barr")
		self.wait_notifications
		assert @observer2.check("observer 2: got an update on one_thing with args = foo, bar")
		assert @observer1.check("observer 1: got an update on one_thing with args = fooo, barr")

	end

	def test_pending_notifications?
		self.add_observer(:delayed_thing, @observer3)
		1.upto(3) do
			self.changed(:delayed_thing)
			self.notify_observers(:delayed_thing, "foo bar")
		end
		assert self.pending_notifications?, "should have notifications pending"
		sleep 15
		assert ! self.pending_notifications?, "should not have anything pending"
	end

	def test_wait_notifications
		time = Time.now
		self.add_observer(:delayed_thing, @observer3)
		self.changed(:delayed_thing)
		self.notify_observers(:delayed_thing, "foo bar")
		self.wait_notifications
		dif = Time.now - time
		assert dif >= 10, "should take around 10 seconds"
		assert dif < 12, "should not take so long"
	end

end

class TestQObserver < Test::Unit::TestCase

	def setup
		@qobserver = QObserver.new
	end

	def teardown
		@qobserver = nil
	end

	def test_queues
		assert @qobserver.queues.empty?
		@qobserver.update(:thing1, 123)
		assert_equal 1, @qobserver.queues.length
		@qobserver.update(:thing2, 123)
		assert @qobserver.queues.include?(:thing1)
		assert @qobserver.queues.include?(:thing2)
	end

	def test_received?
		assert ! @qobserver.received?(:thing1)
		@qobserver.update(:thing1, 123)
		assert @qobserver.received?(:thing1)
		extract = @qobserver.received(:thing1)
		assert ! @qobserver.received?(:thing1)
	end

	def test_received
		@qobserver.update(:thing1, 123)
		@qobserver.update(:thing1, 456)
		assert ! @qobserver.received?(:nothing)
		extract = @qobserver.received(:thing1)
		assert_kind_of Array, extract
		assert extract.include?([123])
		assert extract.include?([456])
		assert ! @qobserver.received?(:thing1)

		@qobserver.update(:thing1, 789)
		@qobserver.update(:thing1, 890)
		
		@qobserver.received(:thing1) do |arg|
			assert [[789], [890]].include?(arg)
		end
	end

end
