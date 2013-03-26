module AppleTvConverter
  class MediaConverterAdapter
    include AppleTvConverter

    def extract_subtitles(media, languages)
      puts "* Extracting subtitles"

      languages.map!(&:to_sym)

      if media.has_embedded_subtitles?(languages)
        last_destination_filename = nil

        options = "-scodec subrip"

        media.ffmpeg_data.streams.each do |stream|
          next unless stream.type == :subtitle && (languages.empty? || languages.include?(stream.language.to_sym))
          filename = File.join(File.dirname(media.original_filename), "#{File.basename(media.original_filename).gsub(File.extname(media.original_filename), %Q[.#{stream.stream_number}.#{stream.language}.srt])}")

          begin
            printf "  * #{File.basename(filename)}: Progress:     0%"
            start_time = Time.now.to_i
            transcoded = media.ffmpeg_data.transcode(filename, "#{options} -map #{stream.input_number}:#{stream.stream_number}", :validate_output => false) do |progress|
              elapsed = Time.now.to_i - start_time
              printf "\r" + (" " * 40)
              printf "\r  * #{File.basename(filename)}: Progress: #{(progress * 100).round(2).to_s.rjust(6)}%% (#{(elapsed / 60).to_s.rjust(2, '0')}:#{(elapsed % 60).to_s.rjust(2, '0')})     "
            end
            puts ""
          rescue Interrupt
            puts "\nProcess canceled!"
            exit!
          end
        end

        puts "  * Extracted all subtitles"
      else
        puts "  * No subtitles to extract"
      end
    end

    def transcode(media, languages = nil)
      if media.needs_transcoding?
        puts "* Transcoding"

        options = {}
        options[:codecs] = get_transcode_options(media)
        options[:files] = ""
        options[:metadata] = ""
        options[:map] = ""
        options[:extra] = ""

        # Better video and audio transcoding quality
        if media.needs_video_conversion?
          # Ensure divisible by 2 width and height
          dimensions = "-s #{(media.ffmpeg_data.width % 2 > 0) ? (media.ffmpeg_data.width + 1) : media.ffmpeg_data.width}x#{(media.ffmpeg_data.height % 2 > 0) ? (media.ffmpeg_data.height + 1) : media.ffmpeg_data.height}" if media.ffmpeg_data.width % 2 > 0 || media.ffmpeg_data.height % 2 > 0

          options[:extra] << " #{dimensions} -mbd rd -flags +mv4+aic -trellis 2 -cmp 2 -subcmp 2 -g 300 -pass 1 -q:v 1 -r 23.98"
        end

        if media.needs_audio_conversion?
          if media.ffmpeg_data.audio_codec =~ /mp3/i
            # Ensure that destination audio bitrate is 128k for Stereo MP3 (couldn't convert with higher bitrate)
            audio_bitrate = 128 if media.ffmpeg_data.audio_channels == 2
          elsif media.ffmpeg_data.audio_codec =~ /pcm_s16le/i
            # Ensure that destination audio bitrate is 128k for PCM signed 16-bit little-endian (couldn't convert with higher bitrate)
            audio_bitrate = 128
          elsif media.ffmpeg_data.audio_codec =~ /ac3/i
            # Ensure that maximum destination audio bitrate is 576k for AC3 (couldn't convert with higher bitrate)
            audio_bitrate = [media.ffmpeg_data.audio_bitrate || 576, 576].min
          end

          audio_bitrate ||= media.ffmpeg_data.audio_bitrate || 448

          options[:extra] << " -af volume=2.000000" # Increase the volume when transcoding
          options[:extra] << " -ac #{media.ffmpeg_data.audio_channels} -ar #{media.ffmpeg_data.audio_sample_rate}"
          options[:extra] << " -ab #{[audio_bitrate, (media.ffmpeg_data.audio_bitrate || 1000000)].min}k"
        end

        # If the file has more than one audio track, map all tracks but subtitles when transcoding
        if media.audio_streams.length > 0
          media.streams.each do |stream|
            options[:map] << " -map #{stream.input_number}:#{stream.stream_number}" if stream.type == :video || (stream.type == :audio && (languages.nil? || languages.empty? || languages.include?(stream.language)))
          end
        end

        options = "#{options[:files]} #{options[:codecs]} #{options[:map]} #{options[:metadata]} #{options[:extra]}"

        transcoded = nil

        begin
          start_time = Time.now.to_i
          transcoded = media.ffmpeg_data.transcode(media.converted_filename, options) do |progress|
            elapsed = Time.now.to_i - start_time
            printf "\r" + (" " * 40)
            printf %Q[\r  * Progress: #{(progress * 100).round(2).to_s.rjust(6)}%% (#{(elapsed / 60).to_s.rjust(2, '0')}:#{(elapsed % 60).to_s.rjust(2, '0')})]
          end
        rescue Interrupt
          puts "\nProcess canceled!"
          exit!
        end

        status = transcoded.valid?

        printf "\r" + (" " * 40)

        if status
          puts "\r  * Progress: [DONE]#{' ' * 20}"
        else
          puts "\r  * Progress: [ERROR]#{' ' * 20}"
          exit!
        end
      else
        puts "* Encoding: [UNNECESSARY]"
        status = true
      end

      return status
    end

    def add_subtitles(media)
      raise NotImplementedYetException
    end

    def get_imdb_info(media)
      printf "* Getting info from IMDB"

      if media.imdb_id
        media.imdb_movie = Imdb::Movie.new(media.imdb_id)
      elsif Dir[File.join(File.dirname(media.original_filename), '*.imdb')].any?
        media.imdb_movie = Imdb::Movie.new(File.basename(Dir[File.join(File.dirname(media.original_filename), '*.imdb')].first).gsub(/\.imdb$/i, ''))
      else
        puts " [SKIPPING - COULDN'T FIND IMDB ID]"
        return
      end

      puts " [DONE]"
    end

    def tag(media)
      raise NotImplementedYetException
    end

    def add_to_itunes(media)
      raise NotImplementedYetException
    end

    def clean_up(media)
      printf "* Cleaning up"
      begin
        if media.needs_transcoding?
          FileUtils.rm media.original_filename

          if media.converted_filename_equals_original_filename?
            FileUtils.mv media.converted_filename, media.original_filename
          end
        end

        # Always clean up subtitles and artwork, and backup
        FileUtils.rm(media.artwork_filename) if File.exists?(media.artwork_filename)
        FileUtils.rm_r list_files(media.original_filename.gsub(File.extname(media.original_filename), '*.srt'))
        FileUtils.rm(media.backup_filename) if File.exists?(media.backup_filename)


        puts " [DONE]"
      rescue
        puts " [ERROR]"
      end
    end

    protected

      def list_files(ls)
        raise NotImplementedYetException
      end

      def has_subtitles?(media)
        list_files(File.join(File.dirname(media.original_filename), '*.srt')).any?
      end

      def get_transcode_options(media)
        options =  " -vcodec #{media.needs_video_conversion? ? 'libx264' : 'copy'}"
        options << " -acodec #{media.needs_audio_conversion? ? 'libfaac' : 'copy'}"

        options
      end

      def load_movie_from_imdb(media)
        begin
          search = Imdb::Search.new(media.show)

          return search.movies.first if search.movies.count == 1
        rescue
        end

        return nil
      end
  end
end