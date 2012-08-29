#!/usr/bin/env ruby
require 'net/http'
require 'rexml/document'
require 'optparse'



CLIENTS_FILE = 'local.clients'
TVDB_URI='www.thetvdb.com'
TVDB_KEY="1D807D9321ED31C5"
EPISODE_LENGTH_MIN=1100.0


def get_xml(cmd)
  	Net::HTTP.get TVDB_URI, cmd
end



def query_series_list(series)
    titles=[]
    doc = REXML::Document.new get_xml("/api/GetSeries.php?seriesname=#{series.split(' ').join('%20')}")
    doc.elements.each('Data/Series') do |ele|
        titles << [ele.elements['SeriesName'].text, ele.elements['seriesid'].text]
    end
    return titles 
end



def get_episodes(series)
    REXML::Document.new(xml_data)
end

def scatter_cmd(clients,cmd)
    print "#{cmd} ..."
	clients.each do |client| 
	    cmd = "ssh #{client} -f -- #{cmd}"
	    system cmd
	end
    print "done\n"
end


def hand_brake(params={})
  o = {
    :path => "video/",
    :show => "show",
    :dvd_title => 1,
    :season => 1,
    :episode => 1,  
    :audio_tracks => 1,
    :exec => false,
    :overwrite => false
  }.merge(params)
  
    filename="#{o[:path]}#{o[:show]}.#{o[:season]}x#{'%02d' % o[:episode]}.#{o[:title].split(' ').join('.')}.mkv"
        if File.exist?(filename) && !o[:overwrite] then
            puts "Hey dickhead Y U overwrite #{filename}?"
        return
    end
  
#    `/usr/bin/purple-remote "setstatus?status=available&message=enc #{filename}"`  
    
    #--audio #{o[:audio_tracks]}
    filename.gsub!(/[\(\)]/, '.')   
    aopt="--native-dub --native-language #{o[:audio_tracks]} -E faac -B 128 -6 stereo -R Auto -D 0.0"
    vopt="-e x264  -q  21.0 -f mkv --loose-anamorphic -m -x ref=1:weightp=1:subq=2:rc-lookahead=10:trellis=0:8x8dct=0"
    fopt="--denoise weak --detelecine --width 624"
  #--start-at duration:57
    cmd="HandBrakeCLI -i /dev/sr0 -t #{o[:dvd_title]}  -o #{filename} #{aopt} #{vopt} #{fopt}" 
    puts cmd
    `#{cmd}` if o[:exec]
end






options = {
    :show => "show",
    :series_id => 0,

    :season => 1,
    :episode_start => 1,

    :title_start => 1,
    :title_no => 1,
    :titles => [],

    :audio_tracks => "eng",

    :path=> '/media/daten/todo/'
}

OptionParser.new do |opts|
  opts.banner = "Usage: start.rb [options]"

  opts.on("-S", "--series TITLE", "name of the tv series") do |show|
    options[:show] = show
  end
  opts.on("-s", "--season N", "season #") do |n|
    options[:season] = n
  end 
  opts.on("-e", "--episode N", "episode #") do |n|
    options[:episode_start] = n
  end 
  opts.on("-T", "--title N", "track") do |n|
    options[:title_start] = n
  end   
  opts.on("-t", "--titles N", "tracks") do |n|
    options[:title_no] = n
  end   
  opts.on("-a", "--atracks N", "langcode") do |n|
    options[:audio_tracks] = n
  end    
      opts.on_tail("-h", "--help", "Show this message") do
        puts opts
        exit
      end  
end.parse!

p options



# guess show
print "Retrieving show list ..."
titles = query_series_list( options[:show] )
print "done\n"

episodes = []
if titles.empty? then
  options[:series_id] = options[:show]
  puts "Show #{options[:show]} not found."
  exit
 
else

  ch=0
  if titles.length>1 then
    titles.each_with_index do |title, i|
      print "[#{i}] - #{title[0]}\n"
    end
    print "which one? [0] "
    ch = STDIN.gets.chomp.to_i
  end
  options[:show]=titles[ch][0]
  options[:series_id]=titles[ch][1]
  
  print "Retrieving show #{options[:show]} infos ..."

  show_file = "show_#{options[:series_id]}.xml"
  if File.exists?(show_file) then
    print " from FILE ..."
    file = File.new( show_file )
    doc = REXML::Document.new file
  else
    print " from #{TVDB_URI} ..."
    doc = get_xml("/api/#{TVDB_KEY}/series/#{options[:series_id]}/all/")
    file = File.new( show_file, 'w' )
    file.write(doc.to_s)
    file.close
  end  
  doc.elements.each('Data/Episode') do |ele|
    if (ele.elements['SeasonNumber'].text.to_i == options[:season].to_i &&
        ele.elements['EpisodeNumber'].text.to_i >= options[:episode_start].to_i) ||
        ele.elements['SeasonNumber'].text.to_i > options[:season].to_i then
      episodes << [ele.elements['SeasonNumber'].text,ele.elements['EpisodeNumber'].text,ele.elements['EpisodeName'].text]
    end
  end

  print "done\n"

end


options[:show]=options[:show].split(' ').join('.')
index=0

#exit 

while index < episodes.length do


options[:titles].clear

while options[:titles].empty? do
# require disc
#`eject`
puts "Please insert DVD starting Season #{episodes[index][0]} Episode #{episodes[index][1]} and hit [RETURN]"
STDIN.gets
#`eject -t`
#sleep 1

print "Reading DVD TOC ..."
lsdvd=`lsdvd -a -Ox`
doc = REXML::Document.new( lsdvd )
puts doc.elements['lsdvd/title'].text

doc.elements.each('lsdvd/track') do |e|
  #puts e.elements['length'].text
  if e.elements['length'].text.to_i > EPISODE_LENGTH_MIN then
    options[:titles] << e.elements['ix'].text
    
#    e.elements.each('audio') do |a|
#      # puts a
#      if a.elements['langcode'].text=='en' then 
#        options[:audio_tracks] = a.elements['ix'].text
#      end
#    end
  end
end
print " done\n"
end

p options

#exit

#clients = `cat #{CLIENTS_FILE}`.split
#scatter_cmd(clients, "eject")
# wait for input
#scatter_cmd(clients, "eject -t")

options[:titles].each do |ep|
    
    hand_brake  :path => options[:path], 
                :show => options[:show], 
                :dvd_title => ep, 
                :season => episodes[index][0], 
                :episode => episodes[index][1], 
                :title => episodes[index][2],
                :audio_tracks => options[:audio_tracks], 
                :exec => false
    index+=1              
end

end






