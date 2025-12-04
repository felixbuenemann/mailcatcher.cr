require "option_parser"

module MailCatcher
  class Config
    property smtp_ip : String = "127.0.0.1"
    property smtp_port : Int32 = 1025
    property http_ip : String = "127.0.0.1"
    property http_port : Int32 = 1080
    property http_path : String = "/"
    property messages_limit : Int32? = nil
    property verbose : Bool = false
    property daemon : Bool = true
    property browse : Bool = false
    property quit : Bool = true

    def self.parse(args : Array(String) = ARGV) : Config
      config = Config.new

      # Default to foreground on Windows (not applicable to Crystal usually)
      {% if flag?(:windows) %}
        config.daemon = false
      {% end %}

      OptionParser.parse(args) do |parser|
        parser.banner = "Usage: mailcatcher [options]"

        parser.on("--ip IP", "Set the ip address of both servers") do |ip|
          config.smtp_ip = ip
          config.http_ip = ip
        end

        parser.on("--smtp-ip IP", "Set the ip address of the smtp server") do |ip|
          config.smtp_ip = ip
        end

        parser.on("--smtp-port PORT", "Set the port of the smtp server") do |port|
          config.smtp_port = port.to_i
        end

        parser.on("--http-ip IP", "Set the ip address of the http server") do |ip|
          config.http_ip = ip
        end

        parser.on("--http-port PORT", "Set the port of the http server") do |port|
          config.http_port = port.to_i
        end

        parser.on("--messages-limit COUNT", "Only keep up to COUNT most recent messages") do |count|
          config.messages_limit = count.to_i
        end

        parser.on("--http-path PATH", "Add a prefix to all HTTP paths") do |path|
          # Clean the path
          clean_path = "/" + path.gsub(/^\/+|\/+$/, "")
          config.http_path = clean_path == "/" ? "/" : clean_path
        end

        parser.on("--no-quit", "Don't allow quitting the process") do
          config.quit = false
        end

        {% unless flag?(:windows) %}
          parser.on("-f", "--foreground", "Run in the foreground") do
            config.daemon = false
          end
        {% end %}

        parser.on("-b", "--browse", "Open web browser") do
          config.browse = true
        end

        parser.on("-v", "--verbose", "Be more verbose") do
          config.verbose = true
        end

        parser.on("-h", "--help", "Display this help information") do
          puts parser
          exit
        end

        parser.on("--version", "Display the current version") do
          puts "MailCatcher v#{VERSION}"
          exit
        end

        parser.invalid_option do |flag|
          STDERR.puts "ERROR: #{flag} is not a valid option."
          STDERR.puts parser
          exit(1)
        end
      end

      config
    end

    def smtp_url : String
      "smtp://#{smtp_ip}:#{smtp_port}"
    end

    def http_url : String
      base = "http://#{http_ip}:#{http_port}"
      if http_path == "/"
        base
      else
        "#{base}#{http_path}"
      end
    end

    def quittable? : Bool
      quit
    end
  end
end
