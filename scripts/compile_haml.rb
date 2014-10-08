Dir["../Past-Year-Papers/**/*.haml"].each do |directory|
  system "haml #{directory} #{directory.gsub('.haml', '')}"
end
