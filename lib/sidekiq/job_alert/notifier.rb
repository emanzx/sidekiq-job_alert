# frozen_string_literal: true

require 'slack-notifier'
require 'telegram/bot'
require 'sidekiq/job_alert/queue'

module Sidekiq
  module JobAlert
    class Notifier
      def initialize(config)
        @notifier_config = YAML.load_file(config)
        @message = ''
      end

      def call
        @message += make_dead_job_message
        @message += make_all_job_message('alert_total_waiting_jobs')
        keys = @notifier_config[:alert_each_waiting_job].keys
        keys.delete(:message)
        keys.each do |key|
          @message += make_job_message('alert_each_waiting_job', key)
        end

        return if @message.empty?

        case @notifier_config[:notifier_mode]
        when "slack"
          @message += @notifier_config[:sidekiq_url]
          slack_notifier.ping(@message)
        when "telegram"
          telegram_notifier
        else
          puts "invalid notifier mode.."
        end
      end

      private

      def make_dead_job_message
        cnt = Sidekiq::JobAlert::Queue.dead_job_cnt
        cnt.positive? ? make_message('alert_dead_jobs', cnt) : ''
      end

      def make_all_job_message(type)
        cnt = Sidekiq::JobAlert::Queue.all_job_cnt
        limit = @notifier_config[type.to_sym][:all][:limit].to_i
        cnt > limit ? make_message(type, cnt) : ''
      end

      def make_job_message(type, queue_name)
        cnt = Sidekiq::JobAlert::Queue.queue_job_cnt(queue_name)
        limit = @notifier_config[type.to_sym][queue_name.to_sym][:limit].to_i
        cnt > limit ? make_message(type, cnt, queue_name.to_s) : ''
      end

      def make_message(type, job_counter, queue_name = nil)
        format(
          @notifier_config[type.to_sym][:message],
          job_counter: job_counter,
          queue_name: queue_name
        )
      end

      def slack_notifier
        Slack::Notifier.new(
          @notifier_config[:webhook_url],
          username: @notifier_config[:username],
          channel: @notifier_config[:channel]
        )
      end
      def telegram_notifier
        Telegram::Bot::Client.run(@notifier_config[:telegram_token]) do |tg_client|
          chat_id = @notifier_config[:telegram_chatid]
          tg_client.api.send_message(chat_id: chat_id, text: @message)
        end
      end
    end
  end
end
