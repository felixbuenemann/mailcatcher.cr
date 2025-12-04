require "json"

module MailCatcher
  # Pub/Sub message bus for real-time notifications
  module Bus
    extend self

    # Message types that can be sent through the bus
    alias MessageData = Hash(String, JSON::Any)

    struct AddMessage
      include JSON::Serializable
      property type : String
      property message : MessageData

      def initialize(@message : MessageData = MessageData.new, @type : String = "add")
      end
    end

    struct RemoveMessage
      include JSON::Serializable
      property type : String
      property id : Int64

      def initialize(@id : Int64, @type : String = "remove")
      end
    end

    struct ClearMessage
      include JSON::Serializable
      property type : String

      def initialize(@type : String = "clear")
      end
    end

    struct QuitMessage
      include JSON::Serializable
      property type : String

      def initialize(@type : String = "quit")
      end
    end

    alias Message = AddMessage | RemoveMessage | ClearMessage | QuitMessage

    @@subscribers = [] of Channel(Message)
    @@mutex = Mutex.new

    def subscribe : Channel(Message)
      channel = Channel(Message).new(64)
      @@mutex.synchronize do
        @@subscribers << channel
      end
      channel
    end

    def unsubscribe(channel : Channel(Message)) : Nil
      @@mutex.synchronize do
        @@subscribers.delete(channel)
      end
      channel.close rescue nil
    end

    def push(message : Message) : Nil
      @@mutex.synchronize do
        @@subscribers.each do |sub|
          # Non-blocking send - if channel is full, skip
          select
          when sub.send(message)
            # Sent successfully
          else
            # Channel full or closed, skip
          end
        end
      end
    end

    # Convenience methods
    def push_add(message_data : MessageData) : Nil
      push(AddMessage.new(message: message_data))
    end

    def push_remove(id : Int64) : Nil
      push(RemoveMessage.new(id: id))
    end

    def push_clear : Nil
      push(ClearMessage.new)
    end

    def push_quit : Nil
      push(QuitMessage.new)
    end

    # Convert message to JSON string
    def to_json(message : Message) : String
      case message
      when AddMessage
        message.to_json
      when RemoveMessage
        message.to_json
      when ClearMessage
        message.to_json
      when QuitMessage
        message.to_json
      else
        "{}"
      end
    end
  end
end
