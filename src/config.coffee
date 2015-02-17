crypto = require "crypto"
path = require "path"
tv4 = require "tv4"



serializeObject = (obj) ->
    type = (x) ->
        t = typeof x
        if t is "object"
            if x instanceof Array
                "array"
            else
                t
        else
            t

    encodeMap =
        boolean: (b) -> "b#{if b then 1 else 0}"
        string: (s) -> "#{s.length}:#{s}"
        number: (i) -> "i#{i}e"
        array: (a) -> "a#{(encode i for i in a).join ""}e"
        object: (o) -> "o#{
            ("#{encode i}#{encode o[i]}" for i in Object.keys(o).sort()).join ""
        }e"

    encode = (x) ->
        encodeMap[type x] x

    encode obj



class Config
    constructor: (@config, @logger, @pipes) ->
        for name, meta of @config.pipes
            if meta.enabled is false
                @config.pipes[name] = meta = type: "passthrough"
            delete meta.enabled

            meta.id = name
            meta.inputs ?= []
            for input in meta.inputs
                if not @config.pipes[input]
                    @log "error", "Pipe '#{name}' references an nknown input
                        pipe '#{input}'"
                    return ok: false

        if @config.bungle.checkconfig
            return ok: false if not @validate @pipes

        @ok = true
        @config.hash = crypto
            .createHash "sha1"
            .update require(path.join __dirname, "..", "package.json").version
            .update serializeObject @config.pipes
            .digest "hex"

        @log "verbose", "Config hash #{@config.hash}"

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
                    checkconfig: type: "boolean"
                    reset: type: "boolean"
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
        required: ["bungle", "pipes"]
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

    # validate config against schema
    validate: (pipes) ->
        fragments = @schema.properties.pipes.patternProperties["^.+$"].oneOf

        # extend base schema with pipe entries
        for id, pipe of pipes
            fragment = pipe.schema() || {}
            fragment.properties ?= {}
            fragment.properties[k] = v for k, v of @defaultFragmentProperties
            fragment.properties.type =
                description: id
                enum: [id]
            fragment.properties.id = type: "string"
            fragment.additionalProperties = false
            fragment.required ?= []
            fragment.required.push attr for attr in ["type"]
            fragments.push fragment

        config = @config
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
                    if fragment
                        tv4.validate pipe, fragment
                        dp = tv4.error.dataPath
                        @log "error", "Pipe validation: #{dataPath + dp}"
                        @log "error", tv4.error.message
                        return false
                    else
                        @log "error", "Pipe type unknown: #{pipe.type}"
                        @log "error", "Run 'bungle -L' to list known types"
                        return false
                else if subErrors.length > 0
                    # show non enum error
                    @log "error", "validation: #{subErrors[0].dataPath}"
                    @log "error", subErrors[0].message
                    return false
                else
                    # show parent oneOf error if enum did not match
                    @log "error", "validation: #{tv4.error.dataPath}"
                    @log "error", tv4.error.message
                    return false
            else
                # dataPath should be empty
                @log "error", "Top-level validation: #{tv4.error.dataPath}"
                @log "error", tv4.error.message
                return false

        @log "verbose", "Validation successful"
        validationStatus

    log: (level, args...) ->
        @logger.log level, "config", args...



module.exports.Config = Config

