crypto = require "crypto"
fs = require "fs"
path = require "path"

tv4 = require "tv4"

pipes =
    "auto-import": require "./pipes/auto-import"
    "auto-prefixer": require "./pipes/auto-prefixer"
    "bower": require "./pipes/bower"
    "bundle-amd": require "./pipes/bundle-amd"
    "bundle-css": require "./pipes/bundle-css"
    "coffee": require "./pipes/coffee"
    "ember-auto-import": require "./pipes/ember-auto-import"
    "ember-templates": require "./pipes/ember-templates"
    "es6-module-transpiler": require "./pipes/es6-module-transpiler"
    "file-reader": require "./pipes/file-reader"
    "file-writer": require "./pipes/file-writer"
    "jshint": require "./pipes/jshint"
    "move": require "./pipes/move"
    "passthrough": require "./pipes/passthrough"
    "stylus": require "./pipes/stylus"
    "template-compiler": require "./pipes/template-compiler"
    "uglify": require "./pipes/uglify"
    "webserver": require "./pipes/webserver"

clone = (obj) ->
    return obj if obj is null or typeof obj is "object"

    o = obj.constructor()
    o[key] = clone obj[key] for key in obj
    o



class Config
    constructor: ->

    schema:
        $schema: "http://json-schema.org/draft-04/schema#"
        id: "http://git.savensis.net/bungle-config-schema#"
        title: "Bungle"
        description: "Bungle pipeline configuration"
        type: "object"
        properties:
            bungle:
                description: "Bungle configuration section"
                type: "object"
                properties:
                    logger:
                        type: "object"
                        properties:
                            console:
                                type: "string"
                            notify:
                                type: "string"
                        additionalProperties: false
                    reset:
                        type: "boolean"
                additionalProperties: false
            hash:
                description: "Config file hash, added on the fly"
                type: "string"
            profiles:
                description: "Configuration profiles of the pipeline"
                type: "object"
                patternProperties:
                    "^.+$":
                        description: "Configuration profile instance"
                        type: "object"
                        properties:
                            description:
                                type: "string"
                                description: "Profile description shown in help"
                            config:
                                type: "object"
                                description: "Profile config"
                        required: ["description", "config"]
                        additionalProperties: false
                    additionalProperties: false
                additionalProperties: false
            pipes:
                description: "The pipe instances to create for this pipeline"
                type: "object"
                patternProperties:
                    "^.+$":
                        description: "Pipe instance config"
                        type: "object"
                        oneOf: []
        required: ["profiles", "pipes"]
        additionalProperties: false

    defaultFragmentProperties:
        description:
            description: "Description of the pipe's function in the pipeline"
            type: "string"
        pattern:
            description: "Input accept pattern"
            type: "string"
        passthrough:
            description: "Pass unaccepted inputs through pipe (default: true)"
            type: "boolean"
        enabled:
            description: "Enable this pipe (default: false)"
            type: "boolean"
        debug:
            description: "Verbose pipe operations (default: false)"
            type: "boolean"
        inputs:
            description: "Connect inputs to these pipes (default: [])"
            type: "array"
            items:
                type: "string"
                minItems: 1
                uniqueItems: true

    # load config from file
    load: ->
        pjson = require path.join __dirname, "..", "package.json"
        if fs.existsSync "bungle.json"
            data = fs.readFileSync "bungle.json", "utf8"
            try
                @config = JSON.parse data
            catch err
                console.log "bungle config error", err
                return null
            @config.hash = crypto
                .createHash("sha1")
                .update(pjson.version)
                .update(data)
                .digest("hex")

            return @config.hash
        else
            console.log "There is no bungle.json config file in", process.cwd()

    profile: "default"
    setProfile: (@profile) ->

    enable: []
    setEnable: (@enable) ->

    disable: []
    setDisable: (@disable) ->

    pipes: {}

    autodiscover: true

    # load pipes from directory
    loadPipes: ->
        if @autodiscover
            pipesdir = path.join __dirname, "pipes"
            files = fs.readdirSync pipesdir
                .filter (f) -> /\.(js|coffee)$/.test f

            for file in files
                filename = path.resolve (path.join pipesdir), file
                id = filename.replace /.*[/\\](.*)\.(coffee|js)/, "$1"
                mod = require path.resolve filename
                @pipes[id] = mod
        else
            @pipes = pipes
        @updateSchema()

    # create validation schema for config
    updateSchema: ->
        # extend base schema with pipe entries
        fragments = @schema.properties.pipes.patternProperties["^.+$"].oneOf
        for id, pipe of @pipes
            fragment = pipe.schema() || {}
            fragment.properties ?= {}
            fragment.properties[k] = v for k, v of @defaultFragmentProperties
            fragment.properties.type =
                description: id
                enum: [id]
            fragment.additionalProperties = false
            fragment.required ?= []
            fragment.required.push attr for attr in ["type"]
            fragments.push fragment

    # display available profiles, mark active profile in output
    showProfiles: ->
        console.log "Profiles:"
        for name, profile of @config.profiles
            indicator = if name is @profile then "*" else " "
            padded = "#{name}#{Array(20-name.length).join " "}"
            console.log "    #{indicator} #{padded}#{profile.description}"
        console.log ""

    # show list of pipes
    showPipes: ->
        console.log "Available pipes:"
        for id, pipe of @pipes
            padded = "#{id}#{Array(25-id.length).join " "}"
            description = (pipe.schema().description.split "\n")[0]
            console.log "    #{padded}#{description}"

    # show pipe help
    showPipeHelp: (pipes) ->
        pipes = Object.keys @pipes if "all" in pipes

        fragments = @schema.properties.pipes.patternProperties["^.+$"].oneOf
        for pipe in pipes
            if not @pipes[pipe]
                console.log "bungle config error", "Unknown pipe: #{pipe}"
                continue

            for fragment in fragments
                break if fragment.properties.type.enum[0] is pipe

            console.log "\n#{pipe}\n#{Array(pipe.length+1).join "="}\n"
            console.log fragment.description
            console.log "\nOptions (*=required)\n--------------------"
            for name in (Object.keys fragment.properties).sort()
                continue if name is "pipe"
                prop = fragment.properties[name]

                if prop.type is "array"
                    type = "array of #{prop.items.type}s"
                else
                    type = prop.type

                req = if name in fragment.required then "* " else "  "
                name = "#{name}#{Array(16-name.length).join " "}"
                type = "#{type}#{Array(20-type.length).join " "}"
                console.log "#{req}#{name}#{type}#{prop.description}"
            console.log "\n"

    # return config with merged profile config
    getMerged: ->
        config = clone @config
        profile = config.profiles[@profile]
        for key, val of profile.config
            [ pipeName, key ] = key.split "."
            if pipeName is "*"
                pipe[key] = val for id, pipe of config.pipes
            else
                pipe = config.pipes[pipeName]
                if not pipe
                    console.log "bungle config error", @name,
                        "Profile '#{@profile}':",
                        "trying to set key '#{key}'",
                        "on non-existing pipe '#{pipeName}'."
                pipe[key] = val
        config

    # validate config schema
    validate: ->
        cfgerr = (args...) ->
            #args = [config._name].concat args
            console.log "bungle config error", args...

        fragments = @schema.properties.pipes.patternProperties["^.+$"].oneOf

        for config in [@config, @getMerged()]
            validationStatus = tv4.validate config, @schema
            if validationStatus is false
                if tv4.error.code is 11
                    #oneOf failed, remove enum errrors
                    subErrors = tv4.error.subErrors.filter (e) -> e.code isnt 1
                    if subErrors.length > 1
                        # too many matches, find correct error message
                        dataPath = tv4.error.dataPath

                        # last part of dataPath is pipe id
                        id = tv4.error.dataPath.replace /.*\//, ""
                        pipe = config.pipes[id]

                        fragment = null
                        for f in fragments
                            if f.properties.type.enum[0] is pipe.type
                                fragment = f
                                break
                        console.log fragment
                        if fragment
                            tv4.validate pipe, fragment
                            dp = tv4.error.dataPath
                            cfgerr "Pipe validation error:", dataPath + dp
                            cfgerr tv4.error.message
                        else
                            cfgerr "Pipe type unknown:", pipe.type
                            cfgerr "Run 'bungle -L' to list known types"
                    else if subErrors.length > 0
                        # show non enum error
                        cfgerr "validation error:". subErrors[0].dataPath
                        cfgerr subErrors[0].message
                    else
                        # show parent oneOf error if enum did not match
                        cfgerr "validation error:", tv4.error.dataPath
                        cfgerr tv4.error.message
                else
                    # dataPath should be empty
                    cfgerr "Top-level validation error:", tv4.error.dataPath
                    cfgerr tv4.error.message
            return false if not validationStatus
        true

    # get pipeline config
    getPipelineConfig: ->
        config = @getMerged()

        for id, pipeconfig of config.pipes
            pipeconfig.id = id
            pipeconfig.inputs ?= []

            # make sure input pipes exist
            for input in pipeconfig.inputs
                if not config.pipes[input]
                    console.log "bungle config error", config._name,
                        "Pipe '#{id}' uses unknown input pipe '#{input}'."
                    return null

            # disable pipes if requested in config or on commandline
            disableViaCfg = pipeconfig.enabled is false
            disableViaCmd = id in @disable
            enableViaCmd = id in @enable
            if disableViaCfg or disableViaCmd and not enableViaCmd
                pipeconfig.type = "passthrough"
                pipeconfig.inputs = []
        config

    logger: ->
        @config?.bungle?.logger || {}

module.exports.Config = Config
