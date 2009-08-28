require 'test/unit'
require '../lib/thread_store'

class TestThreadStore < Test::Unit::TestCase
	def test_initialize
		ts1 = ThreadStore.new
		assert_equal 100, ts1.max

		ts2 = ThreadStore.new(50)
		assert_equal 50, ts2.max
	end

	def test_add_more_than_max
		ts = ThreadStore.new
		1.upto(200) do |n|
			ts.add Thread.new { sleep 10 while true }
		end
		assert ts.size <= ts.max
		ts.add Thread.new { sleep 10 while true }
		assert ts.size <= ts.max
	end

	def test_auto_kill
		ts = ThreadStore.new(10)
		1.upto(10) do |n|
			ts.add Thread.new { sleep 10 }
		end
		assert_equal 10, ts.size
		sleep 15
		assert_equal 0, ts.size
	end

	def test_kill!
		ts = ThreadStore.new(10)
		1.upto(10) do |n|
			ts.add Thread.new { sleep 10 }
		end
		assert_equal 10, ts.size
		ts.kill!
		assert_equal 0, ts.size
	end
end
