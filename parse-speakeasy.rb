#!/usr/bin/env ruby

require 'pp'
require 'rexml/document'
require 'cgi'
require 'time'
require 'nokogiri'

# ----------------------------------------------------------------------------
# Common structures
# ----------------------------------------------------------------------------

Post = Struct.new(:title, :link, :pubdate, :content, :comments)
Comment = Struct.new(:id, :author, :date, :content, :parent_id, :user_id)

# ----------------------------------------------------------------------------
# XML dump parsing
# ----------------------------------------------------------------------------

def parse_comment(raw)
  comment = Comment.new
  raw.elements.each do |el|
    comment.id = el.text.to_i if el.name == 'comment_id'
    comment.parent_id = el.text.to_i if el.name == 'comment_parent'
    comment.author = el.text if el.name == 'comment_author'
    comment.date = Time.parse(el.text + ' GMT') if el.name == 'comment_date_gmt'
    comment.content = el.text if el.name == 'comment_content'
    comment.user_id = el.text.to_i if el.name == 'comment_user_id'
  end
  comment
end

def should_keep?(raw)
  is_post = false
  is_published = false
  is_page = false
  raw.elements.each do |el|
    is_post = true if el.name == 'post_type' && el.text == 'post'
    is_page = true if el.name == 'post_type' && el.text == 'page'
    is_published = true if el.name == 'status' && el.text == 'publish'
  end
  (is_post && is_published) || is_page
end

def parse_post(raw)
  post = Post.new
  raw.elements.each do |el|
    post.title = CGI.unescapeHTML(el.text) if el.name == 'title'
    post.link = el.text if el.name == 'link'
    post.pubdate = Time.parse(el.text + ' GMT') if el.name == 'post_date_gmt' && el.text != '0000-00-00 00:00:00'
    post.content = el.text if el.name == 'encoded' && el.namespace == 'http://purl.org/rss/1.0/modules/content/'
    (post.comments ||= []) << parse_comment(el) if el.name == 'comment'
  end
  if post.content.size <= 1 && post.link == 'http://freegoldspeakeasy.com/2015/07/06/minister-no-more/'
    # fix for "reblog" which I'm not going to implement
    post.content = 'https://www.yanisvaroufakis.eu/2015/07/06/minister-no-more/'
  end
  post
end

# ----------------------------------------------------------------------------
# HTML generation
# ----------------------------------------------------------------------------

def page_header(title, h1=nil)
  out = []
  out << '<html>'
  out << '<head>'
  out << '<style>img { display: block; padding: 1em; } #post_content, .comment { max-width: 800px; } .comment { border-bottom: 1px dashed black; }</style>'
  out << "<title>#{CGI.escapeHTML(title)}</title>"
  out << '</head>'
  out << '<body>'
  out << "<h1>#{CGI.escapeHTML(h1 || title)}</h1>"
  out
end

def page_footer
  out = []
  out << '</body>'
  out << '</html>'
  out
end

def linkify(what)
  if what =~ /^https?:\/\/goldtrail.files.wordpress.com\//
    '<a style="display: block" href="' + what + '"><img src="' + what + '" /></a>'
  else
    '<a style="display: block" href="' + what + '">' + what + '</a>'
  end
end

