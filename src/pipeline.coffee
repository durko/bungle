{EventEmitter} = require "events"
fs = require "fs"
path = require "path"
zlib = require "zlib"

RSVP = require "rsvp"

RSVP.on "error", (error) -> console.assert false, error



RegExp::toJSON = ->
    type: "RegExp"
    source: @source
    flags: [
        if @global then "g" else ""
        if @multiline then "m" else ""
        if @ignoreCase then "i" else ""
    ].join ""

Buffer::toJSON = ->
    type: "Buffer"
    data: @toString "hex"

parseExJSON = (json) ->
    convert = (data) ->
        for k, v of data
            if v and v.type is "RegExp"
                data[k] = new RegExp v.source, v.flags
            else if v and v.type is "Buffer"
                data[k] = new Buffer v.data, "hex"
            else if typeof v is "object"
                convert v
        data

    data = JSON.parse json
    convert data

gunzip = RSVP.denodeify zlib.gunzip
gzip = RSVP.denodeify zlib.gzip
readFile = RSVP.denodeify fs.readFile
mkdir = RSVP.denodeify fs.mkdir
stat = RSVP.denodeify fs.stat
unlink = RSVP.denodeify fs.unlink
writeFile = RSVP.denodeify fs.writeFile



# CTRL-C handler
setupSIGINT = (log) ->
    shuttingDown = false
    process.on "SIGINT", ->
        if shuttingDown
            log.log "info", "process", "Force exiting ..."
            log.log "debug", "process", process._getActiveHandles()
            process.exit()
        else
            shuttingDown = true
            log.log "info", "process", "Shutting down gracefully ..."

            RSVP.all Pipeline.instances.map (pipeline) -> pipeline.cleanup()
            .then ->
                log.log "info", "process", "Bye"
                process.exit()



class Pipeline extends EventEmitter
    @sigintInstalled: false
    @instances: []
    pipes: {}

    constructor: (@logger, @cfg) ->
        if not @constructor.sigintInstalled
            setupSIGINT @logger
            @constructor.sigintInstalled = true

        @loadState()
        .then (state) =>
            @state = state
            @createPipes()
        .then =>
            # emit start event
            #RSVP.all (pipe.start() for _, pipe of @pipes)
            @orderedPipes.reduce (p, i) ->
                p.then -> i.start()
            , RSVP.Promise.resolve()
        .then =>
            @log "info", "Startup complete"
            @constructor.instances.push @
        .catch (err) =>
            @log "error", "Pipeline constructor error #{err} #{err.stack}"

    # load cached state
    loadState: ->
        filename = path.join ".bungle", "state.#{@cfg.config.hash}"

        if @cfg.config.bungle.reset
            @log "verbose", "Discarding previous state"
            unlink filename
            .catch -> null
            .then => hash: @cfg.config.hash
        else
            readFile filename
            .then (compressed) -> gunzip compressed
            .then (data) -> parseExJSON data
            .catch (err) =>
                @log "verbose", "Starting with a fresh state"
                hash: @cfg.config.hash

    createPipes: ->
        for id, pipeconfig of @cfg.config.pipes
            # get state and prototype
            pipestate = @state[id] || (@state[id] = {})
            PipeClass = @cfg.pipes[pipeconfig.type]

            @pipes[id] = new PipeClass pipeconfig, pipestate, @

        # call init and continue when all pipes are done
        RSVP.all (pipe.init() for _, pipe of @pipes)
        .then =>
            # connect inputs of all pipes
            for id, pipeconfig of @cfg.config.pipes
                for input in pipeconfig.inputs
                    @pipes[input].outputs.push @pipes[id]

            unsorted = (pipe for _, pipe of @pipes)
            sorted = []
            while unsorted.length
                add = unsorted.filter (u) ->
                    u.outputs.every (o) ->
                        o in sorted
                sorted = sorted.concat add
                unsorted = unsorted.filter (u) -> u not in add
            @orderedPipes = sorted.reverse()

    cleanup: ->
        @log "info", "Saving state"
        RSVP.all (pipe.stop() for _, pipe of @pipes)
        .then =>
            gzip JSON.stringify @state
        .then (data) =>
            filename = path.join ".bungle", "state.#{@cfg.config.hash}"
            writeFile filename, data
            .catch (err) =>
                if err.errno is -2
                    mkdir ".bungle"
                    .then -> writeFile filename, data
                    .catch (err) =>
                        @log "error", "Could not dump state cache #{err}"
                else
                    @log "error", "Could not dump state cache #{err}"
        .then =>
            @log "info", "Pipeline shutdown complete"

    broadcast: (req) ->
        RSVP.all Object.keys(@pipes).map (id) =>
            @pipes[id].broadcast req

    log: (level, args...) ->
        @logger.log level, "pipeline", args...



module.exports.Pipeline = Pipeline

