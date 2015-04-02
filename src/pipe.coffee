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

    # Clone file and modify property
    modifyFile: (file, key, value) ->
        nfile = {}
        for k, v of file
            nfile[k] = v

        __key = "__#{key}"
        if nfile[__key] is undefined
            nfile[__key] = file[key]

        nfile[key] = value
        nfile



    #### Pipe local file management

    # Add a new file into the pipeline.
    fileAdd: (name) ->
        return RSVP.Promise.resolve() if @state.localFiles[name]

        @log "debug", "LA #{name}" if @config.debug
        BasePipe::add.call @,
            name:name
            add:false
        .then (res) =>
            @state.localFiles[name] =
                name:name
                added:res.add
            res
        .catch (err) =>
            @log "error", err
            @log "error", err.stack

    # Message file change
    fileChange: (name, content) ->
        file = @state.localFiles[name]
        return if not file?.added

        @log "debug", "LC #{name}" if @config.debug
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
                sendfile = @modifyFile file, "content", content
                BasePipe::change.call @, sendfile
            else
                null
        .then (res) =>
            file.changing = false
            if file.reread
                file.reread = false
                @fileChange name
            res
        .catch (err) =>
            @log "error", err
            @log "error", err.stack

    # Remove a file from the pipeline
    fileUnlink: (name) ->
        file = @state.localFiles[name]
        return if not file?.added

        @log "debug", "LD #{name}" if @config.debug
        BasePipe::unlink.call @, file
        .then (res) =>
            delete @state.localFiles[name]
            res
        .catch (err) =>
            @log "error", err
            @log "error", err.stack



    #### Interpipe communication

    # Process add from previous pipes
    _add_in: (file) ->
        if minimatch file.name, @config.pattern
            @log "debug", "A #{file.name}" if @config.debug
            file = @modifyFile file, "name", @rename file.name if @rename
            @add file
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
            file = @modifyFile file, "name", @rename file.name if @rename
            @change file
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
            file = @modifyFile file, "name", @rename file.name if @rename
            @unlink file
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



class DependsPipe extends BasePipe
    @stateDefaults:
        depsFor: {}
        depsOn: {}
        files: {}
        backlog: {}

    _compile: (names) ->
        depsOn = @state.depsOn
        names.reduce (p, i) =>
            if Object.keys(depsOn[i]).length
                p
            else
                p
                .then => @fileAdd i
                .then => @compile i
        , RSVP.Promise.resolve()

    start: ->
        @started = true
        depsOn = @state.depsOn
        names = []
        for name of @state.backlog
            delete @state.backlog[name]
            names.push name if not Object.keys(depsOn[name]).length
        @_compile names

    add: (file) ->
        file.add = true
        @state.depsFor[file.name] = {}
        @state.depsOn[file.name] = {}
        @state.files[file.name] = new Buffer ""

        depsOn = @state.depsOn[file.name]
        for name, deps of @state.depsFor
            depsOn[name] = true if deps[file.name]

        if @started
            if Object.keys(depsOn).length
                file
            else
                @fileAdd file.name
        else
            @state.backlog[file.name] = true
            file

    change: (file) ->
        @state.files[file.name] = file.content
        deps = @dependenciesFor file.name
        old = @state.depsFor[file.name]
        @state.depsFor[file.name] = {}
        for dep in deps
            @state.depsFor[file.name][dep] = true
        deps = @state.depsFor[file.name]

        add = []
        unlink = []
        for dep of old
            # obsolete dep
            if not deps[dep]
                c = @state.depsOn[dep]
                if c
                    delete c[file.name]
                    add.push dep

        for dep of deps
            # new dep
            if not old[dep]
                c = @state.depsOn[dep]
                if c
                    c[file.name] = true
                    unlink.push dep

        promise = unlink.reduce (p, i) =>
            p.then => @fileUnlink i
        , RSVP.Promise.resolve()

        if @started
            promise = promise.then => @_compile add
        else
            for name in add
                @state.backlog[name] = true

        promise.then =>
            if @started
                depsOn = @state.depsOn[file.name]
                if Object.keys(depsOn).length
                    @_compile Object.keys depsOn
                else
                    @_compile [file.name]
            else
                @state.backlog[file.name] = true
                file

    unlink: (file) ->
        deps = @state.depsFor[file.name]
        delete @state.depsFor[file.name]
        delete @state.depsOn[file.name]
        delete @state.files[file.name]
        delete @state.backlog[file.name]

        add = []
        for dep of deps
            depsOn = @state.depsOn[dep]
            delete depsOn[file.name]
            add.push dep

        if @started
            @_compile add
            .then =>
                @fileUnlink file.name
        else
            for name in add
                @state.backlog[name] = true
            @fileUnlink file.name



module.exports.BasePipe = BasePipe
module.exports.CompileInputListPipe = CompileInputListPipe
module.exports.CompileInputDataPipe = CompileInputDataPipe
module.exports.DependsPipe = DependsPipe
