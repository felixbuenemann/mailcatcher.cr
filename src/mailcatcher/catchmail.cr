require "option_parser"
require "socket"

module MailCatcher
  module CatchMail
    extend self

    def run(args : Array(String) = ARGV)
      smtp_ip = "127.0.0.1"
      smtp_port = 1025
      from = "#{ENV["USER"]? || "nobody"}@#{System.hostname}"
      recipients = [] of String

      parser = OptionParser.new do |p|
        p.banner = "Usage: catchmail [options] [recipient ...]\n" \
                   "sendmail-like interface to forward mail to MailCatcher."

        p.on("--ip IP", "Set the ip address of the smtp server") { |ip| smtp_ip = ip }
        p.on("--smtp-ip IP", "Set the ip address of the smtp server") { |ip| smtp_ip = ip }
        p.on("--smtp-port PORT", "Set the port of the smtp server") { |port| smtp_port = port.to_i }
        p.on("-f FROM", "Set the sending address") { |f| from = f }

        # Ignored sendmail compatibility options
        p.on("-oi", "Ignored option -oi") { }
        p.on("-t", "Ignored option -t") { }
        p.on("-q", "Ignored option -q") { }
        p.on("-x", "--no-exit", "Ignored option") { }

        p.on("-h", "--help", "Display this help information") do
          puts p
          exit 0
        end

        p.unknown_args do |args|
          recipients = args
        end
      end

      parser.parse(args)

      # Read message from stdin
      message = STDIN.gets_to_end

      # Extract sender from message if not provided via -f
      if from.nil?
        message.each_line do |line|
          break if line.strip.empty? # End of headers
          if line.starts_with?("From:")
            # Extract email from "From: Name <email>" or "From: email"
            if match = line.match(/<([^>]+)>/)
              from = match[1]
            elsif match = line.match(/From:\s*(\S+@\S+)/)
              from = match[1]
            end
            break
          end
        end
      end

      # Extract recipients from message if none provided
      if recipients.empty?
        message.each_line do |line|
          break if line.strip.empty? # End of headers
          if line.starts_with?("To:") || line.starts_with?("Cc:") || line.starts_with?("Bcc:")
            # Extract emails
            line.scan(/<([^>]+)>|[\s,:](\S+@\S+)/).each do |match|
              if email = (match[1]? || match[2]?)
                recipients << email
              end
            end
          end
        end
      end

      # Default recipient if still none
      recipients << "unknown@localhost" if recipients.empty?

      # Send via SMTP
      deliver(smtp_ip, smtp_port, from, recipients, message)
    end

    private def deliver(host : String, port : Int32, from : String, recipients : Array(String), message : String)
      socket = TCPSocket.new(host, port)

      begin
        # Read greeting
        response = socket.gets
        raise "SMTP connection failed: #{response}" unless response.try(&.starts_with?("220"))

        # HELO
        socket.puts "HELO localhost"
        response = socket.gets
        raise "HELO failed: #{response}" unless response.try(&.starts_with?("250"))

        # MAIL FROM
        socket.puts "MAIL FROM:<#{from}>"
        response = socket.gets
        raise "MAIL FROM failed: #{response}" unless response.try(&.starts_with?("250"))

        # RCPT TO for each recipient
        recipients.each do |recipient|
          socket.puts "RCPT TO:<#{recipient}>"
          response = socket.gets
          raise "RCPT TO failed: #{response}" unless response.try(&.starts_with?("250"))
        end

        # DATA
        socket.puts "DATA"
        response = socket.gets
        raise "DATA failed: #{response}" unless response.try(&.starts_with?("354"))

        # Send message body (escape leading dots)
        message.each_line do |line|
          if line.starts_with?(".")
            socket.puts ".#{line}"
          else
            socket.puts line
          end
        end

        # End data
        socket.puts "."
        response = socket.gets
        raise "Message rejected: #{response}" unless response.try(&.starts_with?("250"))

        # QUIT
        socket.puts "QUIT"
        socket.gets
      ensure
        socket.close
      end
    end
  end
end