def comment_partial(comment, replace_images=false)
  out = []
  out << "<h3 id=\"comment-#{comment.id}\">##{comment.id} #{CGI.escapeHTML(comment.author)}</h3"
  date = comment.date.strftime("%Y-%m-%d %H:%M:%S GMT")
  if comment.parent_id && comment.parent_id != 0
    out << "<p>#{date}, in response to: <a href=\"#comment-#{comment.parent_id}\">##{comment.parent_id}</a></p>"
  else
    out << "<p>#{date}</p>"
  end
  out << '<div class="comment">'

  comment_data = comment.content

  if comment_data.index('<')
    # fix html soup
    soup = "<html><body>" + comment_data + "</body></html>"
    comment_data = Nokogiri::HTML(soup).to_html.
      sub(/\A\s*(<!.*?>)?\s*<html>\s*<body>\s*(.*)\s*<\/body>\s*<\/html>\s*\z/m, '\2'). # remove soup
      sub(/\A\s*<p>\s*(.*)\s*<\/p>\s*\z/m, '\1') # remove enclosing paragraphs, if needed

    # linkify non-links, but only enclosed by white-space
    comment_data.gsub!(/(\s|\A)(https?:\/\/[^<\s]*)(\s|\z)/) { $1 + linkify($2) + $3 }
  elsif comment_data.index(/http/i)
    # linkify non-links, only if there's no html in the comment
    comment_data.gsub!(/(https?:\/\/[^\s]*)/) { linkify($1) }
  end

  # FIXME: post-process: freegoldspeakeasy.com -> archive, goldtrail.files.* -> media archive

  comment_data = comment_data.split(/\n\n+/m).map { |c| "<p>\n" + c + "\n</p>\n" }.join("\n")
  comment_data.gsub!(/<img(.*?)>/, '[img\1]') if replace_images
  out << comment_data
  out << '</div>'
  out
end

def post_partial(post, replace_images=false)
  out = []
  out << '<div id="post_content">'
  content = post.content

  content.gsub!(/(\s|\A)(https?:\/\/[^<\s]*)(\s|\z)/) { $1 + linkify($2) + $3 }

  # FIXME: post-process: freegoldspeakeasy.com -> archive, goldtrail.files.* -> media archive
  # FIXME [wpvideo SDCd4fRy] links video (but that links file from video.wordpress.com?!)

  if replace_images
    out << content.gsub!(/<img(.*?)>/, '[img\1]')
  else
    out << content
  end
  out << '</div>'
  out
end

def generate_post(file, post)
  out = page_header("#{post.pubdate.strftime("%Y-%m-%d")}: #{post.title}", post.title)

  out << '<ul>'
  out << "<li>Original URL: <a href=\"#{CGI.escapeHTML(post.link.gsub(/https?:/, 'https:'))}\">#{CGI.escapeHTML(post.link.gsub(/https?:/, 'https:'))}</a></li>"
  out << "<li>Published: #{post.pubdate.strftime("%Y-%m-%d")}</li>"
  out << "<li>Comments: <a href=\"#comments\">#{post.comments.size}</a></li>"
  out << '</ul>'

  out << "<h2>Post</h2>"
  out += post_partial(post)

  out << "<a id=\"comments\"><h2>Comments</h2></a>"
  for comment in post.comments.sort_by { |c| c.date }
    out += comment_partial(comment)
  end

  out += page_footer

  File.open(file, 'w') { |f| f.puts(out.join("\n")) }
  file
end

def generate_index(file, posts)
  out = page_header("FOFOA's Freegold Speakeasy Archive")

  year = nil
  posts.sort_by { |k, v| [k.to_i.zero? ? 0 : 1, -1 * v.pubdate.to_i] }.each do |id, post|
    if year.nil? || year != id.to_i
      out << "</ul>" unless year.nil?
      year = id.to_i

      out << "<h2>#{year.zero? ? "Pages" : year}</h2>"
      out << "<ul>"
    end

    out << "<li>#{post.pubdate.strftime("%Y-%m-%d")}: <a href=\"#{CGI.escapeHTML(id)}.html\">#{CGI.escapeHTML(post.title)}</a></li>"

  end
  out << "</ul>" unless year.nil?

  out << "<h2>Indexes</h2>"
  out << "<p>Those are BIG files and can jam your browser. You have been warned.</p>"
  out << "<ul>"
  out << "<li><a href=\"_posts.html\">All posts</a></li>"
  out << "<li><a href=\"_comments.html\">All comments</a></li>"
  out << "</ul>"

  out += page_footer

  File.open(file, 'w') { |f| f.puts(out.join("\n")) }
  file
end

