# frozen_string_literal: true

# A single blog comment.
class Comment < ActiveRecord::Base
  include SpamDetection

  STATUSES = %w[pending approved spam rejected].freeze

  # A pending comment is "stale" once it has gone unmoderated for this long
  STALE_AFTER_HOURS = 24

  # How far back the weekly spam digest looks for auto-flagged spam to recheck
  RECENT_SPAM_DAYS = 7

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
  scope :spam, -> { where(status: 'spam') }
  scope :for_slug, ->(slug) { where(post_slug: slug) }
  scope :pending, -> { where(status: 'pending') }
  scope :stale_pending, -> { pending.where(created_at: ..STALE_AFTER_HOURS.hours.ago).order(:created_at) }
  scope :recent_spam, -> { spam.where(created_at: RECENT_SPAM_DAYS.days.ago..).order(created_at: :desc) }

  def approve!
    update!(status: 'approved')
  end

  def reject!
    update!(status: 'rejected')
  end

  def mark_spam!
    update!(status: 'spam')
  end

  def spam?
    status == 'spam'
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
