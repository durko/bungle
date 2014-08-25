crypto = require "crypto"
minimatch = require "minimatch"
RSVP = require "rsvp"

clone = (obj) ->
    return obj if not obj? or typeof obj isnt 'object'
    newInstance = new obj.constructor()
    newInstance[key] = clone obj[key] for key of obj
    newInstance

cloned = (v) -> if typeof v is "function" then v.apply @ else clone v

class BasePipe
    @schema: -> {}

    @configDefaults:
        pattern: "**/*"

    @stateDefaults:
        localFiles: {}

    constructor: (@config, @state, @pipeline) ->
        @log "debug", "Pipe created" if @config.debug

        obj = @constructor
        while obj
            @config[k] ?= cloned v for k, v of obj.configDefaults
            @state[k] ?= cloned v for k, v of obj.stateDefaults
            obj = obj.__super__?.constructor

        @outputs = []


    init: -> null

    start: (res) -> res

    stop: -> null



    #### Helpers for modifications

    # Rename a file
    renameHelper: (file) ->
        if @rename
            nfile = {}
            for k, v of file
                nfile[k] = v

            if nfile.originalName is undefined
                nfile.originalName = file.name

            nfile.name = @rename file.name
            nfile
        else
            file

    # Change the content of a file
    changeHelper: (file, content, sourceMap) ->
        nfile = {}
        for k, v of file
            nfile[k] = v

        if nfile.originalContent is undefined
            nfile.originalContent = file.content

        nfile.content = content
        nfile



    #### Pipe local file management

    # Add a new file into the pipeline.
    fileAdd: (name) ->
        return RSVP.Promise.resolve() if @state.localFiles[name]

        file =
            name:name
            add:false
        BasePipe::add.call @, file
        .then (res) =>
            @state.localFiles[name] =
                name:name
                added:res.add
            res
        .catch (err) ->
            console.log err
            console.log err.stack

    # Message file change
    fileChange: (name, content) ->
        file = @state.localFiles[name]
        return if not file?.added

        if file.changing
            @state.localFiles[name].reread = true
            return
        file.changing = true

        if content is undefined
            p = @getFileContent name
        else
            p = RSVP.Promise.resolve content

        p
        .then (content) =>
            hash = crypto.createHash "sha1"
            hash.update content
            digest = hash.digest "hex"

            if digest isnt file.hash
                file.hash = digest
                file.content = content
                BasePipe::change.call @, file
            else
                null
        .then (res) =>
            file.changing = false
            if file.reread
                file.reread = false
                @fileChange name
            res
        .catch (err) ->
            console.log err
            console.log err.stack

    # Remove a file from the pipeline
    fileUnlink: (name) ->
        file = @state.localFiles[name]
        return if not file?.added

        BasePipe::unlink.call @, file
        .then (res) =>
            delete @state.localFiles[name]
            res
        .catch (err) ->
            console.log err
            console.log err.stack



    #### Interpipe communication

    # Process add from previous pipes
    _add_in: (file) ->
        if minimatch file.name, @config.pattern
            @log "debug", "A #{file.name}" if @config.debug
            @add @renameHelper file
        else if @config.passthrough
            BasePipe::add.call @, file
        else
            file

    # Relay add to subsequent pipes
    add: (file) ->
        p = RSVP.Promise.resolve file
        if @outputs.length
            RSVP.all @outputs.map (o) ->
                p.then (arg) -> o._add_in arg
            .then (res) ->
                res.reduce (p, file) ->
                    name:file.name
                    add:p.add||file.add
                , {}
        else
            p

    # Process change from previous pipes
    _change_in: (file) ->
        if minimatch file.name, @config.pattern
            @log "debug", "M #{file.name}" if @config.debug
            @change @renameHelper file
        else if @config.passthrough
            BasePipe::change.call @, file
        else
            file

    # Relay change to subsequent pipes
    change: (file) ->
        p = RSVP.Promise.resolve file
        if @outputs.length
            RSVP.all @outputs.map (o) ->
                p.then (arg) -> o._change_in arg
            .then (res) ->
                res.reduce (p, file) ->
                    if Array.isArray file
                        file.reduce (p, file) ->
                            p.push file if file not in p
                            p
                        , p
                    else
                        p.push file if file not in p
                    p
                , []
        else
            p

    # Process unlink from previous pipes
    _unlink_in: (file) ->
        if minimatch file.name, @config.pattern
            @log "debug", "D #{file.name}" if @config.debug
            @unlink @renameHelper file
        else if @config.passthrough
            BasePipe::unlink.call @, file
        else
            file

    # Relay unlink to subsequent pipes
    unlink: (file) ->
        p = RSVP.Promise.resolve file
        if @outputs.length
            RSVP.all @outputs.map (o) ->
                p.then (arg) -> o._unlink_in arg
            .then (res) ->
                res.reduce (p, file) ->
                    if Array.isArray file
                        file.reduce (p, file) ->
                            p.push file if file not in p
                            p
                        , p
                    else
                        p.push file if file not in p
                    p
                , []
        else
            p

    broadcast: (req) ->

    log: (level, args...) ->
        @pipeline.logger.log level, "#{@config.type}(#{@config.id})", args...



class CompileInputListPipe extends BasePipe
    @stateDefaults:
        files: []

    start: ->
        @started = true
        super @fileAdd(@config.filename).then => @compile()

    add: (file) ->
        file.add = true
        @state.files.push file.name
        @compile() if @started
        if @config.passthrough
            super file
        else
            file

    unlink: (file) ->
        @state.files.splice (@state.files.indexOf file.name), 1
        @compile() if @started
        if @config.passthrough
            super file
        else
            file



class CompileInputDataPipe extends BasePipe
    @stateDefaults:
        files: {}

    start: ->
        @started = true
        super @fileAdd(@config.filename).then => @compile()

    add: (file) ->
        file.add = true
        @state.files[file.name] = ""
        if @config.passthrough
            super file
        else
            file

    change: (file) ->
        @state.files[file.name] = file.content
        @compile() if @started
        if @config.passthrough
            super file
        else
            file

    unlink: (file) ->
        delete @state.files[file.name]
        @compile() if @started
        if @config.passthrough
            super file
        else
            file



module.exports.BasePipe = BasePipe
module.exports.CompileInputListPipe = CompileInputListPipe
module.exports.CompileInputDataPipe = CompileInputDataPipe
