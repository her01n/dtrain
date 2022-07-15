require 'dbus'
require 'stringio'
require 'test/unit'

require './dtrain.rb'

class TestObject < DBus::Object

  def initialize(object_name)
    super(object_name)
  end

  dbus_interface "com.her01n.Test" do

    dbus_method :Hello, "out greeting:s" do
      puts "Hello called"
      return "Hi"
    end
    
    dbus_method :Subtract, "in min:x, in sub:x, out dif:x" do |min, sub|
      puts "Subtract called"
      return min - sub
    end
  end
end

class TestService

  def start
    read, write = IO.pipe
    @service = Process.fork do
      read.close 
      $stdout = write
      bus = DBus.session_bus
      service = bus.request_service("com.her01n.Test")
      exported = TestObject.new("/com/her01n/Test")
      service.export(exported)
      @loop = DBus::Main.new
      @loop << bus
      puts "running"
      @loop.run
    end
    write.close
    read.gets # read "running"
    @log = []
    Thread.new do
      while true
        line = read.gets
        @log << line
      end
    end
  end
  
  def stop
    Process.kill("TERM", @service)
    Process.wait(@service)
  end
  
  def log()
    @log.join("\n")
  end
  
  def reset()
    @log = []
  end
end

class TestDTrain < Test::Unit::TestCase

  # REFACTOR, how can i make $service a class variable?
  
  class << self
  
    def startup
      $service = TestService.new
      $service.start
    end
    
    def shutdown
      $service.stop
    end
  end
  
  def setup
    @original_stdout = $stdout
    $stdout = StringIO.new
    $service.reset
  end

  def teardown
    $stdout = @original_stdout
  end      

  def output
    return $stdout.string 
  end
  
  def service_log
    return $service.log()
  end
  
  def test_help
    dtrain(["--help"])
    assert_include output, "services"
  end
  
  def test_list_services
    dtrain(["--verbose"])
    assert_include output, "com.her01n.Test"
  end
  
  def test_list_activateble_services
    dtrain(["--verbose"])
    # TODO register my own activatable, but not activated service
    assert_include output, "org.freedesktop.ColorHelper"
  end
  
  def test_list_objects
    dtrain(["--verbose", "com.her01n.Test"])
    assert_include output, "/com/her01n/Test"
  end
  
  def test_list_methods
    dtrain(["--verbose", "com.her01n.Test"])
    assert_include output, "  com.her01n.Test.Hello"
  end
  
  def test_call_method
    dtrain(["--verbose", "com.her01n.Test.Hello"])
    assert_include service_log, "Hello called"
  end
  
  def test_print_result
    dtrain(["--verbose", "com.her01n.Test.Hello"])
    assert_include output, "Hi"
  end

  def test_arguments
    dtrain(["--verbose", "com.her01n.Test.Subtract", "7", "3"])
    assert_include service_log, "Subtract called"
    assert_include output, "4"
  end
end

ARGV.each do|a|
  if a == "service" then
    puts "Launching the test service..."
    TestService.new.start
    puts "Service running."
    while true
      sleep 1
    end
    exit
  end
end

