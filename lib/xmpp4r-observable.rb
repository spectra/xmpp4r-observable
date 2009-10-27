# XMPP4R-Observable - An easy-to-use Jabber Client library with PubSub support
# Copyright (c) 2009 by Pablo Lorenzoni <pablo@propus.com.br>
#
# This is based on XMPP4R-Simple (http://github.com/blaine/xmpp4r-simple) but
# we implement the notification of messages using a modified form of Ruby's
# Observable module instead of a queue.
#
# Jabber::Observable is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.
#
# Jabber::Observable is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# Jabber::Simple; if not, write to the Free Software Foundation, Inc., 51
# Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

require 'time'
require 'rubygems'
require 'xmpp4r'
require 'xmpp4r/roster'
require 'xmpp4r/vcard'
require 'xmpp4r/pubsub'
require 'xmpp4r/pubsub/helper/servicehelper'
require 'xmpp4r/pubsub/helper/nodebrowser'
require 'xmpp4r/pubsub/helper/nodehelper'

# This will provide us our Notifications system
require 'observable_thing'

module Jabber

	class ConnectionError < StandardError; end #:nodoc:

	class NotConnected < StandardError; end #:nodoc:

	class Contact #:nodoc:

		def initialize(client, jid)
			@jid = jid.respond_to?(:resource) ? jid : JID.new(jid)
			@client = client
		end

		def inspect
			sprintf("#<%s:0x%x @jid=%s>", self.class.name, __id__, @jid.to_s)
		end

		def subscribed?
			[:to, :both].include?(subscription)
		end

		def subscription
			roster_item && roster_item.subscription
		end

		def ask_for_authorization!
			subscription_request = Jabber::Presence.new.set_type(:subscribe)
			subscription_request.to = jid
			client.send!(subscription_request)
		end

		def unsubscribe!
			unsubscription_request = Jabber::Presence.new.set_type(:unsubscribe)
			unsubscription_request.to = jid
			client.send!(unsubscription_request)
			client.send!(unsubscription_request.set_type(:unsubscribed))
		end

		def jid(bare=true)
			bare ? @jid.strip : @jid
		end

		private

		def roster_item
			client.roster.items[jid]
		end
	 
		def client
			@client
		end
	end

	# Jabber::Observable - Creates observable Jabber Clients
	class Observable

		# Jabber::Observable::PubSub - Convenience subclass to deal with PubSub
		class PubSub
			class NoService < StandardError; end #:nodoc:

			class AlreadySet < StandardError; end #:nodoc:

			# Creates a new PubSub object
			#
			# observable:: points a Jabber::Observable object
			def initialize(observable)
				@observable = observable

				@helper = @service_jid = nil
				@disco = Jabber::Discovery::Helper.new(@observable.client)
				attach!
			end

			def attach!
				begin
					domain = Jabber::JID.new(@observable.jid).domain
					@service_jid = "pubsub." + domain
					set_service(@service_jid)
				rescue
					@helper = @service_jid = nil
				end
				return has_service?
			end

			def inspect	#:nodoc:
				if has_service?
					sprintf("#<%s:0x%x @service_jid=%s>", self.class.name, __id__, @service_jid)
				else
					sprintf("#<%s:0x%x @has_service?=false>", self.class.name, __id__)
				end
			end

			# Checks if the PubSub service is set
			def has_service?
				! @helper.nil?
			end
	
			# Sets the PubSub service. Just one service is allowed. If nil, reset.
			def set_service(service)
				if service.nil?
					@helper = @service_jid = nil
				else
					raise NotConnected, "You are not connected" if ! @observable.connected?
					raise AlreadySet, "You already have a PubSub service (#{@service_jid})." if has_service?
					@helper = Jabber::PubSub::ServiceHelper.new(@observable.client, service)
					@service_jid = service

					@helper.add_event_callback do |event|
						@observable.changed(:event)
						@observable.notify_observers(:event, event)
					end
				end
			end
	
			# Subscribe to a node.
			def subscribe_to(node)
				raise_noservice if ! has_service?
				@helper.subscribe_to(node) unless is_subscribed_to?(node)
			end
	
			# Unsubscribe from a node.
			def unsubscribe_from(node)
				raise_noservice if ! has_service?
	
				# FIXME
				# @helper.unsubscribe_from(node)
				# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
				# The above should just work, but I had to reimplement it since XMPP4R doesn't support subids
				# and OpenFire (the Jabber Server I am testing against) seems to require it.
	
				subids = find_subids_for(node)
				return if subids.empty?
	
				subids.each do |subid|
					iq = Jabber::Iq.new(:set, @service_jid)
					iq.add(Jabber::PubSub::IqPubSub.new)
					iq.from = @jid
					unsub = REXML::Element.new('unsubscribe')
					unsub.attributes['node'] = node
					unsub.attributes['jid'] = @jid
					unsub.attributes['subid'] = subid
					iq.pubsub.add(unsub)
					res = nil
					@observable.client.send_with_id(iq) do |reply|
						res = reply.kind_of?(Jabber::Iq) and reply.type == :result
					end # @stream.send_with_id(iq)
				end
			end
	
			# Return the subscriptions we have in the configured PubSub service.
			def subscriptions
				raise_noservice if ! has_service?
				@helper.get_subscriptions_from_all_nodes()
			end
	
			# Create a PubSub node (Lots of options still have to be encoded!)
			def create_node(node)
				raise_noservice if ! has_service?
				begin
					@helper.create_node(node)
				rescue => e
					raise e
					return nil
				end
				@my_nodes << node if defined? @my_nodes
				node
			end
	
			# Return an array of nodes I own
			def my_nodes
				if ! defined? @my_nodes
					ret = []
					subscriptions.each do |sub|
						 ret << sub.node if sub.attributes['affiliation'] == 'owner'
					end
					@my_nodes = ret
				end
				return @my_nodes
			end

			# Return true if a given node exists
			def node_exists?(node)
				ret = []
				if ! defined? @existing_nodes or ! @existing_nodes.include?(node)
					# We'll renew @existing_nodes if we haven't got it the first time
					reply = @disco.get_items_for(@service_jid)
					reply.items.each do |item|
						ret << item.node
					end
					@existing_nodes = ret
				end
				return @existing_nodes.include?(node)
			end

			# Returns an array of nodes I am subscribed to
			def subscribed_nodes
				ret = []
				subscriptions.each do |sub|
					next if sub.node.nil?
					ret << sub.node if sub.attributes['subscription'] == 'subscribed' and ! my_nodes.include?(sub.node)
				end
				return ret
			end

			# Return true if we're subscribed to that node
			def is_subscribed_to?(node)
				ret = false
				subscriptions.each do |sub|
					ret = true if sub.node == node and sub.attributes['subscription'] == 'subscribed'
				end
				return ret
			end
	
			# Delete a PubSub node (Lots of options still have to be encoded!)
			def delete_node(node)
				raise_noservice if ! has_service?
				begin
					@helper.delete_node(node)
				rescue => e
					raise e
					return nil
				end
				@my_nodes.delete(node) if defined? @my_nodes
				node
			end
	
			# Publish an Item. This infers an item of Jabber::PubSub::Item kind is passed
			def publish_item(node, item)
				raise_noservice if ! has_service?
				@helper.publish_item_to(node, item)
			end
	
			# Publish Simple Item. This is an item with one element and some text to it.
			def publish_simple_item(node, text)
				raise_noservice if ! has_service?
	
				item = Jabber::PubSub::Item.new
				xml = REXML::Element.new('value')
				xml.text = text
				item.add(xml)
				publish_item(node, item)
			end
	
			# Publish atom Item. This is an item with one atom entry with title, body and time.
			def publish_atom_item(node, title, body, time = Time.now)
				raise_noservice if ! has_service?
	
				item = Jabber::PubSub::Item.new
				entry = REXML::Element.new('entry')
				entry.add_namespace("http://www.w3.org/2005/Atom")
				mytitle = REXML::Element.new('title')
				mytitle.text = title
				entry.add(mytitle)
				mybody = REXML::Element.new('body')
				mybody.text = body
				entry.add(mybody)
				published = REXML::Element.new("published")
				published.text = time.utc.iso8601
				entry.add(published)
				item.add(entry)
				publish_item(node, item)
			end

			# Get items from a node
			def get_items_from(node, count = nil)
				raise_noservice if ! has_service?

				if is_subscribed_to?(node)
					# FIXME
					# @helper.get_items_from(node, count)
					# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
					# The above should just work, but I had to reimplement it since OpenFire (the Jabber Server
					# I am testing against) seems to require subids for nodes we're subscribed to.
					subids = find_subids_for(node)
					iq = Jabber::Iq.new(:get, @service_jid)
					iq.add(Jabber::PubSub::IqPubSub.new)
					iq.from = @observable.jid
					items = Jabber::PubSub::Items.new
					items.node = node
					items.max_items = count
					items.subid = subids[0]
					iq.pubsub.add(items)
					res = nil
					@observable.client.send_with_id(iq) { |reply|
						if reply.kind_of?(Jabber::Iq) and reply.pubsub and reply.pubsub.first_element('items')
							res = {}
							reply.pubsub.first_element('items').each_element('item') do |item|
								res[item.attributes['id']] = item.children.first if item.children.first
							end
						end
						true
					}
					res
				else
					@helper.get_items_from(node, count)
				end
			end
	
			private
	
			def find_subids_for(node) #:nodoc:
				ret = []
				subscriptions.each do |subscription|
					if subscription.node == node
						ret << subscription.subid
					end
				end
				return ret
			end

			def raise_noservice #:nodoc:
				raise NoService, "Have you forgot to call #set_service ?"
			end
		end

		# Jabber::Observable::Subscriptions - convenience class to deal with
		# Presence subscriptions
		#
		# observable:: points to a Jabber::Observable object
		class Subscriptions
			def initialize(observable)
				@observable = observable
			end

			# Ask the users specified by jids for authorization (i.e., ask them to add
			# you to their contact list). If you are already in the user's contact list,
			# add() will not attempt to re-request authorization. In order to force
			# re-authorization, first remove() the user, then re-add them.
			#
			# Example usage:
			# 
			#	 jabber_observable.subs.add("friend@friendosaurus.com")
			#
			# Because the authorization process might take a few seconds, or might
			# never happen depending on when (and if) the user accepts your
			# request, results are notified to observers of :new_subscription
			def add(*jids)
				@observable.contacts(*jids) do |friend|
					next if subscribed_to? friend
					friend.ask_for_authorization!
				end
			end
	
			# Remove the jabber users specified by jids from the contact list.
			def remove(*jids)
				@observable.contacts(*jids) do |unfriend|
					unfriend.unsubscribe!
				end
			end
	
			# Returns true if this Jabber account is subscribed to status updates for
			# the jabber user jid, false otherwise.
			def subscribed_to?(jid)
				@observable.contacts(jid) do |contact|
					return contact.subscribed?
				end
			end

			# Returns true if auto-accept subscriptions (friend requests) is enabled
			# (default), false otherwise.
			def accept?
				@accept = true if @accept.nil?
				@accept
			end
	
			# Change whether or not subscriptions (friend requests) are automatically accepted.
			def accept=(accept_status)
				@accept=accept_status
			end
		end

		include ObservableThing

		attr_reader :subs, :pubsub, :jid, :auto

		# Create a new Jabber::Observable client. You will be automatically connected
		# to the Jabber server and your status message will be set to the string
		# passed in as the status_message argument.
		#
		# jabber = Jabber::Observable.new("me@example.com", "password", "Chat with me - Please!")
		def initialize(jid, password, status = nil, status_message = "Available", host = nil, port=5222)
			# Basic stuff
			@jid = jid
			@password = password
			@host = host
			@port = port
			@disconnected = false

			# Message dealing
			@delivered_messages = 0
			@deferred_messages = Queue.new
			start_deferred_delivery_thread

			# Tell everybody I am here
			status(status, status_message)

			# Subscription Accessor
			@subs = Subscriptions.new(self)

			# PubSub Accessor
			@pubsub = PubSub.new(self)

			# Auto Observer placeholder
			@auto = nil
		end

		def inspect # :nodoc:
			sprintf("#<%s:0x%x @jid=%s, @delivered_messages=%d, @deferred_messages=%d, @observer_count=%s, @notification_count=%s, @pubsub=%s>", self.class.name, __id__, @jid, @delivered_messages, @deferred_messages.length, observer_count.inspect, notification_count.inspect, @pubsub.inspect)
		end

		# Count the registered observers in each thing
		def observer_count
			h = {}
			[ :message, :presence, :iq, :new_subscription, :subscription_request, :event ].each do |thing|
				h[thing] = count_observers(thing)
			end
			h
		end

		# Count the notifications really send for each thing
		def notification_count
			h = {}
			[ :message, :presence, :iq, :new_subscription, :subscription_request, :event ].each do |thing|
				h[thing] = count_notifications(thing)
			end
			h
		end

		# Attach an auto-observer based on QObserver
		def attach_auto_observer
			raise StandardError, "Already attached." if ! @auto.nil?

			@auto = QObserver.new
			[ :message, :presence, :iq, :new_subscription, :subscription_request, :event ].each do |thing|
				self.add_observer(thing, @auto)
			end
		end

		# Dettach the auto-observer
		def dettach_auto_observer
			raise StandardError, "Not attached." if @auto.nil?

			[ :message, :presence, :iq, :new_subscription, :subscription_request, :event ].each do |thing|
				self.delete_observer(thing, @auto)
			end
			@auto = nil
		end

		# Send a message to jabber user jid.
		#
		# Valid message types are:
		# 
		#	 * :normal (default): a normal message.
		#	 * :chat: a one-to-one chat message.
		#	 * :groupchat: a group-chat message.
		#	 * :headline: a "headline" message.
		#	 * :error: an error message.
		#
		# If the recipient is not in your contacts list, the message will be queued
		# for later delivery, and the Contact will be automatically asked for
		# authorization (see Jabber::Observable#add).
		#
		# message should be a string or a valid Jabber::Message object. In either case,
		# the message recipient will be set to jid.
		def deliver(jid, message, type=:chat)
			contacts(jid) do |friend|
				unless @subs.subscribed_to? friend
					@subs.add(friend.jid)
					return deliver_deferred(friend.jid, message, type)
				end
				if message.kind_of?(Jabber::Message)
					msg = message
					msg.to = friend.jid
				else
					msg = Message.new(friend.jid)
					msg.type = type
					msg.body = message
				end
				@delivered_messages += 1
				send!(msg)
			end
		end

		# Set your presence, with a message.
		#
		# Available values for presence are:
		# 
		#	 * nil: online.
		#	 * :chat: free for chat.
		#	 * :away: away from the computer.
		#	 * :dnd: do not disturb.
		#	 * :xa: extended away.
		#
		# It's not possible to set an offline status - to do that, disconnect! :-)
		def status(presence, message)
			@presence = presence
			@status_message = message
			stat_msg = Jabber::Presence.new(@presence, @status_message)
			send!(stat_msg)
		end

		# If contacts is a single contact, returns a Jabber::Contact object
		# representing that user; if contacts is an array, returns an array of
		# Jabber::Contact objects.
		#
		# When called with a block, contacts will yield each Jabber::Contact object
		# in turn. This is mainly used internally, but exposed as an utility
		# function.
		def contacts(*contacts, &block)
			@contacts ||= {}
			contakts = []
			contacts.each do |contact|
				jid = contact.to_s
				unless @contacts[jid]
					@contacts[jid] = contact.respond_to?(:ask_for_authorization!) ? contact : Contact.new(self, contact)
				end
				yield @contacts[jid] if block_given?
				contakts << @contacts[jid]
			end
			contakts.size > 1 ? contakts : contakts.first
		end

		# Returns true if the Jabber client is connected to the Jabber server,
		# false otherwise.
		def connected?
			@client ||= nil
			connected = @client.respond_to?(:is_connected?) && @client.is_connected?
			return connected
		end

		# Direct access to the underlying Roster helper.
		def roster
			return @roster if @roster
			self.roster = Roster::Helper.new(client)
		end

		# Direct access to the underlying Jabber client.
		def client
			connect!() unless connected?
			@client
		end

		# Send a Jabber stanza over-the-wire.
		def send!(msg)
			attempts = 0
			begin
				attempts += 1
				client.send(msg)
			rescue Errno::EPIPE, IOError => e
				sleep 1
				disconnect
				reconnect
				retry unless attempts > 3
				raise e
			rescue Errno::ECONNRESET => e
				sleep (attempts^2) * 60 + 60
				disconnect
				reconnect
				retry unless attempts > 3
				raise e
			end
		end

		# Use this to force the client to reconnect after a force_disconnect.
		def reconnect
			@disconnected = false
			connect!
		end

		# Use this to force the client to disconnect and not automatically
		# reconnect.
		def disconnect
			disconnect!
		end

		# Queue messages for delivery once a user has accepted our authorization
		# request. Works in conjunction with the deferred delivery thread.
		#
		# You can use this method if you want to manually add friends and still
		# have the message queued for later delivery.
		def deliver_deferred(jid, message, type)
			msg = {:to => jid, :message => message, :type => type, :time => Time.now}
			@deferred_messages.enq msg
		end

		# Sets the maximum time to wait for a message to be delivered (in
		# seconds). It will be removed of the queue afterwards.

		def deferred_max_wait=(seconds)
			@deferred_max_wait = seconds
		end

		# Get the maximum time to wait for a message to be delivered. Default: 600
		# seconds (10 minutes).
		def deferred_max_wait
			@deferred_max_wait || 600
		end

		private 

		def client=(client)
			self.roster = nil # ensure we clear the roster, since that's now associated with a different client.
			@client = client
		end

		def roster=(new_roster)
			@roster = new_roster
		end

		def connect!
			raise ConnectionError, "Connections are disabled - use Jabber::Observable::force_connect() to reconnect." if @disconnected
			# Pre-connect
			@connect_mutex ||= Mutex.new

			# don't try to connect if another thread is already connecting.
			return if @connect_mutex.locked?

			@connect_mutex.lock
			disconnect!(false) if connected?

			# Connect
			jid = JID.new(@jid)
			my_client = Client.new(@jid)
			my_client.connect(@host, @port)
			my_client.auth(@password)
			self.client = my_client

			# Post-connect
			register_default_callbacks
			status(@presence, @status_message)
			if ! @pubsub.nil?
				@pubsub.attach!
			else
				@pubsub = PubSub.new(self)
			end

			@connect_mutex.unlock
		end

		def disconnect!(auto_reconnect = true)
			if client.respond_to?(:is_connected?) && client.is_connected?
				begin
					client.close
				rescue Errno::EPIPE, IOError => e
					# probably should log this.
					nil
				end
			end
			client = nil
			@pubsub.set_service(nil)
			@disconnected = auto_reconnect
		end

		def register_default_callbacks
			client.add_message_callback do |message|
				unless message.body.nil?
					changed(:message)
					notify_observers(:message, message)
				end
			end

			roster.add_subscription_callback do |roster_item, presence|
				if presence.type == :subscribed
					changed(:new_subscription)
					notify_observers(:new_subscription, [roster_item, presence])
				end
			end

			roster.add_subscription_request_callback do |roster_item, presence|
				roster.accept_subscription(presence.from) if @subs.accept?
				changed(:subscription_request)
				notify_observers(:subscription_request, [roster_item, presence])
			end

			client.add_iq_callback do |iq|
				changed(:iq)
				notify_observers(:iq, iq)
			end

			roster.add_presence_callback do |roster_item, old_presence, new_presence|
				simple_jid = roster_item.jid.strip.to_s
				presence = case new_presence.type
									 when nil then new_presence.show || :online
									 when :unavailable then :unavailable
									 else
										 nil
									 end

				changed(:presence)
				notify_observers(:presence, simple_jid, presence, new_presence)
			end
		end

		# This thread facilitates the delivery of messages to users who haven't yet
		# accepted an invitation from us. When we attempt to deliver a message, if
		# the user hasn't subscribed, we place the message in a queue for later
		# delivery. Once a user has accepted our authorization request, we deliver
		# any messages that have been queued up in the meantime.
		def start_deferred_delivery_thread
			@deferred_delivery_thread = Thread.new {
				loop {
					sleep 3 while @deferred_messages.empty?
					sleep 3
					message = @deferred_messages.deq
					if @subs.subscribed_to?(message[:to])
						deliver(message[:to], message[:message], message[:type])
					else
						@deferred_messages.enq message unless Time.now > (deferred_max_wait + message[:time])
					end
				}
			}
		end

	end
end

true
