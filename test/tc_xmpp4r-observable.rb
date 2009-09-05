$: <<  File.dirname(__FILE__)
$: <<  File.dirname(__FILE__) + "/../lib"
require 'test/unit'
require 'timeout'
require 'xmpp4r-observable'
require 'simple_observer'

class TestJabberObservable < Test::Unit::TestCase
	def setup
		@@connections ||= {}

		if @@connections.include?(:client1)
			@client1 = @@connections[:client1]
			@client2 = @@connections[:client2]
			@client1.subs.accept = true
			@client2.subs.accept = true
			@jid1_raw = @@connections[:jid1_raw]
			@jid2_raw = @@connections[:jid2_raw]
			@jid1 = @jid1_raw.strip.to_s
			@jid2 = @jid2_raw.strip.to_s
			@domain1 = @jid1_raw.domain
			@domain2 = @jid2_raw.domain
			@message_observer = Observer.new("message_observer")
			@subscription_observer = Observer.new("subscription_observer")
			return true
		end

		logins = []
		begin
			logins = File.readlines(File.expand_path("~/.xmpp4r-observable-test-config")).map! { |login| login.split(" ") }
			raise StandardError unless logins.size == 2
		rescue => e
			puts "\nConfiguration Error!\n\nYou must make available two unique Jabber accounts in order for the tests to pass."
			puts "Place them in ~/.xmpp4r-observable-test-config, one per line like so:\n\n"
			puts "user1@example.com/res password"
			puts "user2@example.com/res password\n\n"
			raise e
		end

		@@connections[:client1] = Jabber::Observable.new(*logins[0])
		@@connections[:client2] = Jabber::Observable.new(*logins[1])

		@@connections[:jid1_raw] = Jabber::JID.new(logins[0][0])
		@@connections[:jid2_raw] = Jabber::JID.new(logins[1][0])

		# Force load the client and roster, just to be safe.
		@@connections[:client1].roster
		@@connections[:client2].roster

		# Re-run this method to setup the local instance variables the first time.
		setup
	end

	def test_ensure_the_jabber_clients_are_connected_after_setup
		assert @client1.client.is_connected?
		assert @client2.client.is_connected?
	end

	def test_remove_users_from_our_roster_should_succeed
		@client2.subs.remove(@jid1)
		@client1.subs.remove(@jid2)

		assert_before 60 do
			assert_equal false, @client1.subs.subscribed_to?(@jid2)
			assert_equal false, @client2.subs.subscribed_to?(@jid1)
		end
	end

	def test_add_users_to_our_roster_should_succeed_with_automatic_approval
		@client1.subs.remove(@jid2)
		@client2.subs.remove(@jid1)

		assert_before 10 do
			assert_equal false, @client1.subs.subscribed_to?(@jid2)
			assert_equal false, @client2.subs.subscribed_to?(@jid1)
		end

		@client1.add_observer(:new_subscription, @subscription_observer)
		@subscription_observer.clear
		@client1.subs.add(@jid2)

		assert_before 10 do
			assert @client1.subs.subscribed_to?(@jid2)
		end

		assert_equal 1, @subscription_observer.last_args.size
		assert_equal @jid2, @subscription_observer.last_args[0][0].jid.strip.to_s
		@client1.delete_observer(:new_subscription, @subscription_observer)
		@subscription_observer.clear
	end

	def test_disable_auto_accept_subscription_requests
		@client1.subs.remove(@jid2)
		@client2.subs.remove(@jid1)

		assert_before(60) do
			assert ! @client1.subs.subscribed_to?(@jid2)
			assert ! @client2.subs.subscribed_to?(@jid1)
		end

		@client1.add_observer(:subscription_request, @subscription_observer)
		@client1.subs.accept = false
		@subscription_observer.clear
		assert ! @client1.subs.accept?
		
		assert_before(60) { assert @subscription_observer.last.empty? }

		@client2.subs.add(@jid1)

		assert_before(60) do
			assert ! @subscription_observer.last.empty?
		end

		assert_equal @jid2, @subscription_observer.last_args[0][0].jid.strip.to_s
		assert_equal :subscribe, @subscription_observer.last_args[0][1].type

		@client1.delete_observer(:subscription_request, @subscription_observer)
		@subscription_observer.clear
	end

	def test_automatically_reconnect
		@client1.client.close

		sleep 2
		assert_equal false, @client1.connected?

		@client2.add_observer(:message, @message_observer)

		assert @message_observer.last.empty?
		@client1.deliver(@jid2, "Testing")

		sleep 2
		assert @client1.connected?
		assert @client1.roster.instance_variable_get('@stream').is_connected?
		sleep 2
		assert ! @message_observer.last.empty?
	end

	def test_disconnect_doesnt_allow_auto_reconnects
		@client1.disconnect

		assert_equal false, @client1.connected?
		
		assert_raises Jabber::ConnectionError do
			@client1.deliver(@jid2, "testing")
		end

		@client1.reconnect
	end

	private

	def assert_before(seconds, &block)
		error = nil

		# This is for Ruby 1.9.1 compatibility
		assertion_exception_class = begin
			MiniTest::Assertion
		rescue NameError
			Test::Unit::AssertionFailedError
		end

		begin
			Timeout::timeout(seconds) {
				begin
					yield
				rescue assertion_exception_class => e
					error = e
					sleep 0.5
					retry
				end
			}
		rescue Timeout::Error
			raise error
		end
	end

end
