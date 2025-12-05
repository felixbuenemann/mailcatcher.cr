require "json"
require "./mime_parser"
require "./bus"

module MailCatcher
  # Storage module for email messages using in-memory data structures
  module Mail
    extend self

    # In-memory data structure for a message
    class Message
      property id : Int64
      property sender : String?
      property recipients : Array(String)
      property subject : String?
      property source : String
      property size : Int64
      property type : String?
      property created_at : Time
      property parts : Array(MessagePart)

      def initialize(
        @id : Int64,
        @sender : String?,
        @recipients : Array(String),
        @subject : String?,
        @source : String,
        @size : Int64,
        @type : String?,
        @created_at : Time
      )
        @parts = [] of MessagePart
      end
    end

    # In-memory data structure for a message part
    class MessagePart
      property id : Int64
      property message_id : Int64
      property cid : String?
      property type : String?
      property is_attachment : Bool
      property filename : String?
      property charset : String?
      property body : Bytes
      property size : Int64
      property created_at : Time

      def initialize(
        @id : Int64,
        @message_id : Int64,
        @cid : String?,
        @type : String?,
        @is_attachment : Bool,
        @filename : String?,
        @charset : String?,
        @body : Bytes,
        @size : Int64,
        @created_at : Time
      )
      end
    end

    @@config : Config? = nil
    @@messages : Array(Message) = [] of Message
    @@mutex : Mutex = Mutex.new
    @@next_message_id : Int64 = 1_i64
    @@next_part_id : Int64 = 1_i64

    def setup(config : Config)
      @@config = config
    end

    # Reset storage (useful for testing)
    def reset!
      @@mutex.synchronize do
        @@messages.clear
        @@next_message_id = 1_i64
        @@next_part_id = 1_i64
      end
    end

    private def current_time : Time
      Time.utc
    end

    private def format_time(time : Time) : String
      time.to_s("%Y-%m-%d %H:%M:%S")
    end

    # Add a new message from SMTP
    def add_message(sender : String?, recipients : Array(String), source : String) : Int64
      # Parse the message
      parser = MimeParser.new(source)
      parsed = parser.parse

      message_id : Int64 = 0_i64

      @@mutex.synchronize do
        message_id = @@next_message_id
        @@next_message_id += 1
        now = current_time

        message = Message.new(
          id: message_id,
          sender: sender,
          recipients: recipients,
          subject: parsed.subject,
          source: source,
          size: source.bytesize.to_i64,
          type: parsed.mime_type,
          created_at: now
        )

        # Insert parts (generate CID if none exists for attachment lookup)
        parsed.parts.each_with_index do |part, index|
          cid = part.cid || "part-#{index}"
          part_id = @@next_part_id
          @@next_part_id += 1

          new_part = MessagePart.new(
            id: part_id,
            message_id: message_id,
            cid: cid,
            type: part.mime_type,
            is_attachment: part.is_attachment,
            filename: part.filename,
            charset: part.charset,
            body: part.body,
            size: part.body.size.to_i64,
            created_at: now
          )
          message.parts << new_part
        end

        @@messages << message
      end

      # Notify subscribers (spawn to not block)
      spawn do
        if msg = message(message_id)
          Bus.push_add(msg)
        end
      end

      message_id
    end

    def add_message_part(
      message_id : Int64,
      cid : String?,
      mime_type : String,
      is_attachment : Bool,
      filename : String?,
      charset : String?,
      body : Bytes,
      size : Int32
    )
      @@mutex.synchronize do
        if message = @@messages.find { |m| m.id == message_id }
          part_id = @@next_part_id
          @@next_part_id += 1

          new_part = MessagePart.new(
            id: part_id,
            message_id: message_id,
            cid: cid,
            type: mime_type,
            is_attachment: is_attachment,
            filename: filename,
            charset: charset,
            body: body,
            size: size.to_i64,
            created_at: current_time
          )
          message.parts << new_part
        end
      end
    end

    # Get all messages
    def messages : Array(Hash(String, JSON::Any))
      results = [] of Hash(String, JSON::Any)

      @@mutex.synchronize do
        # Sort by created_at, then by id (ASC)
        sorted = @@messages.sort_by { |m| {m.created_at, m.id} }

        sorted.each do |msg|
          hash = Hash(String, JSON::Any).new
          hash["id"] = JSON::Any.new(msg.id)
          hash["sender"] = msg.sender.try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          hash["recipients"] = JSON::Any.new(msg.recipients.map { |r| JSON::Any.new(r) })
          hash["subject"] = msg.subject.try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          hash["size"] = JSON::Any.new(msg.size)
          hash["created_at"] = JSON::Any.new(format_time(msg.created_at))
          results << hash
        end
      end

      results
    end

    # Get a single message
    def message(id : Int64) : Hash(String, JSON::Any)?
      @@mutex.synchronize do
        if msg = @@messages.find { |m| m.id == id }
          hash = Hash(String, JSON::Any).new
          hash["id"] = JSON::Any.new(msg.id)
          hash["sender"] = msg.sender.try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          hash["recipients"] = JSON::Any.new(msg.recipients.map { |r| JSON::Any.new(r) })
          hash["subject"] = msg.subject.try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          hash["size"] = JSON::Any.new(msg.size)
          hash["type"] = msg.type.try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          hash["created_at"] = JSON::Any.new(format_time(msg.created_at))
          return hash
        end
      end
      nil
    end

    # Get message source
    def message_source(id : Int64) : String?
      @@mutex.synchronize do
        if msg = @@messages.find { |m| m.id == id }
          return msg.source
        end
      end
      nil
    end

    # Check if message has HTML part
    def message_has_html?(id : Int64) : Bool
      @@mutex.synchronize do
        if msg = @@messages.find { |m| m.id == id }
          # Check parts for HTML
          has_html_part = msg.parts.any? do |part|
            !part.is_attachment && part.type.in?(["application/xhtml+xml", "text/html"])
          end
          return true if has_html_part

          # Check if the main message type is HTML
          return true if msg.type.in?(["text/html", "application/xhtml+xml"])
        end
      end
      false
    end

    # Check if message has plain text part
    def message_has_plain?(id : Int64) : Bool
      @@mutex.synchronize do
        if msg = @@messages.find { |m| m.id == id }
          # Check parts for plain text
          has_plain_part = msg.parts.any? do |part|
            !part.is_attachment && part.type == "text/plain"
          end
          return true if has_plain_part

          # Check if the main message type is plain
          return true if msg.type == "text/plain"
        end
      end
      false
    end

    # Get message parts
    def message_parts(id : Int64) : Array(Hash(String, JSON::Any))
      results = [] of Hash(String, JSON::Any)

      @@mutex.synchronize do
        if msg = @@messages.find { |m| m.id == id }
          # Sort by filename ASC (nil filenames first)
          sorted_parts = msg.parts.sort_by { |p| p.filename || "" }

          sorted_parts.each do |part|
            hash = Hash(String, JSON::Any).new
            hash["cid"] = part.cid.try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
            hash["type"] = part.type.try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
            hash["filename"] = part.filename.try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
            hash["size"] = JSON::Any.new(part.size)
            results << hash
          end
        end
      end

      results
    end

    # Get message attachments
    def message_attachments(id : Int64) : Array(Hash(String, JSON::Any))
      results = [] of Hash(String, JSON::Any)

      @@mutex.synchronize do
        if msg = @@messages.find { |m| m.id == id }
          # Filter attachments and sort by filename ASC
          attachments = msg.parts.select(&.is_attachment)
          sorted_attachments = attachments.sort_by { |p| p.filename || "" }

          sorted_attachments.each do |part|
            hash = Hash(String, JSON::Any).new
            hash["cid"] = part.cid.try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
            hash["type"] = part.type.try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
            hash["filename"] = part.filename.try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
            hash["size"] = JSON::Any.new(part.size)
            results << hash
          end
        end
      end

      results
    end

    # Get a specific part by ID
    def message_part(message_id : Int64, part_id : Int64) : MessagePart?
      @@mutex.synchronize do
        if msg = @@messages.find { |m| m.id == message_id }
          return msg.parts.find { |p| p.id == part_id }
        end
      end
      nil
    end

    # Get part by MIME type
    def message_part_type(message_id : Int64, part_type : String) : MessagePart?
      @@mutex.synchronize do
        if msg = @@messages.find { |m| m.id == message_id }
          return msg.parts.find { |p| p.type == part_type && !p.is_attachment }
        end
      end
      nil
    end

    # Get HTML part
    def message_part_html(message_id : Int64) : MessagePart?
      part = message_part_type(message_id, "text/html")
      part ||= message_part_type(message_id, "application/xhtml+xml")

      # If no HTML part found, check if the main message is HTML
      if part.nil?
        if msg = message(message_id)
          msg_type = msg["type"]?.try(&.as_s?)
          if msg_type.in?(["text/html", "application/xhtml+xml"])
            # Return a synthetic part from the source
            if source = message_source(message_id)
              parser = MimeParser.new(source)
              parsed = parser.parse
              if first_part = parsed.parts.first?
                return MessagePart.new(
                  id: 0_i64,
                  message_id: message_id,
                  cid: nil,
                  type: first_part.mime_type,
                  is_attachment: false,
                  filename: nil,
                  charset: first_part.charset,
                  body: first_part.body,
                  size: first_part.body.size.to_i64,
                  created_at: Time.utc
                )
              end
            end
          end
        end
      end

      part
    end

    # Get plain text part
    def message_part_plain(message_id : Int64) : MessagePart?
      message_part_type(message_id, "text/plain")
    end

    # Get part by CID
    def message_part_cid(message_id : Int64, cid : String) : MessagePart?
      @@mutex.synchronize do
        if msg = @@messages.find { |m| m.id == message_id }
          return msg.parts.find { |p| p.cid == cid }
        end
      end
      nil
    end

    # Delete all messages
    def delete!
      @@mutex.synchronize do
        @@messages.clear
      end
      spawn { Bus.push_clear }
    end

    # Delete a specific message
    def delete_message!(message_id : Int64)
      @@mutex.synchronize do
        @@messages.reject! { |m| m.id == message_id }
      end
      spawn { Bus.push_remove(message_id) }
    end

    # Delete older messages to enforce limit
    def delete_older_messages!(limit : Int32? = nil)
      limit ||= @@config.try(&.messages_limit)
      return if limit.nil?

      ids_to_delete = [] of Int64

      @@mutex.synchronize do
        if @@messages.size > limit
          # Sort by created_at DESC, take all except the newest `limit` messages
          sorted = @@messages.sort_by { |m| {m.created_at, m.id} }.reverse
          to_keep = sorted.first(limit).map(&.id).to_set
          ids_to_delete = @@messages.reject { |m| to_keep.includes?(m.id) }.map(&.id)
        end
      end

      ids_to_delete.each do |id|
        delete_message!(id)
      end
    end

    # Get latest created_at timestamp
    def latest_created_at : String?
      @@mutex.synchronize do
        if msg = @@messages.max_by? { |m| {m.created_at, m.id} }
          return format_time(msg.created_at)
        end
      end
      nil
    end
  end
end
