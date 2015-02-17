fs = require "fs"
path = require "path"

{Config} = require "./config"
{Logger} = require "./logger"
{Pipeline} = require "./pipeline"



class Runner
    constructor: ->
        @pipes = {}

    loadPipes: (names) ->
        extexp = /\.(js|coffee)$/
        ext = module.filename.replace /.*\./, ""
        pipesdir = path.join __dirname, "pipes"

        if not names
            names = fs
                .readdirSync pipesdir
                .filter (f) -> extexp.test f
                .map (f) -> f.replace extexp, ""

        for name in names
            filename = path.resolve pipesdir, name

            if not fs.existsSync "#{filename}.#{ext}"
                console.log "Error: Pipe #{name} does not exist"
                return null

            @pipes[name] = require path.resolve filename if not @pipes[name]

        @pipes

    run: (config) ->
        pipes = config?.pipes || {}
        names = (meta.type for _, meta of pipes when meta.enabled isnt false)
        pipeModules = @loadPipes names
        return if not pipeModules

        # create singleton logger instance
        @log = new Logger config?.bungle?.logger || {}

        # create config instance
        @cfg = new Config config, @log, @pipes
        if not @cfg.ok
            return null

        # spawn pipeline with config
        @pipeline = new Pipeline @log, @cfg



module.exports.Runner = Runner

