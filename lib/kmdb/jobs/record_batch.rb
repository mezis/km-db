require 'kmdb'
require 'kmdb/resque'
require 'kmdb/models/event_batch'
require 'kmdb/models/user'
require 'kmdb/models/alias'
require 'kmdb/models/event'
require 'kmdb/models/property'
require 'kmdb/models/global_uid'
require 'kmdb/models/ignored_user'
require 'kmdb/jobs/locked'
require 'kmdb/jobs/unalias_user'

module KMDB
  module Jobs
    class RecordBatch < Locked
      @queue = :high

      def self.perform(id)
        new(id).work
      end

      def initialize(id)
        @batch = EventBatch.find(id)
        raise ArgumentError.new('no such batch') if @batch.nil?
      end

      def work
        tid = GlobalUID.get

        @batch.events.each do |event|
          # reject ignored users 
          next if IgnoredUser.include?(event['_p']) ||
                  IgnoredUser.include?(event['_p2'])

          # store depending on event type
          if event['_p2']
            aliaz = Alias.record event['_p'], event['_p2'], event['_t']
            Resque.enqueue(UnaliasUser, aliaz.name1, aliaz.name2)
          elsif event['_n']
            Event.record(event, tid: tid)
          else
            Property.set(event, tid: tid)
          end
        end

        KMDB.transaction do
          Event.commit(tid)
          Property.commit(tid)
        end

        @batch.delete
      end
    end
  end
end
