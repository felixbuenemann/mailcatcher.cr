require "sqlite3"
require "json"
require "./mime_parser"
require "./bus"

module MailCatcher
  # Storage module for email messages using SQLite
  module Mail
    extend self

    @@db : DB::Database? = nil
    @@config : Config? = nil

    def setup(config : Config)
      @@config = config
      setup_database
    end

    def db : DB::Database
      @@db ||= begin
        database = DB.open("sqlite3::memory:")
        database.exec("PRAGMA foreign_keys = ON")
        create_tables(database)
        database
      end
    end

    private def create_tables(database : DB::Database)
      database.exec(<<-SQL)
        CREATE TABLE IF NOT EXISTS message (
          id INTEGER PRIMARY KEY ASC,
          sender TEXT,
          recipients TEXT,
          subject TEXT,
          source BLOB,
          size INTEGER,
          type TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      SQL

      database.exec(<<-SQL)
        CREATE TABLE IF NOT EXISTS message_part (
          id INTEGER PRIMARY KEY ASC,
          message_id INTEGER NOT NULL,
          cid TEXT,
          type TEXT,
          is_attachment INTEGER,
          filename TEXT,
          charset TEXT,
          body BLOB,
          size INTEGER,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (message_id) REFERENCES message (id) ON DELETE CASCADE
        )
      SQL
    end

    def setup_database
      db # Ensure database is created
    end

    # Add a new message from SMTP
    def add_message(sender : String?, recipients : Array(String), source : String) : Int64
      # Parse the message
      parser = MimeParser.new(source)
      parsed = parser.parse

      # Insert message
      db.exec(
        "INSERT INTO message (sender, recipients, subject, source, type, size, created_at) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))",
        sender,
        recipients.to_json,
        parsed.subject,
        source,
        parsed.mime_type,
        source.bytesize
      )

      message_id = db.scalar("SELECT last_insert_rowid()").as(Int64)

      # Insert parts (generate CID if none exists for attachment lookup)
      parsed.parts.each_with_index do |part, index|
        cid = part.cid || "part-#{index}"
        add_message_part(
          message_id,
          cid,
          part.mime_type,
          part.is_attachment ? 1 : 0,
          part.filename,
          part.charset,
          part.body,
          part.body.size
        )
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
      is_attachment : Int32,
      filename : String?,
      charset : String?,
      body : Bytes,
      size : Int32
    )
      db.exec(
        "INSERT INTO message_part (message_id, cid, type, is_attachment, filename, charset, body, size, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))",
        message_id,
        cid,
        mime_type,
        is_attachment,
        filename,
        charset,
        body,
        size
      )
    end

    # Get all messages
    def messages : Array(Hash(String, JSON::Any))
      results = [] of Hash(String, JSON::Any)

      db.query("SELECT id, sender, recipients, subject, size, created_at FROM message ORDER BY created_at, id ASC") do |rs|
        rs.each do
          msg = Hash(String, JSON::Any).new
          msg["id"] = JSON::Any.new(rs.read(Int64))
          msg["sender"] = rs.read(String?).try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          recipients_json = rs.read(String?)
          msg["recipients"] = recipients_json.try { |r| JSON.parse(r) } || JSON::Any.new([] of JSON::Any)
          msg["subject"] = rs.read(String?).try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          msg["size"] = JSON::Any.new(rs.read(Int64))
          msg["created_at"] = rs.read(String?).try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          results << msg
        end
      end

      results
    end

    # Get a single message
    def message(id : Int64) : Hash(String, JSON::Any)?
      db.query_one?(
        "SELECT id, sender, recipients, subject, size, type, created_at FROM message WHERE id = ? LIMIT 1",
        id
      ) do |rs|
        msg = Hash(String, JSON::Any).new
        msg["id"] = JSON::Any.new(rs.read(Int64))
        msg["sender"] = rs.read(String?).try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
        recipients_json = rs.read(String?)
        msg["recipients"] = recipients_json.try { |r| JSON.parse(r) } || JSON::Any.new([] of JSON::Any)
        msg["subject"] = rs.read(String?).try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
        msg["size"] = JSON::Any.new(rs.read(Int64))
        msg["type"] = rs.read(String?).try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
        msg["created_at"] = rs.read(String?).try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
        msg
      end
    end

    # Get message source
    def message_source(id : Int64) : String?
      db.query_one?("SELECT source FROM message WHERE id = ? LIMIT 1", id, as: String)
    end

    # Check if message has HTML part
    def message_has_html?(id : Int64) : Bool
      has_html_part = db.query_one?(
        "SELECT 1 FROM message_part WHERE message_id = ? AND is_attachment = 0 AND type IN ('application/xhtml+xml', 'text/html') LIMIT 1",
        id,
        as: Int64
      )
      return true if has_html_part

      # Check if the main message type is HTML
      if msg = message(id)
        msg_type = msg["type"]?.try(&.as_s?)
        return true if msg_type.in?(["text/html", "application/xhtml+xml"])
      end

      false
    end

    # Check if message has plain text part
    def message_has_plain?(id : Int64) : Bool
      has_plain_part = db.query_one?(
        "SELECT 1 FROM message_part WHERE message_id = ? AND is_attachment = 0 AND type = 'text/plain' LIMIT 1",
        id,
        as: Int64
      )
      return true if has_plain_part

      # Check if the main message type is plain
      if msg = message(id)
        msg_type = msg["type"]?.try(&.as_s?)
        return true if msg_type == "text/plain"
      end

      false
    end

    # Get message parts
    def message_parts(id : Int64) : Array(Hash(String, JSON::Any))
      results = [] of Hash(String, JSON::Any)

      db.query("SELECT cid, type, filename, size FROM message_part WHERE message_id = ? ORDER BY filename ASC", id) do |rs|
        rs.each do
          part = Hash(String, JSON::Any).new
          part["cid"] = rs.read(String?).try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          part["type"] = rs.read(String?).try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          part["filename"] = rs.read(String?).try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          part["size"] = JSON::Any.new(rs.read(Int64))
          results << part
        end
      end

      results
    end

    # Get message attachments
    def message_attachments(id : Int64) : Array(Hash(String, JSON::Any))
      results = [] of Hash(String, JSON::Any)

      db.query("SELECT cid, type, filename, size FROM message_part WHERE message_id = ? AND is_attachment = 1 ORDER BY filename ASC", id) do |rs|
        rs.each do
          part = Hash(String, JSON::Any).new
          part["cid"] = rs.read(String?).try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          part["type"] = rs.read(String?).try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          part["filename"] = rs.read(String?).try { |v| JSON::Any.new(v) } || JSON::Any.new(nil)
          part["size"] = JSON::Any.new(rs.read(Int64))
          results << part
        end
      end

      results
    end

    # Message part result
    record MessagePartResult,
      id : Int64,
      message_id : Int64,
      cid : String?,
      type : String?,
      is_attachment : Int64,
      filename : String?,
      charset : String?,
      body : Bytes,
      size : Int64

    # Get a specific part by ID
    def message_part(message_id : Int64, part_id : Int64) : MessagePartResult?
      db.query_one?(
        "SELECT id, message_id, cid, type, is_attachment, filename, charset, body, size FROM message_part WHERE message_id = ? AND id = ? LIMIT 1",
        message_id, part_id
      ) do |rs|
        MessagePartResult.new(
          id: rs.read(Int64),
          message_id: rs.read(Int64),
          cid: rs.read(String?),
          type: rs.read(String?),
          is_attachment: rs.read(Int64),
          filename: rs.read(String?),
          charset: rs.read(String?),
          body: rs.read(Bytes),
          size: rs.read(Int64)
        )
      end
    end

    # Get part by MIME type
    def message_part_type(message_id : Int64, part_type : String) : MessagePartResult?
      db.query_one?(
        "SELECT id, message_id, cid, type, is_attachment, filename, charset, body, size FROM message_part WHERE message_id = ? AND type = ? AND is_attachment = 0 LIMIT 1",
        message_id, part_type
      ) do |rs|
        MessagePartResult.new(
          id: rs.read(Int64),
          message_id: rs.read(Int64),
          cid: rs.read(String?),
          type: rs.read(String?),
          is_attachment: rs.read(Int64),
          filename: rs.read(String?),
          charset: rs.read(String?),
          body: rs.read(Bytes),
          size: rs.read(Int64)
        )
      end
    end

    # Get HTML part
    def message_part_html(message_id : Int64) : MessagePartResult?
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
                return MessagePartResult.new(
                  id: 0_i64,
                  message_id: message_id,
                  cid: nil,
                  type: first_part.mime_type,
                  is_attachment: 0_i64,
                  filename: nil,
                  charset: first_part.charset,
                  body: first_part.body,
                  size: first_part.body.size.to_i64
                )
              end
            end
          end
        end
      end

      part
    end

    # Get plain text part
    def message_part_plain(message_id : Int64) : MessagePartResult?
      message_part_type(message_id, "text/plain")
    end

    # Get part by CID
    def message_part_cid(message_id : Int64, cid : String) : MessagePartResult?
      db.query("SELECT id, message_id, cid, type, is_attachment, filename, charset, body, size FROM message_part WHERE message_id = ?", message_id) do |rs|
        rs.each do
          part = MessagePartResult.new(
            id: rs.read(Int64),
            message_id: rs.read(Int64),
            cid: rs.read(String?),
            type: rs.read(String?),
            is_attachment: rs.read(Int64),
            filename: rs.read(String?),
            charset: rs.read(String?),
            body: rs.read(Bytes),
            size: rs.read(Int64)
          )
          return part if part.cid == cid
        end
      end
      nil
    end

    # Delete all messages
    def delete!
      db.exec("DELETE FROM message")
      spawn { Bus.push_clear }
    end

    # Delete a specific message
    def delete_message!(message_id : Int64)
      db.exec("DELETE FROM message WHERE id = ?", message_id)
      spawn { Bus.push_remove(message_id) }
    end

    # Delete older messages to enforce limit
    def delete_older_messages!(limit : Int32? = nil)
      limit ||= @@config.try(&.messages_limit)
      return if limit.nil?

      # Get IDs of messages to delete
      ids_to_delete = [] of Int64
      db.query("SELECT id FROM message WHERE id NOT IN (SELECT id FROM message ORDER BY created_at DESC LIMIT ?)", limit) do |rs|
        rs.each do
          ids_to_delete << rs.read(Int64)
        end
      end

      ids_to_delete.each do |id|
        delete_message!(id)
      end
    end

    # Get latest created_at timestamp
    def latest_created_at : String?
      db.query_one?("SELECT created_at FROM message ORDER BY created_at DESC LIMIT 1", as: String)
    end
  end
end
