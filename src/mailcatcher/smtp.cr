require "socket"
require "./mail"

module MailCatcher
  # SMTP Server implementation
  class SmtpServer
    @server : TCPServer?
    @running : Bool = false
    @config : Config

    def initialize(@config : Config)
    end

    def start
      @running = true
      @server = TCPServer.new(@config.smtp_ip, @config.smtp_port)

      puts "==> #{@config.smtp_url}"

      while @running
        if client = @server.try(&.accept?)
          spawn handle_connection(client)
        end
      end
    rescue ex : Socket::BindError
      STDERR.puts "~~> ERROR: Something's using port #{@config.smtp_port}. Are you already running MailCatcher?"
      raise ex
    end

    def stop
      @running = false
      @server.try(&.close)
    end

    private def handle_connection(client : TCPSocket)
      handler = SmtpConnection.new(client, @config)
      handler.run
    rescue ex
      log_exception("Error handling SMTP connection", ex)
    ensure
      client.close rescue nil
    end

    private def log_exception(message : String, ex : Exception)
      STDERR.puts "*** #{message}"
      STDERR.puts "    Exception: #{ex.message}"
      if bt = ex.backtrace?
        STDERR.puts "    Backtrace:"
        bt.first(10).each { |line| STDERR.puts "       #{line}" }
      end
    end
  end

  # SMTP connection state machine
  private class SmtpConnection
    enum State
      Initial
      Greeted
      MailFrom
      RcptTo
      Data
    end

    @client : TCPSocket
    @config : Config
    @state : State = State::Initial
    @sender : String? = nil
    @recipients : Array(String) = [] of String
    @data_buffer : IO::Memory = IO::Memory.new

    CRLF = "\r\n"
    MAX_MESSAGE_SIZE = 10 * 1024 * 1024 # 10MB

    def initialize(@client : TCPSocket, @config : Config)
    end

    def run
      send_response(220, "MailCatcher SMTP ready")

      while line = @client.gets(chomp: true)
        handle_command(line)
      end
    rescue IO::Error
      # Connection closed - normal during shutdown
    end

    private def handle_command(line : String)
      if @state == State::Data
        handle_data_line(line)
        return
      end

      # Parse command
      parts = line.split(" ", 2)
      command = parts[0].upcase
      args = parts[1]? || ""

      case command
      when "HELO"
        handle_helo(args)
      when "EHLO"
        handle_ehlo(args)
      when "MAIL"
        handle_mail(args)
      when "RCPT"
        handle_rcpt(args)
      when "DATA"
        handle_data_start
      when "RSET"
        handle_reset
      when "NOOP"
        send_response(250, "OK")
      when "QUIT"
        handle_quit
      else
        send_response(500, "Unrecognized command")
      end
    end

    private def handle_helo(domain : String)
      @state = State::Greeted
      send_response(250, "MailCatcher")
    end

    private def handle_ehlo(domain : String)
      @state = State::Greeted
      # Send multi-line response with extensions
      @client.print "250-MailCatcher#{CRLF}"
      @client.print "250-SIZE #{MAX_MESSAGE_SIZE}#{CRLF}"
      @client.print "250 8BITMIME#{CRLF}"
    end

    private def handle_mail(args : String)
      unless @state.greeted? || @state.mail_from? || @state.rcpt_to?
        send_response(503, "EHLO/HELO first")
        return
      end

      # Reset if we're in the middle of a transaction
      if @state.mail_from? || @state.rcpt_to?
        reset_transaction
      end

      # Parse "FROM:<address>" or "FROM: <address>"
      if match = args.match(/^FROM:\s*<([^>]*)>(.*)$/i)
        sender = match[1]
        extra = match[2].strip

        # Strip SIZE parameter (RFC 1870)
        if size_match = extra.match(/SIZE=\d+/i)
          # Just ignore the SIZE parameter
        end

        @sender = sender.empty? ? nil : sender
        @state = State::MailFrom
        send_response(250, "OK")
      else
        send_response(501, "Syntax error in MAIL command")
      end
    end

    private def handle_rcpt(args : String)
      unless @state.mail_from? || @state.rcpt_to?
        send_response(503, "MAIL first")
        return
      end

      # Parse "TO:<address>"
      if match = args.match(/^TO:\s*<([^>]+)>/i)
        recipient = match[1]
        @recipients << recipient
        @state = State::RcptTo
        send_response(250, "OK")
      else
        send_response(501, "Syntax error in RCPT command")
      end
    end

    private def handle_data_start
      unless @state.rcpt_to?
        send_response(503, "RCPT first")
        return
      end

      @state = State::Data
      @data_buffer = IO::Memory.new
      send_response(354, "Start mail input; end with <CRLF>.<CRLF>")
    end

    private def handle_data_line(line : String)
      # Check for end of data marker
      if line == "."
        # Message complete
        receive_message
        return
      end

      # Handle dot-stuffing (RFC 5321 4.5.2)
      actual_line = line.starts_with?("..") ? line[1..] : line

      # Add line to buffer
      @data_buffer << actual_line << CRLF
    end

    private def receive_message
      source = @data_buffer.to_s

      begin
        message_id = Mail.add_message(@sender, @recipients, source)
        Mail.delete_older_messages!

        if @config.verbose
          puts "==> SMTP: Received message from '#{@sender}' (#{source.bytesize} bytes)"
        else
          puts "==> SMTP: Received message from '#{@sender}' (#{source.bytesize} bytes)"
        end

        send_response(250, "OK")
      rescue ex
        STDERR.puts "*** Error receiving message: #{ex.message}"
        send_response(451, "Error processing message")
      end

      reset_transaction
      @state = State::Greeted
    end

    private def handle_reset
      reset_transaction
      @state = State::Greeted if @state != State::Initial
      send_response(250, "OK")
    end

    private def handle_quit
      send_response(221, "Bye")
      @client.close
    end

    private def reset_transaction
      @sender = nil
      @recipients = [] of String
      @data_buffer = IO::Memory.new
    end

    private def send_response(code : Int32, message : String)
      @client.print "#{code} #{message}#{CRLF}"
    end
  end
end
