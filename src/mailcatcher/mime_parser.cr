require "base64"

module MailCatcher
  # MIME part representation
  class MimePart
    property cid : String?
    property mime_type : String
    property charset : String?
    property filename : String?
    property is_attachment : Bool
    property body : Bytes

    def initialize(
      @mime_type : String = "text/plain",
      @body : Bytes = Bytes.empty,
      @cid : String? = nil,
      @charset : String? = nil,
      @filename : String? = nil,
      @is_attachment : Bool = false
    )
    end

    def body_string : String
      String.new(body)
    end

    def size : Int32
      body.size
    end
  end

  # Parsed email message
  class ParsedMessage
    property subject : String?
    property mime_type : String
    property parts : Array(MimePart)
    property headers : Hash(String, String)

    def initialize(
      @mime_type : String = "text/plain",
      @subject : String? = nil,
      @parts : Array(MimePart) = [] of MimePart,
      @headers : Hash(String, String) = {} of String => String
    )
    end
  end

  # RFC822/MIME email parser
  class MimeParser
    @source : String
    @headers : Hash(String, String)
    @body : String

    def initialize(@source : String)
      @headers = {} of String => String
      @body = ""
      parse_headers_and_body
    end

    def parse : ParsedMessage
      subject = decode_header(@headers["subject"]?)
      content_type = @headers["content-type"]? || "text/plain"
      mime_type = extract_mime_type(content_type)

      message = ParsedMessage.new(
        mime_type: mime_type,
        subject: subject,
        headers: @headers
      )

      if multipart?(content_type)
        boundary = extract_boundary(content_type)
        if boundary
          message.parts = parse_multipart(@body, boundary)
        end
      else
        # Single part message - treat the body as a single part
        encoding = @headers["content-transfer-encoding"]?
        charset = extract_charset(content_type)
        body_bytes = decode_body(@body, encoding)

        part = MimePart.new(
          mime_type: mime_type,
          body: body_bytes,
          charset: charset
        )
        message.parts << part
      end

      # If no parts were extracted, create one from the body
      if message.parts.empty?
        message.parts << MimePart.new(
          mime_type: mime_type,
          body: @body.to_slice
        )
      end

      message
    end

    private def parse_headers_and_body
      lines = @source.split(/\r?\n/)
      header_lines = [] of String
      body_start = 0

      # Find the blank line separating headers from body
      lines.each_with_index do |line, i|
        if line.empty?
          body_start = i + 1
          break
        end

        # Handle header continuation (line starting with whitespace)
        if line.starts_with?(" ") || line.starts_with?("\t")
          if header_lines.size > 0
            header_lines[-1] += " " + line.strip
          end
        else
          header_lines << line
        end
        body_start = i + 1
      end

      # Parse headers
      header_lines.each do |line|
        if match = line.match(/^([^:]+):\s*(.*)$/i)
          key = match[1].downcase
          value = match[2]
          @headers[key] = value
        end
      end

      # Extract body
      @body = lines[body_start..].join("\r\n")
    end

    private def multipart?(content_type : String) : Bool
      content_type.downcase.starts_with?("multipart/")
    end

    private def extract_boundary(content_type : String) : String?
      if match = content_type.match(/boundary\s*=\s*"?([^";]+)"?/i)
        match[1]
      else
        nil
      end
    end

    private def extract_mime_type(content_type : String) : String
      content_type.split(";").first.strip.downcase
    end

    private def extract_charset(content_type : String) : String?
      if match = content_type.match(/charset\s*=\s*"?([^";]+)"?/i)
        match[1].strip
      else
        nil
      end
    end

    private def extract_filename(content_type : String?, content_disposition : String?) : String?
      # Try Content-Disposition first
      if content_disposition
        if match = content_disposition.match(/filename\s*=\s*"?([^";]+)"?/i)
          return decode_header(match[1])
        end
      end

      # Fall back to Content-Type name parameter
      if content_type
        if match = content_type.match(/name\s*=\s*"?([^";]+)"?/i)
          return decode_header(match[1])
        end
      end

      nil
    end

    private def is_attachment?(content_disposition : String?) : Bool
      return false unless content_disposition
      content_disposition.downcase.starts_with?("attachment")
    end

    private def extract_cid(content_id : String?) : String?
      return nil unless content_id
      # Remove angle brackets if present
      content_id.gsub(/^<|>$/, "")
    end

    private def parse_multipart(body : String, boundary : String) : Array(MimePart)
      parts = [] of MimePart
      delimiter = "--#{boundary}"
      end_delimiter = "--#{boundary}--"

      # Split by boundary
      sections = body.split(delimiter)

      # Skip the first section (preamble before the first boundary)
      sections = sections[1..] if sections.size > 1

      sections.each do |section|
        # Skip preamble and epilogue
        next if section.strip.empty?
        next if section.strip == "--" # End marker

        # Remove leading -- from end marker check
        section = section.chomp("--").rstrip

        # Parse this part
        part = parse_part(section)
        if part
          # Check if this part is itself multipart
          part_content_type = get_part_header(section, "content-type")
          if part_content_type && multipart?(part_content_type)
            sub_boundary = extract_boundary(part_content_type)
            if sub_boundary
              sub_body = get_part_body(section)
              sub_parts = parse_multipart(sub_body, sub_boundary)
              parts.concat(sub_parts)
            end
          else
            parts << part
          end
        end
      end

      parts
    end

    private def parse_part(section : String) : MimePart?
      return nil if section.strip.empty?

      # Split headers and body
      lines = section.split(/\r?\n/)

      # Skip any leading empty lines
      start_idx = 0
      lines.each_with_index do |line, i|
        if !line.empty?
          start_idx = i
          break
        end
      end
      lines = lines[start_idx..]

      headers = {} of String => String
      body_start = 0

      # Parse headers
      current_header = ""
      lines.each_with_index do |line, i|
        if line.empty?
          body_start = i + 1
          break
        end

        if line.starts_with?(" ") || line.starts_with?("\t")
          current_header += " " + line.strip
        else
          # Save previous header
          if !current_header.empty?
            if match = current_header.match(/^([^:]+):\s*(.*)$/i)
              headers[match[1].downcase] = match[2]
            end
          end
          current_header = line
        end
        body_start = i + 1
      end

      # Save last header
      if !current_header.empty?
        if match = current_header.match(/^([^:]+):\s*(.*)$/i)
          headers[match[1].downcase] = match[2]
        end
      end

      # Get body
      body_text = lines[body_start..].join("\r\n")

      content_type = headers["content-type"]? || "text/plain"
      content_disposition = headers["content-disposition"]?
      content_transfer_encoding = headers["content-transfer-encoding"]?
      content_id = headers["content-id"]?

      mime_type = extract_mime_type(content_type)
      charset = extract_charset(content_type)
      filename = extract_filename(content_type, content_disposition)
      is_attachment = is_attachment?(content_disposition) || !filename.nil?
      cid = extract_cid(content_id)

      # Decode body
      body_bytes = decode_body(body_text, content_transfer_encoding)

      MimePart.new(
        mime_type: mime_type,
        body: body_bytes,
        cid: cid,
        charset: charset,
        filename: filename,
        is_attachment: is_attachment
      )
    end

    private def get_part_header(section : String, header_name : String) : String?
      lines = section.split(/\r?\n/)
      lines.each do |line|
        break if line.empty?
        if match = line.match(/^#{Regex.escape(header_name)}:\s*(.*)$/i)
          return match[1]
        end
      end
      nil
    end

    private def get_part_body(section : String) : String
      lines = section.split(/\r?\n/)
      body_start = 0
      lines.each_with_index do |line, i|
        if line.empty?
          body_start = i + 1
          break
        end
      end
      lines[body_start..].join("\r\n")
    end

    private def decode_body(body : String, encoding : String?) : Bytes
      return body.to_slice unless encoding

      case encoding.downcase.strip
      when "base64"
        begin
          Base64.decode(body.gsub(/\s/, ""))
        rescue
          body.to_slice
        end
      when "quoted-printable"
        decode_quoted_printable(body)
      else
        body.to_slice
      end
    end

    private def decode_quoted_printable(text : String) : Bytes
      result = IO::Memory.new

      i = 0
      bytes = text.bytes
      while i < bytes.size
        byte = bytes[i]

        if byte == '='.ord
          # Check for soft line break: =\r\n or =\n or =\r
          if i + 1 < bytes.size
            next_byte = bytes[i + 1]
            if next_byte == '\r'.ord
              # =\r or =\r\n
              i += 2
              if i < bytes.size && bytes[i] == '\n'.ord
                i += 1  # skip \n after \r
              end
              next
            elsif next_byte == '\n'.ord
              # =\n
              i += 2
              next
            end
          end

          # Try to decode hex =XX
          if i + 2 < bytes.size
            hex = String.new(Slice.new(2) { |j| bytes[i + 1 + j] })
            if hex.matches?(/^[0-9A-Fa-f]{2}$/)
              result.write_byte(hex.to_i(16).to_u8)
              i += 3
              next
            end
          end
        end

        result.write_byte(byte)
        i += 1
      end

      result.to_slice
    end

    private def decode_header(value : String?) : String?
      return nil unless value

      # RFC 2047: Remove whitespace between adjacent encoded-words
      # Pattern: =?...?= followed by whitespace followed by =?...?=
      collapsed = value.gsub(/\?=\s+=\?/) { "?==?" }

      # Decode RFC 2047 encoded words: =?charset?encoding?text?=
      collapsed.gsub(/=\?([^?]+)\?([BQbq])\?([^?]*)\?=/) do |match|
        charset = $1
        encoding = $2.upcase
        text = $3

        decoded = case encoding
                  when "B"
                    begin
                      String.new(Base64.decode(text))
                    rescue
                      text
                    end
                  when "Q"
                    # Quoted-printable in header (uses _ for space)
                    String.new(decode_quoted_printable(text.gsub("_", " ")))
                  else
                    text
                  end

        decoded
      end
    end
  end
end
