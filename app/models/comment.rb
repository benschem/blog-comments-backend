# frozen_string_literal: true

# A single blog comment. Nothing is public until moderated: rows are created
# `pending` (DB default) and only surface once `approve!`d. The unguessable
# `moderation_token` is the capability that gates the approve/reject links.
class Comment < ActiveRecord::Base
  STATUSES = %w[pending approved spam rejected].freeze

  # Populates `moderation_token` with a unique value on create.
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

  # Build-hook firing is deliberately kept OUT of callbacks: a raising
  # `after_update` would roll back the status change. Callers fire the hook.
  def approve!
    update!(status: 'approved')
  end

  def reject!
    update!(status: 'rejected')
  end

  # Explicit allow-list of fields safe to serve publicly — never the token,
  # ip_address, user_agent, or status.
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
