# frozen_string_literal: true

require "open-uri"

class RemoteFetchJob < ApplicationJob
  queue_as :default

  def perform(bookmark_id)
    bookmark = Bookmark.find(bookmark_id)
    if [bookmark.favicon, bookmark.title, bookmark.description, bookmark.lang].all?(&:present?)
      return
    end
    parser = LinkThumbnailer.generate(bookmark.url)
    favicon_url = parser.favicon
    begin
      open(parser.favicon, open_timeout: 8)
    rescue OpenURI::HTTPError, Errno::ENOENT
      url_parser = URI.parse(bookmark.url)
      favicon_url = [url_parser.scheme, "://", url_parser.host, "/favicon.ico"].join
      begin
        result = open(favicon_url, open_timeout: 8)
        favicon_url = nil if /html|text/i.match?(result.content_type)
      rescue OpenURI::HTTPError, Errno::ENOENT
        favicon_url = nil
      end
    end
    bookmark.title = parser.title.presence if bookmark.title.blank?
    bookmark.description = parser.description.presence if bookmark.description.blank?
    bookmark.favicon = favicon_url.presence if bookmark.favicon.blank?
    lang = [bookmark.title, bookmark.description].any? { |text| text.to_s.match?(/\p{Han}/) } ? :chinese : :english
    bookmark.lang = lang if bookmark.lang.blank?
    if bookmark.save
      bookmark.save_favicon if bookmark.favicon.present?
    else
      logger.error "[RemoteFetchJob] Save bookmark failed: #{bookmark.errors.full_messages.to_sentence}"
    end
  rescue LinkThumbnailer::HTTPError
    # TODO
  end
end
