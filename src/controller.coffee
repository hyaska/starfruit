#
#       _/_/_/    _/                              _/_/                      _/    _/      
#    _/        _/_/_/_/    _/_/_/  _/  _/_/    _/      _/  _/_/  _/    _/      _/_/_/_/   
#     _/_/      _/      _/    _/  _/_/      _/_/_/_/  _/_/      _/    _/  _/    _/        
#        _/    _/      _/    _/  _/          _/      _/        _/    _/  _/    _/         
# _/_/_/        _/_/    _/_/_/  _/          _/      _/          _/_/_/  _/      _/_/      
#
# MIT Licensed
# Copyright (c) 2014 Kan Kung-Yip
#
# Dynamic Controller

# Module dependencies
fs = require 'fs'
url = require 'url'
path = require 'path'
util = require 'util'
domain = require 'domain'
{Readable} = require 'stream'
querystring = require 'querystring'

# function -> script
Function::script = (argv) ->
  env = ''
  for key, val of argv
    value = ''
    switch typeof val
      when 'string' then value += "\"#{ val.replace /["|']/g, '\\"' }\""
      when 'object' then value += JSON.stringify val
      else value += val.toString()
    env += "var #{key}=#{value};"
  return "#{env}(#{@toString()})();"

# Application script
application = ->
  # application object
  app = window.app = {}
  app.callers = {}

  # application events
  app.selector = window.selector = (selname) ->
    window._event = event
    return app.callers[selname](selname) if typeof app.callers[selname] is 'function'
    $.getScript "#{location.pathname}?_id=event&_key=script&selector=#{selname}"
    .done -> app.callers[selname](selname) if typeof app.callers[selname] is 'function'

  # get element value or attrible
  getValue = app.getValue = (elem, name) ->
    switch name.toString().toLowerCase()
      when 'text' then elem.text()
      when 'html' then elem.html()
      when 'value' then elem.val()
      else elem.attr name

  # set element value or attrible
  setValue = app.setValue = (elem, name, value) ->
    switch name.toString().toLowerCase()
      when 'text' then elem.text value
      when 'html' then elem.html value
      when 'value' then elem.val value
      else elem.attr name, value

  # data model
  models = app.models = (model, selname) ->
    # getting data
    get = ->
      data = {}
      _get = (sets) ->
        sets._selname = selname
        sets.base ?= 'base'
        if (models[sets.base]?) and (typeof models[sets.base].get is 'function')
          models[sets.base].get sets
        else models.base.get sets, $('html')
      for name, sets of model
        if (typeof sets is 'string') or $.isArray sets
          data = _get model
          break
        data[name] = _get sets
      JSON.stringify data

    # setting data
    set = (data) ->
      _set = (sets, data) ->
        sets._selname = selname
        sets.base ?= 'base'
        if (models[sets.base]?) and (typeof models[sets.base].get is 'function')
          models[sets.base].set sets, data
        else models.base.set sets, data, $('html')
      for name, sets of model
        if (typeof sets is 'string') or $.isArray sets
          _set model, data
          break
        _set sets, data[name]

    # post event
    $.post "#{location.pathname}?_id=event&_key=data&selector=#{selname}",
      get(), set, 'json'

  # base data model
  models.base =
    get: (sets, root) ->
      root ?= $('html')
      data = {}
      sets = sets.entry if sets.entry
      for id, attrs of sets
        elem = root.find '#' + id
        data[id] = {}
        unless $.isArray attrs then data[id] = getValue elem, attrs
        else data[id][attr] = getValue elem, attr for attr in attrs
      return data

    set: (sets, data, root) ->
      root ?= $('html')
      sets = sets.entry if sets.entry
      for id, attrs of sets
        elem = root.find '#' + id
        continue unless data[id]?
        unless $.isArray attrs then setValue elem, attrs, data[id]
        else setValue elem, attr, data[id][attr] for attr in attrs

  # list data model
  models.list =
    actived: (sets) ->
      root = $ '#' + sets.root
      temp = "[style*='#{sets.active.style}']"
      temp = ".#{sets.active.class}" if sets.active.class
      root.children temp

    target: (sets) ->
      if sets.active.index?
        root = $ '#' + sets.root
        index = parseInt sets.active.index
        if isNaN(index) or (index < 0) then index = 0
        length = root.children().length
        if index >= length then index = length - 1
        target = root.children().eq index
      else
        target = $ _event.target
        type = 'on' + _event.type
        if typeof target.attr(type) isnt 'string'
          target = target.parents "[#{type}*='#{sets._selname}']:first"
      return target

    get: (sets) ->
      data = {}
      actived = models.list.actived sets
      switch sets.method.toLowerCase()
        when 'remove'
          data = models.base.get sets.entry, actived
          data._id = actived.attr 'id'
        when 'active'
          target = actived
          target = models.list.target sets unless sets.active.index? and actived.length > 0
          data = models.base.get sets.entry, target
          data._id = target.attr 'id'
      return data

    set: (sets, data) ->
      actived = models.list.actived sets
      method = sets.method.toLowerCase()
      switch method
        when 'add', 'insert'
          return unless data
          root = $ '#' + sets.root
          return if root.length < 1
          temp = "[style*='#{sets.active.style}']"
          temp = ".#{sets.active.class}" if sets.active.class
          template = root.children().not(temp).first()
          for uid, record of data
            entry = template.clone()
            entry.attr 'id', uid
            # set contents
            for id, attrs of sets.entry
              elem = entry.children '#' + id
              unless $.isArray attrs then setValue elem, attrs, record[id]
              else setValue elem, attr, value[id][attr] for attr in attrs
            if (actived.index() < 0) or (method is 'add') then root.append entry
            else entry.insertBefore actived
          unless template.attr('id') then template.remove()

        when 'active'
          return if sets.active.index? and actived.length > 0
          root = $ '#' + sets.root
          target = models.list.target sets
          models.base.set sets, data, target
          # active style
          if sets.active.class
            root.children().removeClass sets.active.class
            target.addClass sets.active.class
          if sets.active.style
            template = root.children().not("[style*='#{sets.active.style}']").first()
            style = if template.attr 'style' then template.attr 'style' else ''
            root.children().attr 'style', style
            style = if target.attr 'style' then target.attr 'style' else ''
            target.attr 'style', "#{style};#{sets.active.style};"

        when 'blur', 'remove'
          root = $ '#' + sets.root
          if sets.active.class
            root.children().removeClass sets.active.class
          if sets.active.style
            template = root.children().not("[style*='#{sets.active.style}']").first()
            style = if template.attr 'style' then template.attr 'style' else ''
            root.children().attr 'style', style
          # remove actived item
          actived.remove() if (method is 'remove') and (actived.index() > -1)

  # getting user event
  window.constructor::__defineGetter__ 'event', ->
    func = arguments.callee.caller
    while func?
      arg = func.arguments[0]
      return arg if arg instanceof Event
      func = func.caller
    return null

  # elements' load event
  $(document).ready -> $('[onload]').load()

