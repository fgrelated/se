task default: [:rebuild]

task :rebuild do |t|
  sh "ruby parse-speakeasy.rb src/*"
end

task :clean do |t|
  sh "rm *.html"
end
