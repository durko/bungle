{EventEmitter} = require "events"
fs = require "fs"
zlib = require "zlib"

RSVP = require "rsvp"

RSVP.on "error", (error) -> console.assert false, error

RegExp::toJSON = RegExp::toJSON || ->
    type: "__regexp"
    source: @source
    flags: [
        if @global then "g" else ""
        if @multiline then "m" else ""
        if @ignoreCase then "i" else ""
    ].join ""

parseExJSON = (json) ->
    convert = (data) ->
        for k, v of data
            if v and v.type is "__regexp"
                data[k] = new RegExp v.source, v.flags
            else if typeof v is "object"
                convert v
        data

    data = JSON.parse json
    convert data

gzip = RSVP.denodeify zlib.gzip
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

module.exports.Pipeline = class Pipeline extends EventEmitter
    @sigintInstalled: false
    @instances: []
    pipes: {}

    constructor: (@logger, @cfg) ->
        @config = @cfg.getPipelineConfig()

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

    readFile: RSVP.denodeify fs.readFile
    gunzip: RSVP.denodeify zlib.gunzip
    unlink: RSVP.denodeify fs.unlink

    # load cached state
    loadState: ->
        if @config.bungle.reset
            @unlink ".bungle.state"
            .catch ->
                null
            .then =>
                hash:@config.hash
        else
            @readFile ".bungle.state"
            .then (compressed) =>
                @gunzip compressed
            .then (data) =>
                state = parseExJSON data
                if state.hash is @config.hash
                    state
                else
                    hash:@config.hash
            .catch (err) =>
                @log "info", "Previous state could not be loaded"
                hash:@config.hash

    createPipes: ->
        for id, pipeconfig of @config.pipes
            # get state and prototype
            pipestate = @state[id] || {}
            PipeClass = @cfg.pipes[pipeconfig.type]

            @pipes[id] = new PipeClass pipeconfig, pipestate, @

        # call init and continue when all pipes are done
        RSVP.all (pipe.init() for _, pipe of @pipes)
        .then =>
            # connect inputs of all pipes
            for id, pipeconfig of @config.pipes
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
        state = { hash: @config.hash }
        state[id] = pipe.state for id, pipe of @pipes

        @log "info", "Saving state"
        RSVP.all (pipe.stop() for _, pipe of @pipes)
        .then ->
            gzip JSON.stringify(state)
        .then (data) ->
            writeFile ".bungle.state", data
        .then =>
            @log "info", "Pipeline shutdown complete"

    broadcast: (req) ->
        RSVP.all Object.keys(@pipes).map (id) =>
            @pipes[id].broadcast req

    log: (level, args...) ->
        @logger.log level, "pipeline", args...
