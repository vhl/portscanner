require 'socket'
require 'json'
require 'slack-notifier'

PORTBOT_WEBHOOK = ENV["PORTBOT_WEBHOOK"]
PORTBOT_TARGET = ENV["PORTBOT_TARGET"]

notifier = Slack::Notifier.new PORTBOT_WEBHOOK

TIMEOUT = 2
thread_count = 48
ports_open = 0

q = Queue.new

# create a list of all port numbers
PORT_LIST = *(1..65535)

# these ports we expect. Remove them from list.
PORT_LIST.delete(80)
PORT_LIST.delete(443)

# shuffle ports so we don't scan in order
PORT_LIST.shuffle!

# populate the queue
PORT_LIST.each do |port|
  q.push(port)
end

# create threads
threads   = thread_count.times.map do |i|
  Thread.new do
    while port = q.pop
      begin
        puts "[#{port}]"
        socket      = Socket.new(:INET, :STREAM)
        remote_addr = Socket.sockaddr_in(port, PORTBOT_TARGET)
        socket.connect_nonblock(remote_addr)
      rescue Errno::EINPROGRESS => e
        # skip
      rescue Errno::ECONNREFUSED => e
        # skip
      rescue SocketError => e
        # skip
      end
      _, sockets, _ = IO.select(nil, [socket], nil, TIMEOUT)
      if sockets
        ports_open += 1
        notifier.ping "<!channel> UNAUTHORIZED PORT OPEN ON MAESTRO: #{port}"
      end
    end
  end
end

q.close
threads.each(&:join)

notifier.ping "<!channel> TOTAL UNAUTHORIZED PORTS OPEN ON MAESTRO: #{ports_open}" if ports_open > 0
