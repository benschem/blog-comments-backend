# frozen_string_literal: true

# Heuristic, dependency-free spam scoring run at submit time. A comment whose
# score crosses SPAM_THRESHOLD is auto-classified `spam` (see Comment's
# before_create), so it is never emailed to the moderator and never published.
#
# Ported from the saint-heaven enquiry scorer and adapted to this schema: there
# is no commenter email or subject here, and `author_website` is a legitimate
# URL field by design — so a URL there is expected, not scored. The signals that
# remain key off author_name, author_role and body (the free-text fields a bot
# actually abuses).
module SpamDetection
  SPAM_THRESHOLD = 1.0

  URL_PATTERN = %r{https?://|www\.|\.com/|\.net/|\.org/|\.ru/|\.top/|\.xyz/}i
  # Link/injection markup — almost never legitimate in a plain-text comment, even from devs
  HTML_LINK_PATTERN = /<\s*a\b[^>]*\bhref\b|<\s*script\b|<\s*iframe\b/i
  # Structural tags a developer might paste while discussing markup — only a weak signal
  HTML_STRUCTURAL_PATTERN = /<\s*(?:div|span|img|a)\b/i
  BBCODE_PATTERN = /\[url=/i
  # Markdown code spans/fences a dev would use to share a snippet
  CODE_FENCE_PATTERN = /```.*?```/m
  INLINE_CODE_PATTERN = /`[^`]*`/
  SHORTENER_PATTERN = %r{bit\.ly|tinyurl\.com|t\.co/|goo\.gl|is\.gd|ow\.ly}i
  TELEGRAM_PATTERN = %r{t\.me/}i
  ZERO_WIDTH_PATTERN = /[\u200B\u200C\u200D\uFEFF]/

  SUSPICIOUS_TLDS = %w[.xyz .top .icu .buzz .monster .pw .tk .ml .ga .cf .gq].freeze

  SPAM_PHRASES = [
    # SEO / marketing
    'seo services', 'search engine optimization', 'rank your website',
    'first page of google', 'boost your ranking', 'increase your traffic',
    'backlinks', 'link building', 'domain authority', 'free seo audit',
    'i visited your site', 'i came across your website', 'i noticed your website',
    'i just visited', 'digital marketing manager', 'organic leads',
    'generate quality leads', 'white-hat', 'ethical strategies',
    'drive traffic', 'competitors are outranking',
    # Pharmaceutical
    'viagra', 'cialis', 'tramadol', 'erectile dysfunction',
    'online pharmacy', 'buy medication', 'male enhancement',
    # Gambling
    'online casino', 'sports betting', 'free spins',
    'start spinning', 'reel cash vault',
    # Financial / crypto
    'bitcoin investment', 'crypto trading', 'forex trading',
    'binary options', 'make money fast', 'guaranteed returns',
    'investment opportunity', 'passive income',
    # Generic
    'opt-out', "congratulations you've won", 'you have been selected',
    'our prices start from', 'impactful video to advertise',
    'toxic backlinks', 'google penalty'
  ].freeze

  def self.included(base)
    base.before_create :detect_spam
  end

  def spam_score # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    # author_website is intentionally excluded from the free-text bucket: it is a
    # URL field, so URL/TLD heuristics there would fire on legitimate comments.
    text_fields = [author_name, author_role, body].map(&:to_s)
    all_text = text_fields.join(' ')
    lower = all_text.downcase
    score = 0.0

    # Strip fenced and inline code so a dev sharing a snippet isn't scored on its markup or
    # URLs. Prose signals (phrases, caps, zero-width, Cyrillic) still run on the full text
    # below, so wrapping spam prose in ``` fences can't hide it from the phrase list.
    decoded_body = body.to_s.gsub(CODE_FENCE_PATTERN, ' ').gsub(INLINE_CODE_PATTERN, ' ')
    markup_text = "#{author_name} #{author_role} #{decoded_body}"

    # A URL in the name is a near-certain tell (the website field exists for that)
    score += 0.8 if author_name.to_s.match?(URL_PATTERN)
    # A URL in the short role/title field is unusual too
    score += 0.6 if author_role.to_s.match?(URL_PATTERN)

    # Link/injection HTML scores hard; structural HTML a dev might paste while discussing
    # markup is only a weak corroborating signal. Mutually exclusive so an <a href> (which
    # also matches the structural <a) doesn't double-count and self-bin.
    if markup_text.match?(HTML_LINK_PATTERN)
      score += 0.8
    elsif markup_text.match?(HTML_STRUCTURAL_PATTERN)
      score += 0.3
    end

    # BBCode [url=…] is a pure forum-spam fingerprint — no dev uses it in a modern comment box
    score += 0.8 if all_text.match?(BBCODE_PATTERN)

    # Telegram links anywhere, including the website field
    score += 0.8 if "#{all_text} #{author_website}".match?(TELEGRAM_PATTERN)

    # URL shorteners in the body or stuffed into the website field
    score += 0.6 if "#{body} #{author_website}".match?(SHORTENER_PATTERN)

    # Excessive URLs in the body (one is plausible, several is link spam)
    url_count = decoded_body.scan(URL_PATTERN).length
    score += 0.3 * [url_count - 1, 0].max

    # Cyrillic runs (this is an English-language blog)
    score += 0.6 if all_text.match?(/\p{Cyrillic}{3,}/)

    # Zero-width / invisible unicode (obfuscation to dodge phrase matching)
    score += 0.8 if all_text.match?(ZERO_WIDTH_PATTERN)

    # Long digit runs in a name (real names don't carry order/phone numbers)
    score += 0.6 if author_name.to_s.match?(/\d{4,}/)

    # Unreasonably long name
    score += 0.5 if author_name.to_s.length > 80

    # Email address stuffed into the name field
    score += 0.5 if author_name.to_s.include?('@')

    # Suspicious TLD on the supplied website
    website_host = author_website.to_s.downcase
    score += 0.3 if SUSPICIOUS_TLDS.any? { |tld| website_host.include?("#{tld}/") || website_host.end_with?(tld) }

    # Spam phrase matching
    SPAM_PHRASES.each { |phrase| score += 0.4 if lower.include?(phrase) }

    # Mostly-uppercase body (shouting ad copy) — code excluded so SQL/constants don't trip it
    if decoded_body.length > 20
      letters = decoded_body.scan(/[A-Za-z]/).length.clamp(1, Float::INFINITY)
      upper_ratio = decoded_body.scan(/[A-Z]/).length.to_f / letters
      score += 0.4 if upper_ratio > 0.6
    end

    score
  end

  private

  def detect_spam
    self.status = 'spam' if spam_score >= SPAM_THRESHOLD
  end
end
