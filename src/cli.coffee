fs = require "fs"
path = require "path"
commander = require "commander"

{Runner} = require "./runner"



list = (val) -> val.split ","

clone = (obj) ->
    return obj if obj is null or typeof obj isnt "object"

    o = obj.constructor()
    o[key] = clone obj[key] for key of obj
    o

merge = (o, n) ->
    o = clone o
    n = clone n
    f = (o, n) ->
        for k, v of n
            if k is "*"
                f o[k2], clone v for k2 of o
            else
                if o[k] is null or typeof o[k] isnt "object"
                    o[k] = v
                else
                    f o[k], v
        o
    f o, n



class Cli
    constructor: (argv=process.argv) ->
        @runner = new Runner()

        @args = commander
        .version require(path.join __dirname, "..", "package.json").version
        .usage "[options] <profile>"
        .option "-c, --checkconfig", "validate config file"
        .option "-D, --debug", "enable debug output"
        .option "-e, --enable <pipe[,pipe]>", "enable pipes", list, []
        .option "-d, --disable <pipe[,pipe]>", "disable pipes", list, []
        .option "-r, --reset", "reset all bungle caches"
        .option "-L, --listpipes", "show list available pipes"
        .option "-H, --pipehelp <pipe|all>", "show help for pipe", list
        .parse argv

        null

    listprofiles: (profiles, current) ->
        console.log "Profiles:"
        for name, profile of profiles
            indicator = if name is current then "*" else " "
            padded = "#{name}#{Array(20-name.length).join " "}"
            console.log "    #{indicator} #{padded}#{profile.description}"
        console.log ""

    listpipes: ->
        pipes = @runner.loadPipes null
        console.log "Available pipes:"
        for id, pipe of pipes
            padded = "#{id}#{Array(25-id.length).join " "}"
            description = (pipe.schema().description.split "\n")[0]
            console.log "    #{padded}#{description}"

    pipehelp: (pipes) ->
        pipes = @runner.loadPipes if "all" in pipes then null else pipes
        for name, pipe of pipes
            schema = pipe.schema()
            console.log "\n#{name}\n#{Array(name.length+1).join "="}\n"
            console.log schema.description
            console.log "\nOptions (*=required)\n--------------------"
            for attr in (Object.keys schema.properties||{}).sort()
                continue if attr is "pipe"
                prop = schema.properties[attr]

                if prop.type is "array"
                    type = "array of #{prop.items.type}s"
                else
                    type = prop.type

                req = if attr in (schema.required || []) then "* " else "  "
                attr = "#{attr}#{Array(16-attr.length).join " "}"
                type = "#{type}#{Array(20-attr.length).join " "}"
                console.log "#{req}#{attr}#{type}#{prop.description}"
            console.log "\n"

    run: ->
        if @args.listpipes
            @listpipes @args.listpipes
        else if @args.pipehelp
            @pipehelp @args.pipehelp
        else
            @rundir = process.cwd()
            config = @load @rundir
            return if not config
            config.bungle ?= {}
            config.pipes ?= {}
            config.profiles ?= {}

            cliConfig =
                reset: !!@args.reset
                checkconfig: !!@args.checkconfig
                logger: {}
            cliConfig.logger.console = "debug" if @args.debug
            bungle = merge config.bungle, cliConfig

            profileName = @args.args[0] || "default"
            profile = config.profiles[profileName]
            if not profile
                console.log "Profile #{profileName} does not exist"
                return
            pipes = merge config.pipes, profile.config

            for id, pipeconfig of pipes
                # disable pipes if requested in config or on commandline
                disableViaCfg = pipeconfig.enabled is false
                disableViaCmd = id in @args.disable
                enableViaCmd = id in @args.enable
                if disableViaCfg or disableViaCmd and not enableViaCmd
                    pipes[id].enabled = false

            @config =
                bungle: bungle
                pipes: pipes
                profiles: config.profiles

            @runner.run @config

    load: (dir) ->
        configfile = path.join dir, "bungle.json"
        if fs.existsSync configfile
            data = fs.readFileSync configfile, "utf8"
            try
                config = JSON.parse data
            catch err
                console.log "Cannot parse bungle.json: #{err.message}"
                return null
            process.chdir dir
            config
        else
            dir = path.dirname dir
            if not dir
                console.log "Cannot find a bungle.json config file"
            @load dir



module.exports.Cli = Cli

