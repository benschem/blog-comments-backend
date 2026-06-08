# frozen_string_literal: true

FactoryBot.define do
  factory :comment do
    post_slug { Faker::Internet.slug(words: 'hello world', glue: '-') }
    author_name { Faker::Name.name }
    body { Faker::Lorem.paragraph }
    # Leave moderation_token unset: has_secure_token populates it on create.

    trait :approved do
      status { 'approved' }
    end

    trait :rejected do
      status { 'rejected' }
    end

    trait :spam do
      status { 'spam' }
    end
  end
end
