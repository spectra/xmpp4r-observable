Gem::Specification.new do |s| 
  s.add_dependency('xmpp4r', '>= 0.5.0')
  s.name = "xmpp4r-observable" 
  s.version = "0.5.1" 
  s.author = "Pablo Lorenzoni" 
  s.email = "pablo@propus.com.br" 
  s.homepage = "http://www.nardol.org/" 
  s.platform = Gem::Platform::RUBY 
  s.summary = "An observable Jabber client library." 
  s.description = <<-EOF
    Jabber::Observable builds on the strong foundation of XMPP4R and use
    a customized version of Ruby's builtin Observer pattern to expose
    XMPP observable things (as messages, pubsub events, presence, etc).
  EOF
  s.files = %w( README COPYING lib/xmpp4r-observable.rb lib/observable_thing.rb lib/thread_store.rb test/simple_observer.rb test/tc_observable_thing.rb test/tc_thread_store.rb	test/tc_xmpp4r-observable.rb ) 
  s.require_path = "lib" 
  s.test_files = %w( test/tc_observable_thing.rb test/tc_thread_store.rb test/tc_xmpp4r-observable.rb )
  s.has_rdoc = true 
  s.extra_rdoc_files = ["README", "COPYING"] 
end 
