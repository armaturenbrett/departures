class VBBDepartureBoard
  require 'action_view'
  require 'uri'
  require 'net/http'
  require 'json'
  require 'time'
  require 'awesome_print'

  def initialize
    @base_url = 'http://fahrinfo.vbb.de/restproxy' # 'http://demo.hafas.de/openapi/vbb-proxy'
    @access_id = nil
    @language = 'de'
    @cli_mode = false
    @configuration = []
    @pending_updates = 0
  end

  def create_widget_cache
    new_departures_datum = {}
    @configuration.each do |widget|
      widget_id = widget[:widget_id]
      new_departures_datum[widget_id] = {}
    end

    WidgetDatum.new(name: 'departures', data: new_departures_datum).save_without_broadcast
  end

  def start_with_configuration(config)
    @access_id = config['access-id']
    @language = config['api-language']
    @configuration = config['boards']

    create_widget_cache unless @cli_mode
    get_station_ids_for_configuration

    $widget_scheduler.every '1m', first: :immediately do
      departures_for_configuration
    end unless @cli_mode

    departures_for_configuration if @cli_mode
  end

  def departures_for_configuration
    @pending_updates = @configuration.count
    @configuration.each do |widget|
      departures(widget)
    end
  end

  def get_station_ids_for_configuration
    (0..(@configuration.count - 1)).each do |index|
      search_station_id_for_config(index, 'start')
      search_station_id_for_config(index, 'direction')
    end
  end

  def search_station_id_for_config(index, attribute)
    service = 'location.name'
    search_name = @configuration[index][attribute]
    parameters = {
      input: search_name,
      type: 'S'
    }

    url = create_request_address(service, parameters)
    api_request(url) do |responseJson|
      @configuration[index][attribute] = {
        human_readable: search_name,
        stationId: responseJson['StopLocation'][0]['id']
      }
    end
  end

  def departures(widget)
    service = 'departureBoard'
    earliest_departure_time = Time.now + (60 * widget['walk_time'])
    parameters = {
      id: widget['start'][:stationId],
      products: widget['products'],
      maxJourneys: widget['upcoming_connections'],
      direction: widget['direction'][:stationId],
      time: earliest_departure_time.strftime('%H:%M')
    }

    url = create_request_address(service, parameters)
    api_request(url) do |response_json|
      departures_received = !response_json['Departure'].nil?
      process_departure_response(response_json, widget) if departures_received
    end
  end

  def process_departure_response(response_json, widget)
    widget_id = widget['widget_id']
    station = {
      name: widget['title'],
      departures: extract_departure_details_from_response(response_json),
      walkTime: widget['walk_time'],
      maxWaitTime: widget['max_wait_time'],
      widgetId: widget_id
    }

    unless @cli_mode
      @pending_updates -= 1
      current_datum = WidgetDatum.find('departures')
      current_datum.data[widget_id] = station
      current_datum.save if @pending_updates.zero?
      current_datum.save_without_broadcast unless @pending_updates.zero?
    end
    ap(station) if @cli_mode
  end

  def create_request_address(service, parameters)
    address = "#{@base_url}/#{service}"
    suffix = "accessId=#{@access_id}&format=json&lang=#{@language}"
    argument_list = []

    parameters.each do |key, value|
      value = URI::encode(value) if value.class == String
      argument_list.push "#{key}=#{value}"
    end

    URI.parse("#{address}?#{argument_list.join('&')}&#{suffix}")
  end

  def api_request(url)
    ap "Departures: calling #{url}" if @cli_mode
    request_object = Net::HTTP::Get.new(url.to_s)
    response = Net::HTTP.start(url.host, url.port) do |http|
      http.request request_object
    end

    if response.is_a?(Net::HTTPSuccess)
      response_hash = JSON.parse response.body
      yield response_hash
    else
      ap 'Departures: API response error!'
    end
  end

  def extract_departure_details_from_response(response)
    departures = remove_cancaled_departures(response['Departure'])
    departures.sort_by! { |k| time_of_departure(k) }

    relevant_details = []
    departures.each do |journey|
      departure_time = journey['rtTime'].nil?? journey['time'] : journey['rtTime']
      relevant_details.push({
        line:                   journey['Product']['line'],
        destination:            journey['direction'],
        departureTime:          departure_time[0..-4],
        minutesUntilDeparture:  minutes_until_departure(journey)
      })
    end

    relevant_details
  end

  def remove_cancaled_departures(departures)
    departures.reverse().each_with_index do |departure, index|
      if departure['cancelled'] == true
        departures.delete_at(index)
      end
    end
  end

  def time_of_departure(departure)
    date_string = "#{departure['rtDate']}-#{departure['rtTime']}" unless departure['rtDate'].nil?
    date_string = "#{departure['date']}-#{departure['time']}" if departure['rtDate'].nil?
    Time.parse(date_string)
  end

  def minutes_until_departure(departure)
    time_difference = time_of_departure(departure) + 59 - Time.now
    (time_difference / 60).to_i
  end

  def cli_mode
    @cli_mode = true
  end
end

board = VBBDepartureBoard.new

if __FILE__ == $0
  exit unless ARGV.count == 1
  board.cli_mode
  $config = {}
  $config['departures'] = {}
  $config['departures']['access-id'] = ARGV[0]
  $config['departures']['api-language'] = 'de'
  $config['departures']['boards'] = []
  $config['departures']['boards'][0] = {
    'direction' => 'S Treptower Park',
    'max_wait_time' => 7,
    'products' => 8,
    'start' => 'Bouchestr',
    'title' => 'Treptower Park',
    'upcoming_connections' => 3,
    'walk_time' => 5,
    'widget_id' => 'bouchestr-to-treptowerpark'
  }
end

board.start_with_configuration $config['departures']
