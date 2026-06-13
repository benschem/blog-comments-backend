# frozen_string_literal: true

# A single blog comment.
class Comment < ActiveRecord::Base
  STATUSES = %w[pending approved spam rejected].freeze

  has_secure_token :moderation_token

  validates :post_slug, presence: true, length: { maximum: 200 }
  validates :author_name, presence: true, length: { maximum: 100 }
  validates :author_role, length: { maximum: 100 }
  validates :body, presence: true, length: { maximum: 5000 }
  validates :status, inclusion: { in: STATUSES }
  validates :author_website,
            format: { with: %r{\Ahttps?://}i, message: 'must be an http(s) URL' },
            allow_blank: true

  scope :approved, -> { where(status: 'approved') }
  scope :for_slug, ->(slug) { where(post_slug: slug) }
  scope :pending, -> { where(status: 'pending') }
  scope :still_pending_after, ->(age) { pending.where(created_at: ..age.ago).order(:created_at) }

  def approve!
    update!(status: 'approved')
  end

  def reject!
    update!(status: 'rejected')
  end

  def mark_spam!
    update!(status: 'spam')
  end

  def public_attributes
    {
      author_name: author_name,
      author_website: author_website,
      author_role: author_role,
      body: body,
      created_at: created_at
    }
  end
end
