#!/usr/bin/env ruby

require 'pp'
require 'nokogiri'

# ----------------------------------------------------------------------------
# Common structures
# ----------------------------------------------------------------------------

Post = Struct.new(:title, :link, :pubdate, :content, :comments)
Comment = Struct.new(:id, :author, :date, :content, :parent_id, :user_id)

# ----------------------------------------------------------------------------
# Main script
# ----------------------------------------------------------------------------

if __FILE__ == $0
  posts = {}
  file_cache = "posts.msh"

  if FileTest.exist?(file_cache)
    puts "Using: #{file_cache}"
    posts = Marshal.load(File.read(file_cache))
  else
    puts "Need the cache, sorry."
    exit 1
  end

  just_text = 0
  no_html_links = 0
  html = 0
  tags = Hash.new(0)
  fixed_html = 0

  for id, post in posts
    for comment in post.comments
      if comment.content.index('<')
	html += 1
	tags_found = comment.content.scan(/<\/?(\w+).*?>/).flatten.map(&:downcase).sort.uniq
	tags_found.each { |t| tags[t] += 1 }
	#unless (tags_found & %w[table tr th thead tt]).empty?
	#  p [id, comment.author, comment.id]
	#  p comment.content unless comment.author == "FOFOA"
	#end

	#hp = Hpricot(comment.content, :fixup_tags => true).to_html
	#tags = comment.content.scan(/<(\/?\w+)\s*.*?>/).join(' ')
	#hp = comment.content
	hp = Nokogiri::HTML("<html><body>" + comment.content + "</body></html>").to_html.sub(/\A\s*(<!.*?>)?\s*<html>\s*<body>\s*/m, '').sub(/\s*<\/body>\s*<\/html>\s*\z/m, '')
	hp = hp.sub(/\A\s*<p>\s*(.*)\s*<\/p>\s*\z/m, '\1')
	if hp != comment.content
	  fixed_html += 1
	  puts "file:///home/wejn/x/speakeasy/#{id}.html#comment-#{comment.id}"
	  #File.open(comment.id.to_s + "a", "w") { |f| f.write(comment.content) }
	  #File.open(comment.id.to_s + "b", "w") { |f| f.write(hp) }
	  #system("diff", "-u", comment.id.to_s + "a", comment.id.to_s + "b")
	  #puts
	end
      else
	if comment.content.index(/http/i)
	  no_html_links += 1
	else
	  just_text += 1
	end
      end
    end
  end

  p [:just_text, just_text]
  p [:no_html_links, no_html_links]
  p [:html, html]
  p [:fixed_html, fixed_html]
  pp [:tags, tags.sort_by {|k,v| v}]
end
