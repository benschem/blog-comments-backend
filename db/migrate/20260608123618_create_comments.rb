# frozen_string_literal: true

class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.string :post_slug, null: false
      t.string :author_name, null: false
      t.string :author_website
      t.string :author_role
      t.text :body, null: false
      t.string :status, null: false, default: 'pending'
      t.string :moderation_token, null: false
      t.string :ip_address
      t.text :user_agent

      t.timestamps
    end

    add_index :comments, %i[post_slug status]
    add_index :comments, :moderation_token, unique: true
  end
end
