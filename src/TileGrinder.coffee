###
  TileGrinder - grinds for you threw a MBTile
  by Michael Strassburger <codepoet@cpan.org>

  A handy library in case you ever want to apply a processor to all vector tiles
  in an MBTiles without having to worry about how to pull, decode, alter, encode
  and store them again.
###

MBTiles = require 'mbtiles'
Protobuf = require 'node-protobuf'
Promise = require 'bluebird'
split = require 'split'

zlib = require 'zlib'
path = require 'path'
fs = Promise.promisifyAll require 'fs'

module.exports = class TileGrinder
  config:
    debug: true
    output: "mbtiles"

    maxZoom: 14
    copyAboveZoom: null

  queueSize: 64

  source: null
  target: null
  protobuf: null

  bytesBefore: 0
  bytesAfter: 0

  constructor: (options) ->
    @config[option] = options[option] for option of options
    @protobuf = new Protobuf fs.readFileSync __dirname+"/../proto/vector_tile.desc"

  grind: (source, @destination, @callback) ->
    @_log "[>] starting to grind"

    @_mustExist source
    .then => @_loadMBTiles source
    .then => @_createMBTiles @destination
    .then => @_grind()
    .then => @_waitForWrites()
    .then =>
      @_log "[+] grinding done!"
      @_log "[>] saved #{Math.round (@bytesBefore-@bytesAfter)/@bytesBefore*100}% of storage"

    .catch (e) ->
      console.error e

  _grind: ->
    new Promise (resolve, reject) =>
      stream = @source
      .createZXYStream batch: @queueSize
      .pipe split()

      queueSpots = @queueSize
      paused = false
      done = false

      stream
      .on 'data', (str) =>
        return unless str

        [z, x, y] = str.split /\//
        return if @config.maxZoom and z > @config.maxZoom

        queueSpots--
        if queueSpots < 1 and not paused
          stream.pause()
          paused = true

        promise = if @config.copyAboveZoom and z >= @config.copyAboveZoom
          @_loadTile z, x, y
          .then (buffer) => @_storeTile z, x, y, buffer
        else
          @_processTile z, x, y

        promise.finally =>
          queueSpots++
          if paused and queueSpots > 0
            stream.resume()
            paused = false

          resolve() if done and queueSpots is @queueSize

      .on 'end', =>
        @_log "[+] waiting for workers to finish..."
        done = true
        resolve() if queueSpots is @queueSize

  _waitForWrites: ->
    return unless @config.output is "mbtiles"

    console.log "[+] finishing database"
    new Promise (resolve, reject) =>
      @target.stopWriting (err) =>
        reject err if err
        resolve()

  _createMBTiles: (destination) ->
    return unless @config.output is "mbtiles"

    new Promise (resolve, reject) =>
      new MBTiles destination, (err, @target) =>
        return reject err if err

        @target.startWriting (err) =>
          return reject err if err
          resolve()

  _loadMBTiles: (source) ->
    new Promise (resolve, reject) =>
      new MBTiles source, (err, @source) =>
        if err then reject err
        else resolve()

  _updateMBTilesInfo: () ->
    new Promise (resolve, reject) =>
      @source.getInfo (err, info) =>
        return reject err if err

        info.mtime = Date.now()

        @target.putInfo info, (err) =>
          return reject err if err
          resolve()

  _processTile: (z, x, y) ->
    original = null

    @_loadTile z, x, y
    .then (buffer) => @_unzipIfNeeded original = buffer
    .then (buffer) => @_decodeTile buffer
    .then (tile) => @_callback tile
    .then (tile) => @_encodeTile tile
    .then (buffer) => @_gzip buffer
    .then (buffer) =>
      @_trackStats z, x, y, original, buffer
      @_storeTile z, x, y, buffer

  _callback: (tile) ->
    @callback tile
    tile

  _storeTile: (z, x, y, buffer) ->
    switch @config.output
      when "mbtiles"
        new Promise (resolve) =>
          @target.putTile z, x, y, buffer, ->
            resolve()

      when "files"
        Promise
        .resolve ["/#{z}", "/#{z}/#{x}"]
        .mapSeries (folder) => @_createFolder @destination+folder
        .then =>
          fs.writeFileAsync @destination+"/#{z}/#{x}-#{y}.pbf", buffer

  _createFolder: (name) ->
    fs
    .mkdirAsync path.resolve name
    .then -> true
    .catch (e) -> e.code is "EEXIST"

  _mustExist: (name) ->
    fs
    .statAsync path.resolve name
    .catch (e) ->
      throw new Error path+" doesn't exist."

  _loadTile: (z, x, y) ->
    new Promise (resolve, reject) =>
      @source.getTile z, x, y, (err, tile) ->
        return reject err if err
        resolve tile

  _unzipIfNeeded: (buffer) ->
    new Promise (resolve, reject) =>
      if @_isGzipped buffer
        zlib.gunzip buffer, (err, data) ->
          return reject err if err
          resolve data
      else
        resolve buffer

  _isGzipped: (buffer) ->
    buffer.slice(0,2).indexOf(Buffer.from([0x1f, 0x8b])) is 0

  _gzip: (buffer) ->
    new Promise (resolve, reject) =>
      zlib.gzip buffer, level: 9, (err, buffer) ->
        return reject err if err
        resolve buffer

  _decodeTile: (buffer) ->
    tile = @protobuf.parse buffer, "vector_tile.Tile"

    for layer in tile.layers
      for feature in layer.features
        feature.geometry = @_decodeGeometry feature.geometry

    tile

  _encodeTile: (tile) ->
    for layer in tile.layers
      for feature in layer.features
        feature.geometry = @_encodeGeometry feature, feature.geometry

    @protobuf.serialize tile, "vector_tile.Tile"

  _decodeGeometry: (geometry) ->
    idx = x = y = count = command = line = 0
    lines = []

    while idx < geometry.length
      unless count
        raw = geometry[idx++]
        command = raw & 7
        count = raw >> 3
      count--

      if command is 1 or command is 2
        x += @_dezigzag geometry[idx++]
        y += @_dezigzag geometry[idx++]

        if command is 1
          lines.push line if line
          line = []

        line.push x: x, y: y

      else if command is 7
        line.push x: line[0].x, y: line[0].y

    lines.push line if line
    lines

  _encodeGeometry: (feature, geometry) ->
    x = y = 0
    encoded = []
    return [] unless geometry?.length

    for line in geometry
      encoded.push @_command 1, 1

      last = line.length-1
      close =
        feature.type is "POLYGON" and
        line[last].x is line[0].x and
        line[last].y is line[0].y

      for point, i in line
        if i is 1
          encoded.push @_command 2, line.length-(if close then 2 else 1)

        else if close and i is last
          encoded.push @_command 7, 1
          break

        dx = point.x - x
        dy = point.y - y

        encoded.push @_zigzag(dx), @_zigzag(dy)

        x += dx
        y += dy

    encoded

  _command: (command, count) ->
    (command & 7) | (count << 3)

  _zigzag: (int) ->
    (int << 1) ^ (int >> 31)

  _dezigzag: (int) ->
    (int >> 1) ^ -(int & 1)

  _trackStats: (z, x, y, original, reduced) ->
    saved = original.length-reduced.length
    @bytesBefore += original.length
    @bytesAfter += reduced.length
    @_log "[>] #{Math.round saved/original.length*100}% less data in zoom #{z}, x: #{x} y: #{y}"

  _log: (msg...) ->
    console.log msg... if @config.debug
