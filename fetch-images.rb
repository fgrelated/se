#!/usr/bin/env ruby

# Outdir for the images
IMAGES = File.join(File.dirname($0), 'images')

# User agent to use
AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

# Hosts that won't be fetched from
BLACKLIST_HOST = %w[]

# URLs that won't be fetched (sha1 or direct)
BLACKLIST_URL = %w[]

# Do not consider any 3rd party domains
NO_3P_DOMAINS = ENV['NO_3P_DOMAINS'] || false

# Host whitelist (list of hosts to restrict to, when non-empty. empty = all)
WHITELIST_HOST = NO_3P_DOMAINS ?  %w[
  a5ebcfcbf2c40f0b281230d90d016e002a3a31a0 #f9fw
  a6bbd2a3643af52dc61d8153a61a9a0def0bb5ab #gtfw
  c0d8a5ddc695543da739000c21b9835517f3c7da #fgs
  b9cc3619507297511e54cd4260dc98a8e3952ea2 #fb
  cee7b1b87daed8be93d5bfd99630384d00743475 #f9w
  13232157c18d9235962e61eb0bc9ecff47cd5555 #gtw
] : []

# How long to sleep between requests
SLEEP_BETWEEN_REQUESTS = 0.2

# Should we dryrun (show, don't fetch)
DRYRUN = ENV['DRYRUN'] ? true : false

# Where to store SHA1-hashed URLs that failed (so we avoid them next time)
BURN_DIR = File.join(File.dirname($0), 'burns')

# How many times does the URL have to fail before it's considered burned
MAX_BURNS = 1

require 'pp'
require 'cgi'
require 'set'
require 'fileutils'
require 'mimemagic' # gem install mimemagic
require 'digest/sha1'
require_relative 'static_burns'

# ----------------------------------------------------------------------------
# Common structures
# ----------------------------------------------------------------------------

Post = Struct.new(:title, :link, :pubdate, :content, :comments)
Comment = Struct.new(:id, :author, :date, :content, :parent_id, :user_id)

# ----------------------------------------------------------------------------
# Main script
# ----------------------------------------------------------------------------

def extract_images(content)
  out = Set.new
  content.scan(/<img.*?>/i).each do |c|
    if c =~ /src=(['"])(.*?)\1/
      i = CGI.unescapeHTML($2)
      i.sub!(/\?.*/, '') if i =~ /wordpress.com\/.*\?([wh]=\d+&?)+$/
      out.add(i)
    end
  end

  if content.index('<')
    # at least some html content
    content.gsub(/<.*?>/, '').scan(/(https?:\/\/[^\s]*\.(png|gif|jpe?g))/i) do |i, _|
      out.add(i)
    end
  else
    # no html content
    content.gsub(/<.*?>/, '').scan(/(\s|\A)(https?:\/\/[^\s]*\.(png|gif|jpe?g))(\s|\z)/i) do |_, i, _|
      out.add(i)
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

def burn(url)
  FileUtils.mkdir_p(BURN_DIR)
  File.open(File.join(BURN_DIR, Digest::SHA1.hexdigest(url)), 'a') { |f| f.write('.') }
rescue Object
  nil
end

def burned?(url)
  hd = Digest::SHA1.hexdigest(url)
  return true if STATIC_BURNS.include?(hd)
  n = File.join(BURN_DIR, hd)
  FileTest.size(n) >= MAX_BURNS
rescue Object
  nil
end

def maybe_save_image(jar, url)
  fn = image_file(url)
  h = Digest::SHA1.hexdigest(url)

  if FileTest.file?(fn)
    return :cached # already exists
  end

  # url blacklist
  return :blacklisted if BLACKLIST_URL.include?(url) || BLACKLIST_URL.include?(h)
  # host blacklist
  if url =~ /\/\/(.*?)\//
    host = $1
    hh = Digest::SHA1.hexdigest(host)
    return :blacklisted if BLACKLIST_HOST.include?(host) || BLACKLIST_HOST.include?(hh)
  end

  # host whitelist. when not empty, fetches are restricted to these host(s)
  unless WHITELIST_HOST.empty?
    if url =~ /\/\/(.*?)\//
      host = $1
      hh = Digest::SHA1.hexdigest(host)
      return :blacklisted unless WHITELIST_HOST.include?(host) || WHITELIST_HOST.include?(hh)
    end
  end

  return :burned if burned?(url)

  return :dryrun if DRYRUN

  res = fetch_url(jar, url)
  if res.nil?
    burn(url)
    return "can't fetch image" # errorneous http code
  end

  type = MimeMagic.by_magic(res)
  type = type.nil? ? "unknown" : type.type
  unless type =~ /^image\//
    burn(url)
    return "invalid file type: #{type}"
  end

  begin
    FileUtils.mkdir_p(File.dirname(fn))
    File.open(fn + ".tmp", 'w') { |f| f.write(res) }
    File.rename(fn + ".tmp", fn)
  rescue Object
    STDERR.puts "BUG: can't store #{url.inspect}: #$!"
    burn(url)
    return "can't store image"
  end
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
  images.sort_by { rand }.each_with_index do |image, idx|
    print "#{idx+1}/#{sz} ... \r"
    case res = maybe_save_image(jar, image)
    when :burned
      stats[res] += 1
      STDERR.puts "- #{image} :: burned"
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
