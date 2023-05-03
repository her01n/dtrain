#!/usr/bin/ruby

require "dbus"
require "optparse"

class NullIO

  def puts(message)
  end
end

def help()
  puts "Usage: dtrain [--help][--verbose] [--system] [/object/Name] [service|interface.Method] [arguments ...]"
  puts ""
  puts "Without service - List available services."
  puts "With service - List methods of the service."
  puts "With interface.method - Call a dbus method."
  puts ""
  puts "  --help     Display help"
  puts "  --verbose  Print more information"
  puts ""
  puts "  --system   Use system bus. The default is to use session bus."
end

def all_services(bus, log)
  service = bus["org.freedesktop.DBus"]
  object = service["/org/freedesktop/DBus"]
  iface = object["org.freedesktop.DBus"]
  names = Set.new + iface.ListNames + iface.ListActivatableNames 
end  

def list_services(bus, log)
  names = all_services(bus, log)
  log.puts "Services:"
  names.select do |service|
    not service.start_with? ":"
  end.sort.each do |service|
    puts service
  end
end

def search_objects(prefix, node)
  objects = []
  node.each do |key, value|
    if value == {} then
      objects << (prefix + "/" + key)
    else
      objects = objects + search_objects(prefix + "/" + key, value)
    end
  end
  objects
end

$skip_interfaces = [
  "org.freedesktop.DBus.Introspectable",
  "org.freedesktop.DBus.Peer",
  "org.freedesktop.DBus.Properties",
]

def list_objects_methods(bus, log, name)
  log.puts "Introspect service #{name}"
  service = bus[name]
  service.introspect
  objects = search_objects("", service.root)
  log.puts "Objects and methods of service #{name}:"
  objects.sort.each do |object|
    puts object
    obj = service[object]
    obj.interfaces.sort.each do |iface|
      if $skip_interfaces.include? iface then
        log.puts "  Skip Interface #{iface}"
        next
      end
      log.puts "  Introspect Interface #{iface}"
      obj[iface].methods.keys.sort.each do |name|
        puts "  #{iface}.#{name}"
      end
    end
  end
end

def parse_interface_and_method(name)
  tokens = name.split(".")
  if tokens.length < 2 then raise "name #{name} contains no '.'" end
  interface = tokens[0, tokens.length - 1].join(".")
  method = tokens[tokens.length - 1]
  return interface, method
end

def guess_object_name(interface)
  tokens = interface.split(".")
  object = "/" + tokens.join("/")
end

def guess_service_name(interface)
  tokens = interface.split(".")
  prefix = tokens.take_while do |token| token[0].downcase == token[0] end
  service = (prefix + [tokens[prefix.length]]).join(".")
end

def parse_bool(arg, i)
  if ["true", "t", "1"].include? arg then
    return true
  elsif ["false", "f", "0"].include? arg then
    return false
  else
    raise "Cannot convert argument #{arg} at index #{i} to boolean"
  end
end 

def parse_method_arguments(params, args)
  if params.size == args.size then
    size = params.size
    parsed = []
    (0..size-1).each do |i|
      type = params[i].type
      if type == "b" then
        parsed << parse_bool(args[i], i)
      elsif ["y", "n", "q", "i", "u", "x", "t"].include? type then
        parsed << args[i].to_i
      elsif type == "s" then
        parsed << args[i]
      else
        raise "Unsupported method argument type: #{type} at index #{i}"
      end
    end
    return parsed
  else 
    raise "Wrong number of arguments, expected #{params.size}, got #{args.size}"
  end
  return args
end

def call_method(bus, log, object_name, name, args_strings)
  interface_name, method_name = parse_interface_and_method(name)
  service_name = guess_service_name interface_name
  if not object_name then
    object_name = guess_object_name interface_name
  end
  log.puts "Calling method #{method_name} from interface #{interface_name}"\
      + " of an object #{object_name} and service #{service_name}"
  service_obj = bus[service_name]
  object_obj = service_obj[object_name]
  iface = object_obj[interface_name]
  method_obj = iface.methods[method_name]
  parsed_args = parse_method_arguments(method_obj.params, args_strings)
  result = object_obj.send(method_name, *parsed_args)
  log.puts "Ok"
  if result != nil then
    log.puts "Result:"
    puts result
  end
end

def parse_arguments(args)
  options = {}
  names = OptionParser.new do |opt|
    opt.on("--help") { |o| options[:help] = true }
    opt.on("--verbose") { |o| options[:verbose] = true }
    opt.on("--system") { |o| options[:system] = true }
  end.parse(args)
  options[:names] = names
  options
end

def log(options)
  if options[:verbose] then
    return $stdout
  else
    return NullIO.new
  end
end

# REFACTOR method too long
def dtrain(args)
  options = parse_arguments(args)
  log = log(options)
  log.puts "dtrain version 0.1"
  if options[:help] then
    help()
  else
    names = options[:names]
    if (options[:system])
      log.puts("connect to system bus")
      bus = DBus::SystemBus.instance
    else
      log.puts "connect to session bus"
      bus = DBus::SessionBus.instance
    end
    if names == [] then
      log.puts "no name given, list all services"
      list_services(bus, log)
    elsif names.length == 1 and all_services(bus, log).include? names[0] then
      log.puts "service name given, list objects and methods"
      list_objects_methods(bus, log, names[0])
    elsif names.length >= 2 and names[0].start_with? "/" and names[1].include? "." then
      log.puts "object and interface and method given, calling a method"
      call_method(bus, log, names[0], names[1], names[2, names.length - 1])
    elsif names[0].include? "." then
      log.puts "interface and method given, calling a method"
      call_method(bus, log, false, names[0], names[1, names.length - 1])
    else
      $stderr.puts "Name #{name} is not a service and does not contain '.'."
      $stderr.puts "Specify a service name or a method as interface.Method."
    end
  end
end

if __FILE__ == $0 then dtrain(ARGV) end
