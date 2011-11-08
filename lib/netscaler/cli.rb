require 'netscaler/errors'
require 'netscaler/config'
require 'netscaler/executor'
require 'netscaler/server/request'
require 'netscaler/vserver/request'
require 'netscaler/service/request'
require 'netscaler/servicegroup/request'
require 'choosy'

module Netscaler
  class CLI

    def initialize(args)
      @args = args.dup
    end

    def parse!(propagate=nil)
      command.parse!(@args, propagate)
    end

    def execute!
      begin
        command.execute!(@args)
      rescue SystemExit
        raise
      rescue Netscaler::ConfigurationError => e
        print_error(e.message)
        exit 1
      rescue Exception => e
        STDERR.puts e.backtrace
        print_error(e.message)
        exit 1
      end
    end

    protected
    def command
      cmds = [vservers, servers, services, servicegroups]
      @command ||= Choosy::SuperCommand.new :netscaler do
        printer :standard, :color => true, :headers => [:bold, :blue], :max_width => 80

        summary "This is a command line tool for interacting with Netscaler load balancer"
        heading 'Description:'
        para "There are several subcommands to do various things with the load balancer. Try 'netscaler help SUBCOMMAND' for more information about the particular command you want to use."
        para "Note that you can supply a configuration file, which would normally be found under ~/.netscaler-cli.yml. That file describes the relationship between your Netscaler load balancers and the aliases, usernames, and passwords that you supply for them. The file is in the general format:"
        para "  netscaler.host.name.com:
    alias: is_optional
    usernamd: is_required
    password: is_optional_but_querried_if_not_found"

        # COMMANDS
        heading 'Commands:'
        cmds.each do |cmd|
          command cmd
        end
        para
        command :help

        # OPTIONS
        heading 'Global Options:'
        string :netscaler, "The IP Address, hostname, or alias in the config file of the Netscaler load balancer. This is required." do
          depends_on :config
          required

          validate do |arg, options|
            reader = Netscaler::ConfigurationReader.new(options[:config])
            config = reader[arg]
            if config.nil?
              die "the Netscaler address '#{arg}' is not defined in the configuration file"
            else
              options[:netscaler] = config
            end
          end
        end
        yaml :config, "The path to the netscaler configuration file. By default, it is ~/.netscaler-cli.yml" do
          default File.join(ENV['HOME'], '.netscaler-cli.yml')
        end
        
        heading 'Informative:'
        boolean_ :debug, "Print extra debug information"
        boolean_ :json, "Prints out JSON instead of textual data"
        help
        version Choosy::Version.load_from_parent.to_s
      end
    end#command

    def servers
      Choosy::Command.new :server do |s|
        executor Netscaler::Executor.new(Netscaler::Server::Request)
        summary "Enables, disbles, or lists servers in the load balancer"
        heading 'Description:'
        para "This is a tool for enabling and disabling a server in a Netscaler load balancer.  The name of the server is required, as is the address of the Netscaler load balancer."
        para "By default, this command will tell you what the current status of the server is."
        para "If you want to list all of the services, use the --list flag."
          
        heading 'Options:'
        enum :action, [:enable, :disable, :list, :status], "Either [enable, disable, list]. 'list' will ignore additional arguments. Default action is 'status'" do
          default :status
        end
        arguments do
          count 0..1 #:at_least => 0, :at_most => 1
          metaname '[SERVER]'
          validate do |args, options|
            if args.length == 0
              die "no server given to act upon" unless options[:action] == :list
            end
          end
        end
      end
    end

    def vservers
      Choosy::Command.new :vserver do
        executor Netscaler::Executor.new(Netscaler::VServer::Request)
        summary "Enables, disables, binds or unbinds policies, or lists virtual servers."
        heading 'Description:'
        para "This is a tool for acting upon virtual servers (VIPs) in a Netscaler load balancer. The name of the virtual server is required."
        para "By default, this command will tell you what the current status of the server is."
        para "If you want to list all of the virtual servers, use the --list flag."

        heading 'Options:'
        enum :action, [:enable, :disable, :list, :bind, :unbind, :status], "Either [enable, disable, list, bind, unbind, status]. 'bind' and 'unbind' require the additional '--policy' flag. 'list' will ignore additional arguments. Default action is 'status'." do
          default :status
        end
        string :policy, "The name of the policy to bind/unbind." do
          depends_on :action
          default :unset
          validate do |arg, options|
            if [:bind, :unbind].include?(options[:action])
              die "required by the 'bind/unbind' actions" if arg == :unset
            else
              die "only used with bind/unbind" unless arg == :unset
            end
          end
        end
        integer :Priority, "The integer priority of the policy to bind with. Default is 100." do
          depends_on :action, :policy
          default -1
          validate do |arg, options|
            if options[:action] == :bind
              if arg == -1
                options[:Priority] = 100
              end
            elsif arg != -1
              die "only used with the bind action"
            end
          end
        end
        arguments do
          count 0..1 #:at_least => 0, :at_most => 1
          metaname '[SERVER]'
          validate do |args, options|
            if args.length == 0
              die "no virtual server given to act upon" unless options[:action] == :list
            end
          end
        end
      end
    end

    def services
      Choosy::Command.new :service do
        executor Netscaler::Executor.new(Netscaler::Service::Request)
        summary "Enables, disables, binds or unbinds from a virtual server, a given service."
        heading 'Description:'
        para "This is a tool for enabling and disabling services in a Netscaler load balancer.  The name of the service is required, as is the address of the Netscaler load balancer."
        
        heading 'Options:'
        enum :action, [:enable, :disable, :bind, :unbind, :status], "Either [enable, disable, bind, unbind, status] of a service. 'bind' and 'unbind' require the '--vserver' flag. Default is 'status'." do
          default :status
        end
        string :vserver, "The virtual server to bind/unbind this service to/from." do
          depends_on :action
          default :unset
          validate do |arg, options|
            if [:bind, :unbind].include?(options[:action])
              die "requires the -v/--vserver flag" if arg == :unset
            else
              die "only used with bind/unbind" unless arg == :unset
            end
          end
        end
        arguments do
          count 0..1 #:at_least => 0, :at_most => 1
          metaname '[SERVICE]'
          validate do |args, options|
            if args.length == 0
              die "no services given to act on" unless options[:action] == :list
            end
          end
        end
      end
    end

    def servicegroups
      Choosy::Command.new :servicegroup do
        executor Netscaler::Executor.new(Netscaler::ServiceGroup::Request)
        summary "Enables, disables, binds or unbinds from a virtual server, a given service group."
        heading 'Description:'
        para "This is a tool for enabling and disabling service groups in a Netscaler load balancer.  The name of the service group is required, as is the address of the Netscaler load balancer."
        
        heading 'Options:'
        enum :action, [:enable, :disable, :bind, :unbind, :status], "Either [enable, disable, bind, unbind, status] of a service group. 'bind' and 'unbind' require the '--vserver' flag. Default is 'status'." do
          default :status
        end
        string :vserver, "The virtual server to bind/unbind this service to/from." do
          depends_on :action
          default :unset
          validate do |arg, options|
            if [:bind, :unbind].include?(options[:action])
              die "requires the -v/--vserver flag" if arg == :unset
            else
              die "only used with bind/unbind" unless arg == :unset
            end
          end
        end
        string :servername, "The name of the server that an individual service runs on (used when scoping the action to an individual service in a service group)." do
          depends_on :action
        end
        string :port, "The port number that an individual service in bound to (used when scoping the action to an individual service in a service group)." do
          depends_on :action
          end
        end
        string :delay, "The delay (in seconds) to wait before disabled services transition to Out of Service. Default is 0 seconds (immediately)." do
          depends_on :action
          default "0"
        end
        arguments do
          count 0..1 #:at_least => 0, :at_most => 1
          metaname '[SERVICEGROUP]'
          validate do |args, options|
            if args.length == 0
              die "no service group given to act on" unless options[:action] == :list
            end
          end
        end
      end
    end

    private
    def print_error(e)
      STDERR.puts "#{File.basename($0)}: #{e}"
      STDERR.puts "Try '#{File.basename($0)} help' for more information"
      exit 1
    end
  end
end
