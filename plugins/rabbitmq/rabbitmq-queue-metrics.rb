#!/usr/bin/env ruby
#
# RabbitMQ Queue Metrics
# ===
#
# Copyright 2011 Sonian, Inc <chefs@sonian.net>
# Copyright 2015 Tim Smith <tim@cozy.co> and Cozy Services Ltd.
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'sensu-plugin/metric/cli'
require 'socket'
require 'carrot-top'

class RabbitMQMetrics < Sensu::Plugin::Metric::CLI::Graphite
  option :host,
         description: 'RabbitMQ management API host',
         long: '--host HOST',
         default: 'localhost'

  option :port,
         description: 'RabbitMQ management API port',
         long: '--port PORT',
         proc: proc(&:to_i),
         default: 15_672

  option :user,
         description: 'RabbitMQ management API user',
         long: '--user USER',
         default: 'guest'

  option :password,
         description: 'RabbitMQ management API password',
         long: '--password PASSWORD',
         default: 'guest'

  option :scheme,
         description: 'Metric naming scheme, text to prepend to $queue_name.$metric',
         long: '--scheme SCHEME',
         default: "#{Socket.gethostname}.rabbitmq"

  option :filter,
         description: 'Regular expression for filtering queues',
         long: '--filter REGEX'

  option :exclude,
         description: 'Regular expression for excluding queues',
         long: '--exclude REGEX'

  option :ssl,
         description: 'Enable SSL for connection to the API',
         long: '--ssl',
         boolean: true,
         default: false

  def acquire_rabbitmq_queues
    begin
      rabbitmq_info = CarrotTop.new(
        host: config[:host],
        port: config[:port],
        user: config[:user],
        password: config[:password],
        ssl: config[:ssl]
      )
    rescue
      warning 'could not get rabbitmq queue info'
    end
    rabbitmq_info.queues
  end

  def run
    timestamp = Time.now.to_i
    acquire_rabbitmq_queues.each do |queue|
      if config[:filter]
        next unless queue['name'].match(config[:filter])
      end

      if config[:exclude]
        next if queue['name'].match(config[:exclude])
      end

      # calculate and output time till the queue is drained in drain metrics
      drain_time_divider = queue['backing_queue_status']['avg_egress_rate']
      if drain_time_divider != 0
        drain_time = queue['messages'] / drain_time_divider
        drain_time = 0 if drain_time.nan? # 0 rate with 0 messages is 0 time to drain
        output([config[:scheme], queue['name'], 'drain_time'].join('.'), drain_time.to_i, timestamp)
      end

      %w(messages).each do |metric|
        output([config[:scheme], queue['name'], metric].join('.'), queue[metric], timestamp)
      end
    end
    ok
  end
end
