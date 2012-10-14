#!/usr/bin/env ruby
require 'net/http'
require 'rexml/document'
require 'optparse'


CLIENTS_FILE = 'local.clients'



module ClusterRipper
    class DVD
        
        EPISODE_LENGTH_MIN=1100.0
        EPISODE_LENGTH_MAX=3000.0
        
        def tracks
            @tracks ||= get_tracks
        end
        
        def get_tracks
            tracks = []
            print "Reading DVD TOC ..."
            lsdvd=`lsdvd -a -Ox`
            doc = REXML::Document.new( lsdvd )
            puts doc.elements['lsdvd/title'].text
                
            doc.elements.each('lsdvd/track') do |e|
#                puts e.elements['length'].text
                e_len = e.elements['length'].text.to_i
                if e_len > EPISODE_LENGTH_MIN and e_len < EPISODE_LENGTH_MAX then
                    tracks << Track.new(e.elements['ix'].text)

                #    e.elements.each('audio') do |a|
                #      # puts a
                #      if a.elements['langcode'].text=='en' then 
                #        options[:audio_tracks] = a.elements['ix'].text
                #      end
                #    end
                end
            end        
            return tracks
        end
    end

    class TVDBClient
    
        TVDB_URI='www.thetvdb.com'
        TVDB_KEY="1D807D9321ED31C5"
        
        def self.get_xml(cmd)
  	        Net::HTTP.get TVDB_URI, cmd
        end
        
        def self.query_series(series)
            titles=[]
            doc = REXML::Document.new get_xml("/api/GetSeries.php?seriesname=#{series.split(' ').join('%20')}")
            doc.elements.each('Data/Series') do |ele|
                titles << [ele.elements['SeriesName'].text, ele.elements['seriesid'].text]
            end
            return titles 
        end  
        
        def self.query_episodes(id)
            show_file = "show_#{id}.xml"
            if File.exists?(show_file) then
                print " from FILE ..."
                file = File.new( show_file )
                doc = REXML::Document.new file
            else
                print " from #{TVDB_URI} ..."
                doc = get_xml("/api/#{TVDB_KEY}/series/#{id}/all/")
                file = File.new( show_file, 'w' )
                file.write(doc.to_s)
                file.close
            end  
            return doc        
        end
    
    end
    
    class Track
        attr_accessor :id
        
        def initialize(id)
            self.id=id
        end
        
    end
    
    class Series
        attr_accessor :id, :title
        
        def initialize(params)
            self.id=params[:id]
            self.title=params[:title]
        end
        
        def episodes
            return @episodes ||= get_episodes
        end
        
        def get_episodes
            eps = []
            print "Retrieving show #{self.title} infos ..."
            doc = TVDBClient.query_episodes(self.id)
            print "done\n"
            doc.elements.each('Data/Episode') do |ele|
               next if ele.elements['SeasonNumber'].text.to_i < 1
               eps << Episode.new(
                        :season => ele.elements['SeasonNumber'].text.to_i,
                        :id => ele.elements['EpisodeNumber'].text.to_i,
                        :title => ele.elements['EpisodeName'].text)
            end 
            return eps        
        end
    end # class Series
    
    
    class Episode
        attr_accessor :title, :season, :id
        
        def initialize(params)
            self.title = params[:title]
            self.id = params[:id]
            self.season = params[:season]
        end
    end 
    
    class Ripper
        attr_accessor :show, :dvd
        def initialize
            #@dbclient = TVDBClient.new
        end
        def encode(options)
            print "Retrieving show list ..."
            titles = TVDBClient.query_series(options[:show])
            print "done\n"  
            
            if titles.empty? then
                puts "Show #{options[:show]} not found."
                exit
            end
            
            ch=0
            if titles.length>1 then
                titles.each_with_index do |title, i|
                    print "[#{i}] - #{title[0]}\n"
                end
                print "which one? [0] "
                ch = STDIN.gets.chomp.to_i
            end

            self.show = Series.new(:title => titles[ch][0], :id=> titles[ch][1])

            
            show.episodes.each_with_index do |ep, idx|
                next if ep.season < options[:season].to_i ||
                     (ep.season == options[:season].to_i &&
                       ep.id < options[:episode_start].to_i )

                if !self.dvd || self.dvd.tracks.empty? then
                    self.dvd = DVD.new 
                    # require disc
                    #`eject`
                    puts "Please insert DVD starting #{ep.season}x#{'%02d' % ep.id} aka #{idx+1} and hit [RETURN]"
                    STDIN.gets
                    #`eject -t`
                    #sleep 1
                end
                track = self.dvd.tracks.shift 
                
                hand_brake  :path => options[:path], 
                    :show => self.show.title, 
                    :dvd_title => track.id, 
                    :season => ep.season, 
                    :episode => ep.id, 
                    :title => ep.title,
                    :audio_tracks => options[:audio_tracks], 
                    :exec => true          
            end
                             

        
            
        end
        
        
        def scatter_cmd(clients,cmd)
            print "#{cmd} ..."
	        clients.each do |client| 
	            cmd = "ssh #{client} -f -- #{cmd}"
	            system cmd
	        end
            print "done\n"
        end
 
    
    end #class Ripper
    
    class HBRipper < Ripper
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
          
            filename="#{o[:path]}/#{o[:show]}/#{o[:season]}/#{o[:show]}.#{o[:season]}x#{'%02d' % o[:episode]}.#{o[:title].split(' ').join('.')}.mkv"
                if File.exist?(filename) && !o[:overwrite] then
                    puts "Hey dickhead Y U overwrite #{filename}?"
                return
            end
          
        #    `/usr/bin/purple-remote "setstatus?status=available&message=enc #{filename}"`  
            
            #--audio #{o[:audio_tracks]}
            filename.gsub!(/[\(\)']/, '.')   
            aopt="--native-dub --native-language #{o[:audio_tracks]} -E faac -B 128 -6 stereo -R Auto -D 0.0"
            vopt="-e x264  -q  21.0 -f mkv --loose-anamorphic -m -x ref=1:weightp=1:subq=2:rc-lookahead=10:trellis=0:8x8dct=0"
            fopt="--denoise weak --detelecine --width 624"
          #--start-at duration:57
            cmd="HandBrakeCLI -i /dev/sr0 -t #{o[:dvd_title]}  -o #{filename} #{aopt} #{vopt} #{fopt}" 
            puts cmd
            `#{cmd}` if o[:exec]
        end    
    end # class HBRipper

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

    :path=> '/media/daten/video/Serien'
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


ClusterRipper::HBRipper.new.encode(options)
# guess show



=begin

    #clients = `cat #{CLIENTS_FILE}`.split
    #scatter_cmd(clients, "eject")
    # wait for input
    #scatter_cmd(clients, "eject -t")



=end






