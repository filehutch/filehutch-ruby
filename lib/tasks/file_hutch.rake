# frozen_string_literal: true

namespace :file_hutch do
  desc "Copy an Active Storage attachment onto a has_hutch column. " \
       "MODEL=User FROM=photo [TO=avatar] [ADOPT_FROM=conn_… to register blobs in place instead of copying]"
  task backfill: :environment do
    model = ENV.fetch("MODEL") { abort "MODEL= is required, e.g. MODEL=User" }.constantize
    from = ENV.fetch("FROM") { abort "FROM= is required: the Active Storage attachment name" }
    to = ENV.fetch("TO", from)

    result = FileHutch::Backfill.new(model: model, from: from, to: to, adopt_from: ENV["ADOPT_FROM"]).call
    puts "#{model.name}##{to}: #{result.done} filled, #{result.skipped} with nothing attached, #{result.failed} failed"
    puts "Run it again to retry the failures; filled rows are skipped." if result.failed.positive?
  end
end
