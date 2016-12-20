App.widget_data = App.cable.subscriptions.create channel: 'WidgetDataChannel', widget: 'departures',

  connected: ->
    console.log('departures connected')

  disconnected: ->
    console.log('departures disconnected')
    window.departuresWidget.resetTemplate()

  received: (data) ->
    console.log('departures received data:', data)
    window.departuresWidget.latestDataSet = data
    window.departuresWidget.newOverwritingUpdate()



class DeparturesWidget
  _this = undefined

  constructor: ->
    _this = this

    $widget = $('.widget .departures')
    this.template = $widget[0].innerHTML
    this.$widgets = {}
    this.widgetsMetaData = {}
    this.latestDataSet = $widget.data('preload')
    this.overwritingUpdateFor = {}
    this.updateIntervalSeconds = 3

    this.initWidgets()
    this.newOverwritingUpdate()
    this.updateCollection()

    setInterval ->
      _this.updateCollection()
    , (this.updateIntervalSeconds * 1000)

  initWidgets: ->
    $('.widget .departures').each ->
      $currentWidget = $(this)
      widgetId = $currentWidget.attr('id')
      _this.$widgets[widgetId] = $currentWidget
      _this.widgetsMetaData[widgetId] = {
        minutesUntilNextLeave: 999,
        secondsUntilNextLeave: 999,
        maxWaitTime: 0
      }

  updateCollection: ->
    for widgetId, station of this.latestDataSet
      if station.widgetId
        this.overwriteTimings(station) if this.overwritingUpdateFor[widgetId]
        this.updateTimings(station) unless this.overwritingUpdateFor[widgetId]
        this.renderStation(station)

  overwriteTimings: (data) ->
    minUntilDeparture = parseInt(data.departures[0].minutesUntilDeparture)
    minutesUntilNextLeave = minUntilDeparture - data.walkTime
    minutesUntilNextLeave = 0 if minutesUntilNextLeave < 0
    data.minutesUntilNextLeave = minutesUntilNextLeave

    metaObject = this.widgetsMetaData[data.widgetId]
    metaObject.minutesUntilNextLeave = minutesUntilNextLeave
    metaObject.secondsUntilNextLeave = (minutesUntilNextLeave * 60) + 59
    metaObject.maxWaitTime = parseInt(data.maxWaitTime)

  updateTimings: (data) ->
    metaObject = this.widgetsMetaData[data.widgetId]
    minutesUntilNextLeave = metaObject.minutesUntilNextLeave
    secondsUntilNextLeave = metaObject.secondsUntilNextLeave - this.updateIntervalSeconds
    metaObject.secondsUntilNextLeave = secondsUntilNextLeave

    if secondsUntilNextLeave > 0 && Math.floor(secondsUntilNextLeave / 60) < minutesUntilNextLeave
      minutesUntilNextLeave = minutesUntilNextLeave - 1
      minutesUntilNextLeave = 0 if minutesUntilNextLeave < 0
      metaObject.minutesUntilNextLeave = minutesUntilNextLeave
      data.minutesUntilNextLeave = minutesUntilNextLeave

      for journey in data.departures
        journey.minutesUntilDeparture = journey.minutesUntilDeparture - 1

  renderStation: (data) ->
    widgetId = data.widgetId
    this.$widgets[widgetId].fadeOut() if this.overwritingUpdateFor[widgetId]

    this.setBackgroundColorFor(widgetId)
    this.render(this.template, data)

    if this.overwritingUpdateFor[widgetId]
      this.$widgets[widgetId].fadeIn()
      this.overwritingUpdateFor[widgetId] = false

  render: (template, data) ->
    renderedTemplate = Mustache.render(template, data)
    this.$widgets[data.widgetId].html(renderedTemplate)

  setBackgroundColorFor: (widgetId) ->
    maxWaitTime = this.widgetsMetaData[widgetId].maxWaitTime
    minutesUntilNextLeave = this.widgetsMetaData[widgetId].minutesUntilNextLeave
    secondsUntilNextLeave = this.widgetsMetaData[widgetId].secondsUntilNextLeave - 60
    $widget = this.$widgets[widgetId]

    if minutesUntilNextLeave > maxWaitTime
      $widget.css('background-color', '')
    else
      hue = secondsUntilNextLeave * (140 / (maxWaitTime * 60))
      hue = 0 if secondsUntilNextLeave <= 0
      $widget.css('background-color', "hsl(#{hue}, 60%, 60%)")

  newOverwritingUpdate: ->
    for widgetId, _ of this.latestDataSet
      _this.overwritingUpdateFor[widgetId] = true

$(document).ready ->
  window.departuresWidget = new DeparturesWidget()
