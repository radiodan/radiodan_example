require 'eventmachine'
require 'date'

class RadioController
  include Radiodan::Logging

  @@playlist = Radiodan::Playlist.new

  # Secs before feed expiry to refresh
  FEED_EXPIRY_BUFFER = 60

  def self.playlist
    @@playlist
  end

  def initialize(*config)
    @options  = config.shift
    @stations = @options[:stations] || []
    @current_station = nil
    @expiry_timer = nil
  end

  def call(player)
    @player = player
    logger.debug "RadioController middleware"

    player.register_event :playlist do |playlist|
      station = @stations.find { |s| s.bbc_id == playlist.tracks.first[:id] }
      @current_station = station if station

      # Update expiry timer
      logger.info "New station, will expire: #{@current_station.expires}"

      if @expiry_timer
        logger.debug "Cancelling existing timer"
        logger.debug @expiry_timer.class
        @expiry_timer.cancel
      end

      secs_until_feed_expires = @current_station.expires.to_time - DateTime.now.to_time
      logger.debug "Feed expires in #{secs_until_feed_expires}s"
      @expiry_timer = EventMachine::Synchrony.add_timer(secs_until_feed_expires - FEED_EXPIRY_BUFFER) do
        @current_station.reset!
        player.playlist.tracks = @current_station.playlist.tracks
      end
    end

    player.register_event :toggle_power do
      power!
    end

    player.register_event :change_volume do |new_volume|
      current_volume = volume
      case new_volume
      when 'up'
        volume(current_volume + 2)
      when 'down'
        volume(current_volume - 2)
      else
        volume(new_volume)
      end
    end

    player.register_event :change_station do |station_id|
      case station_id
      when :next
        next_station
      when :previous
        previous_station
      else
        station(station_id)
      end
    end
  end

  def power!
    logger.info "Toggle power"
    if @player.playlist.state == :play
      @player.pause
    else
      @player.play
    end
  end

  def volume
    @player.playlist.volume
  end

  def volume(value=nil)
    @player.playlist.volume = value unless value.nil? || value < 0 || value > 100
    @player.playlist.volume
  end

  def next_station
    station(surrounding_stations[:next])
  end

  def previous_station
    station(surrounding_stations[:previous])
  end

  def station(station_id)
    station = @stations.find { |station| station.bbc_id == station_id }
    if station
      tracks = station.playlist.tracks
      @player.playlist.tracks = tracks
    else
      logger.warn "Can't find station: #{station_id}"
    end
  end

  private
  def surrounding_stations
    current_station_index = @stations.index(@current_station)
    next_station = @stations[(current_station_index + 1) % @stations.length]
    prev_station = @stations[(current_station_index - 1) % @stations.length]
    { :next => next_station.bbc_id, :previous => prev_station.bbc_id }
  end
end