def generate_all_post_file(file, posts)
  out = page_header("All posts :: FOFOA's Freegold Speakeasy Archive", "All posts")

  posts.sort_by { |k, v| [k.to_i.zero? ? 0 : 1, -1 * v.pubdate.to_i] }.each do |id, post|
    out << "<a href=\"#{CGI.escapeHTML(post.link)}\">"
    out << "<h2>#{CGI.escapeHTML(post.title)}</h2>"
    out << "</a>"
    out << "<p>(Published: #{post.pubdate.strftime("%Y-%m-%d")})"

    out += post_partial(post, true)
  end

  out += page_footer

  File.open(file, 'w') { |f| f.puts(out.join("\n")) }
  file
end

def generate_comment_index(file, posts_by_year)
  out = page_header("All comments :: FOFOA's Freegold Speakeasy Archive", "All comments")

  out << "<p>This file was so big it wouldn't load. It's split up to per-year indexes</p>"

  out << "<ul>"
  for year, posts in posts_by_year
    num_posts = posts.size
    num_comments = posts.inject(0) { |m,(id,post)| m+post.comments.size }
    out << "<li><a href=\"_comments_#{year}.html\">#{year}</a>: #{num_comments} comments total on #{num_posts} posts</li>"
  end
  out << "</ul>"

  out += page_footer

  File.open(file, 'w') { |f| f.puts(out.join("\n")) }
  file
end

def generate_comment_page(file, year, posts)
  entity = year.to_i.zero? ? "pages" : "year #{year}"
  out = page_header("All comments for #{entity} :: FOFOA's Freegold Speakeasy Archive", "All comments for #{entity}")

  for id, post in posts
    next if post.comments.size.zero?
    out << "<h2>#{CGI.escapeHTML(post.title)}</h2>"

    for comment in post.comments.sort_by { |c| c.date }
      out += comment_partial(comment, true)
    end
  end

  out += page_footer

  File.open(file, 'w') { |f| f.puts(out.join("\n")) }
  file
end

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
    for f in ARGV
      puts "Parsing: #{f} ..."
      doc = REXML::Document.new(File.read(f))
      chan = doc.root.elements.first
      raise "channel not found in #{f}" unless chan.name == 'channel'
      chan.elements.each do |el|
	next unless el.name == 'item'
	next unless should_keep?(el)
	post = parse_post(el)
	post.comments = [] if post.comments.nil? # FIXME

	post_file_name = post.link.sub(/^https?:\/\/freegoldspeakeasy.com\//, '').tr('/', '-').sub(/-+$/, '')

	if posts[post_file_name]
	  puts "Warning: duplicate postid #{post_file_name}: #{post.link.inspect}, previous: #{posts[post_file_name].link.inspect}"
	end

	posts[post_file_name] = post

	#pp [post_file_name, post.title, post.link, post.content.size, post.comments.size]

	#pp [post.title, post.link] if post.content.size <= 1

	#p post.comments.find_all { |x| x.parent_id && x.parent_id != 0 }.size
	#require 'pp'
	#pp post
      end
    end

    File.open(file_cache, 'w') { |f| f.write(Marshal.dump(posts)) }
    puts "Wrote cache: #{file_cache}"
  end

  puts "Generating posts ..."
  for id, post in posts
    puts "  #{id}: #{post.title}"
    generate_post(id + ".html", post)
  end

  puts "Generating index ..."
  generate_index('index.html', posts)

  puts "Generating per-type files ..."
  generate_all_post_file('_posts.html', posts)

  posts_by_year = Hash.new { |h,k| h[k] = []; h[k] }
  posts.sort_by { |k, v| [k.to_i.zero? ? 0 : 1, -1 * v.pubdate.to_i] }.each do |id, post|
    year = id.to_i
    year = 'pages' if year.zero?
    posts_by_year[year] << [id, post]
  end

  generate_comment_index('_comments.html', posts_by_year)
  for year, year_posts in posts_by_year
    puts "  comments for #{year}"
    generate_comment_page("_comments_#{year}.html", year, year_posts)
  end

  puts "All done."
end
