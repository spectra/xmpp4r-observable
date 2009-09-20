$: <<  File.dirname(__FILE__) + "/../lib"
require 'test/unit'
require 'thread_store'

class TestThreadStore < Test::Unit::TestCase
	def setup
		@ts = ThreadStore.new
	end

	def teardown
		@ts.kill!
	end

	def test_initialize
		ts1 = ThreadStore.new
		assert_equal 100, ts1.max

		ts2 = ThreadStore.new(50)
		assert_equal 50, ts2.max

		ts3 = ThreadStore.new(0)
		assert_equal 0, ts3.max

		ts4 = ThreadStore.new(-1)
		assert_equal 0, ts4.max
	end

	def test_add_more_than_max
		@ts = ThreadStore.new
		1.upto(200) do |n|
			@ts.add Thread.new { sleep 10 while true }
		end
		assert @ts.size <= @ts.max
		@ts.add Thread.new { sleep 10 while true }
		assert @ts.size <= @ts.max
		@ts.kill!

		@ts = ThreadStore.new(0)
		1.upto(200) do |n|
			@ts.add Thread.new { sleep 10 while true }
		end
		assert 200, @ts.size
	end

	def test_auto_kill
		@ts = ThreadStore.new(10)
		1.upto(10) do |n|
			@ts.add Thread.new { sleep 10 }
		end
		assert_equal 10, @ts.size
		sleep 15
		assert_equal 0, @ts.size
		assert @ts.cycles != 0
	end

	def test_kill!
		@ts = ThreadStore.new(10)
		1.upto(10) do |n|
			@ts.add Thread.new { sleep 10 }
		end
		assert_equal 10, @ts.size
		@ts.kill!
		assert_equal 0, @ts.size
	end

	def test_keep
		@ts = ThreadStore.new(0)
		1.upto(100) do |n|
			@ts.add Thread.new { sleep 10 while true }
		end
		assert_equal 100, @ts.size
		@ts.keep(50)
		assert_equal 50, @ts.size
		assert_raise StandardError do
			@ts.keep
		end
	end

	def test_inspect
		assert_kind_of String, @ts.inspect
		assert /cycles/.match(@ts.inspect)
	end

end
