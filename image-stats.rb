#!/usr/bin/env ruby

require 'pp'
require 'cgi'
require 'set'

# ----------------------------------------------------------------------------
# Common structures
# ----------------------------------------------------------------------------

Post = Struct.new(:title, :link, :pubdate, :content, :comments)
Comment = Struct.new(:id, :author, :date, :content, :parent_id, :user_id)

# ----------------------------------------------------------------------------
# Main script
# ----------------------------------------------------------------------------

def extract_images(content)
  out = []
  content.scan(/<img.*?>/i).each do |c|
    if c =~ /src=(['"])(.*?)\1/
      i = CGI.unescapeHTML($2)
      i.sub!(/\?.*/, '') if i =~ /wordpress.com\/.*\?([wh]=\d+&?)+$/
      out << i
    end
  end
  out
end

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

  links = Set.new
  uses = Hash.new(0)
  presence = Hash.new { |h,k| h[k] = []; h[k] }

  for id, post in posts
    pi = extract_images(post.content)
    links.merge(pi)
    pi.each { |i| uses[i] += 1; presence[i] << id }
    for comment in post.comments
      ci = extract_images(comment.content)
      ci.each { |i| uses[i] += 1; presence[i] << id }
      links.merge(ci)
    end
  end


  # All images:
  #pp links.sort
  #pp links.size

  # Which ones used more than once? (how many times)
  #pp uses.find_all { |k,v| v > 1}.size

  # Where?
  pp presence.find_all { |k,v| v.size > 1 }
end
