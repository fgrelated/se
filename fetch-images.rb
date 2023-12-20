#!/usr/bin/env ruby

IMAGES = File.join(File.dirname($0), 'images')
AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36'
BLACKLIST_HOST = %w[c.statcounter.com static.pjmedia.com www.moonofalabama.org]
BLACKLIST_URL = %w[
  https://timedotcom.files.wordpress.com/2017/02/steve-bannon-cover-time.jpg
  https://theconservativetreehouse.files.wordpress.com/2018/11/jeff-sessions-resignation.jpg
  https://theconservativetreehouse.files.wordpress.com/2018/09/trump-tweet-declassification-reversal.jpg
  https://theconservativetreehouse.files.wordpress.com/2018/09/trump-sessions-3.jpg
]
SLEEP_BETWEEN_REQUESTS = 1
DRYRUN = ENV['DRYRUN'] ? true : false

require 'pp'
require 'cgi'
require 'set'
require 'fileutils'
require 'mimemagic' # gem install mimemagic

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

def fetch_url(jar, url)
  out = ""
  IO.popen(['curl', '-A', AGENT, '-f', '-s', '-L', '-b', jar, url], 'r', encoding: 'ascii-8bit') do |io|
    out = io.read
  end
  return nil unless $?.exitstatus.zero?
  out
end

def valid_login?(jar)
  return true if DRYRUN
  a = fetch_url(jar, 'https://goldtrail.files.wordpress.com/2015/11/speakeasy_banner.jpg')
  !(a.nil? || a =~ /403: Access Denied/i || a =~ /Private Site.*login/i)
end

def image_file(url)
  File.join(IMAGES, url.sub(/^https?:\/\//, ''))
end

def maybe_save_image(jar, url)
  fn = image_file(url)
  if FileTest.file?(fn)
    return :cached # already exists
  end

  # url blacklist
  return :blacklisted if BLACKLIST_URL.include?(url)
  # host blacklist
  if url =~ /\/\/(.*?)\//
    return :blacklisted if BLACKLIST_HOST.include?($1)
  end

  return :dryrun if DRYRUN

  res = fetch_url(jar, url)
  if res.nil?
    return "can't fetch image" # errorneous http code
  end

  type = MimeMagic.by_magic(res).type
  unless type =~ /^image\//
    return "invalid file type: #{type}"
  end

  FileUtils.mkdir_p(File.dirname(fn))
  File.open(fn + ".tmp", 'w') { |f| f.write(res) }
  File.rename(fn + ".tmp", fn)
  :fetched
end

if __FILE__ == $0
  jar = ENV['COOKIEJAR'] || File.join(File.dirname($0), 'cookies.txt')
  unless FileTest.readable?(jar)
    STDERR.puts "Need cookie jar as: #{jar} (you can override with COOKIEJAR env var)"
    STDERR.puts <<-'EOM'

How to get it:
1. Login to speakeasy with Firefox
2. Use the 'Export Cookies' addon by Rotem Dan to export the cookies.txt file.

(h/t Spengler)
    EOM
    exit 111
  end
  unless valid_login?(jar)
    STDERR.puts "Can't access goldtrail.files.wordpress.com; is the cookie jar valid?"
    exit 112
  end

  posts = {}
  file_cache = "posts.msh"

  if FileTest.exist?(file_cache)
    puts "Using: #{file_cache}"
    posts = Marshal.load(File.read(file_cache))
  else
    puts "Need the cache, sorry."
    exit 1
  end

  images = Set.new
  for id, post in posts
    images.merge(extract_images(post.content))
    for comment in post.comments
      images.merge(extract_images(comment.content))
    end
  end


  FileUtils.mkdir_p(IMAGES)

  stats = Hash.new(0)

  STDOUT.sync = true
  sz = images.size
  images.each_with_index do |image, idx|
    print "#{idx+1}/#{sz} ... \r"
    case res = maybe_save_image(jar, image)
    when :blacklisted
      stats[res] += 1
      STDERR.puts "- #{image} :: blacklisted"
    when :cached
      stats[res] += 1
    when :fetched
      stats[res] += 1
      sleep SLEEP_BETWEEN_REQUESTS
    when :dryrun
      stats[res] += 1
      STDERR.puts "- #{image} :: dry run"
    else
      stats[:error] += 1
      STDERR.puts "! #{image} :: #{res}"
    end
  end
  puts "All done, my friend."
  puts
  pp stats
end
