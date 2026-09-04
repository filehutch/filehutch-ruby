# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :documents, force: true do |t|
    t.string :title
    t.string :report_file_id
    t.string :avatar_file_id
    t.string :legacy_ref
    t.timestamps
  end
end