# prototype
module.exports = class Controller

  # Constructor
  constructor: ->
    # sandbox runtime
    @_domain = domain.create()
    @_domain.on 'error', (err) =>
      @_finish = null
      @_error? err
    # application's event callback
    @_script = ''

  # Unique ID
  uid: (length = 8) ->
    id = ''
    id += Math.random().toString(36).substr(2) while id.length < length
    id.substr 0, length

  # Render content
  render: ->
    template = "<!DOCTYPE html>
      <html>
        <head>
          <title>%s</title>
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
          <!-- Bootstrap -->
          <link rel=\"stylesheet\" href=\"http://cdn.bootcss.com/twitter-bootstrap/3.0.3/css/bootstrap.min.css\">

          <!-- Styles -->
          <link rel=\"stylesheet\" href=\"/styles.css\">

          <!-- HTML5 Shim and Respond.js IE8 support of HTML5 elements and media queries -->
          <!-- WARNING: Respond.js doesn't work if you view the page via file:// -->
          <!--[if lt IE 9]>
              <script src=\"http://cdn.bootcss.com/html5shiv/3.7.0/html5shiv.min.js\"></script>
              <script src=\"http://cdn.bootcss.com/respond.js/1.3.0/respond.min.js\"></script>
          <![endif]-->

          <!-- Favorite and touch icons -->
          <link rel=\"apple-touch-icon-precomposed\" sizes=\"144x144\" href=\"/apple-touch-icon-144-precomposed.png\">
          <link rel=\"apple-touch-icon-precomposed\" sizes=\"114x114\" href=\"/apple-touch-icon-114-precomposed.png\">
          <link rel=\"apple-touch-icon-precomposed\" sizes=\"72x72\" href=\"/apple-touch-icon-72-precomposed.png\">
          <link rel=\"apple-touch-icon-precomposed\" href=\"/apple-touch-icon-57-precomposed.png\">
          <link rel=\"shortcut icon\" href=\"/favicon.png\">
        </head>
        <body>
          %s

          <!-- jQuery (necessary for Bootstrap's JavaScript plugins) -->
          <script src=\"http://cdn.bootcss.com/jquery/1.10.2/jquery.min.js\"></script>
          <!-- Include all compiled plugins (below), or include individual files as needed -->
          <script src=\"http://cdn.bootcss.com/twitter-bootstrap/3.0.3/js/bootstrap.min.js\"></script>
          <!-- Starfruit\'s application -->
          <script src=\"%s?script\"></script>
        </body>
      </html>"
    layout = fs.readFileSync 'res/' + @layout
    @set "Content-Type": "text/html;charset=utf-8"
    @write util.format template, @title, layout, @_pathname

  # parse data raw
  parse: (raw) -> JSON.parse raw

  # Client's event script
  handle: (callback, argv) ->
    if typeof callback isnt 'function'
      throw new TypeError typeof(callback) + ' is not a function'
    @_script += callback.script argv

  # Domain running
  domain: (callback) ->
    if typeof callback isnt 'function'
      throw new TypeError typeof(callback) + ' is not a function'
    @_domain?.run callback

  # Catch the error
  error: (callback) ->
    if typeof callback isnt 'function'
      throw new TypeError typeof(callback) + ' is not a function'
    @_error = callback  

  # Set headers
  set: (headers) -> @_buffer.writeHead 200, headers

  # Write chunk or pipe stream to buffer
  write: (data, encoding = 'utf8') ->
    return @_buffer.write.apply @_buffer, arguments unless data instanceof Readable
    @_buffer.on 'pipe', => @_autoend = false
    data.setEncoding = encoding
    data.pipe @_buffer, end: @_autoend
    data.on 'end', => @_buffer.end()

  # User date model
  model: (models) ->
    return if @data
    # custom data model stored method
    stored = (sets, name) =>
      if sets.base and (sets.base.get or sets.base.set)
        name = "#{name}#{@uid()}"
        base = ''
        base += "app.models.#{name}.#{key}=#{func.toString()};" for key, func of sets.base
        @_script += "app.models.#{name}={};#{base}"
        sets.base = name
    if models.base then stored models, 'func'
    else stored sets, name for name, sets of models
    # send data model to client
    @handle (-> app.models models, selname), models: models

  # Respond client
  do: (req, @_buffer) ->
    # parse url
    req.setEncoding 'utf8'
    urls = url.parse req.url
    @_pathname = urls.pathname.toLowerCase()
    @query = querystring.parse urls.query
    @query.raw = urls.query

    # response buffer
    @_buffer.removeAllListeners 'error'
    @_buffer.on 'error', (err) => @_error? err

    # render content
    if !@query.raw or @query.raw.length < 1
      @set "Content-Type": "text/plain"
      @_autoend = true
      @render()

    # application content
    else if @query.raw is 'script'
      @_autoend = true
      @set "Content-Type": "text/javascript"
      @write application.script()

    # geting user post data
    else
      @_autoend = false
      raw = ''
      req.on 'data', (chunk) -> raw += chunk
      req.on 'end', =>
        @data = @parse raw if raw.length > 0
        switch @query._id
          when 'event'
            selector = @query.selector
            @[selector]() if typeof @[selector] is 'function'
            switch @query._key
              when 'script'
                @set "Content-Type": "text/javascript"
                @write "app.callers['#{@query.selector}']=function(selname){#{@_script}};"
              when 'data'
                @set "Content-Type": "application/json"
                @write JSON.stringify @data
        @_buffer.end()

    # end respond
    @_buffer.end() if @_autoend is true
