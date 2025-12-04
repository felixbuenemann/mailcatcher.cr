require "ecr"

# LibC daemon function for daemonizing
{% unless flag?(:windows) %}
  lib LibC
    fun daemon(nochdir : Int32, noclose : Int32) : Int32
  end
{% end %}

require "./mailcatcher/version"
require "./mailcatcher/config"
require "./mailcatcher/bus"
require "./mailcatcher/mime_parser"
require "./mailcatcher/mail"
require "./mailcatcher/smtp"
require "./mailcatcher/web/server"

module MailCatcher
  extend self

  @@config : Config? = nil
  @@smtp_server : SmtpServer? = nil
  @@running = false

  def config : Config
    @@config.not_nil!
  end

  def run(args : Array(String) = ARGV)
    @@config = Config.parse(args)
    cfg = config

    # Sync output if running in foreground
    unless cfg.daemon
      STDOUT.flush_on_newline = true
      STDERR.flush_on_newline = true
    end

    puts "Starting MailCatcher v#{VERSION}"

    # Setup storage
    Mail.setup(cfg)

    # Setup quit handler
    quit_proc = ->{ quit! }

    # Setup web server
    Web.setup(cfg, quit_proc)

    @@running = true

    # Start SMTP server in a fiber
    spawn(name: "smtp") do
      begin
        @@smtp_server = SmtpServer.new(cfg)
        @@smtp_server.not_nil!.start
      rescue ex
        if @@running
          STDERR.puts "SMTP server error: #{ex.message}"
        end
      end
    end

    # Start HTTP server in a fiber
    spawn(name: "http") do
      begin
        puts "==> #{cfg.http_url}"
        Web.start
      rescue ex
        if @@running
          STDERR.puts "HTTP server error: #{ex.message}"
        end
      end
    end

    # Setup signal handlers
    setup_signal_handlers

    # Open browser if requested
    if cfg.browse
      spawn do
        sleep 0.5.seconds # Give servers time to start
        browse(cfg.http_url)
      end
    end

    # Daemonize if requested (using libc daemon function)
    if cfg.daemon
      spawn do
        sleep 0.1.seconds # Give servers time to start
        if cfg.quittable?
          puts "*** MailCatcher runs as a daemon by default. Go to the web interface to quit."
        else
          puts "*** MailCatcher is now running as a daemon that cannot be quit."
        end
        {% unless flag?(:windows) %}
          LibC.daemon(0, 0)
        {% end %}
      end
    end

    # Keep main fiber alive
    while @@running
      sleep 1.second
    end
  end

  def quit!
    return unless @@running
    @@running = false

    puts "\nShutting down..."

    # Notify clients
    Bus.push_quit

    # Stop servers
    spawn do
      @@smtp_server.try(&.stop)
      Web.stop
      sleep 0.5.seconds
      exit(0)
    end
  end

  private def setup_signal_handlers
    {% unless flag?(:windows) %}
      Signal::INT.trap { quit! }
      Signal::TERM.trap { quit! }
      # QUIT signal for graceful shutdown
      Signal::QUIT.trap { quit! }
    {% end %}
  end

  private def browse(url : String)
    {% if flag?(:darwin) %}
      Process.run("open", [url])
    {% elsif flag?(:windows) %}
      Process.run("cmd", ["/c", "start", "", url])
    {% elsif flag?(:linux) %}
      # Try xdg-open, then fallback to common browsers
      if Process.run("xdg-open", [url]).success?
        return
      elsif Process.run("sensible-browser", [url]).success?
        return
      elsif Process.run("x-www-browser", [url]).success?
        return
      end
    {% end %}
  end
end

# Main entry point
MailCatcher.run
