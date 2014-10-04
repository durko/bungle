fs = require "fs"

RSVP = require "rsvp"
{Bower} = require "esx-bower"

{BasePipe} = require "../pipe"

readFile = RSVP.denodeify fs.readFile

module.exports = class ExtPipe extends BasePipe
    @schema: ->
        description: """
            Manage vendor resources with bower.
            Optionally convert resources to ES6 module syntax.
            Optionally manage requirejs config.
        """
        properties:
            offline:
                description: "Do not use internet connection. (default: false)"
                type: "boolean"
            patches:
                description: """
                    Source for patching legacy modules to es6. (default: "")
                """
                type: "string"

    @configDefaults:
        offline: false
        patches: ""

    @stateDefaults:
        esxbower: {}

    init: ->
        @bower = new Bower
            offline: @config.offline
            patches: @config.patches
            state: @state.esxbower

        @bower.on "installed", (pkg) =>
            @log "info", "Installed vendor package #{pkg.name}-#{pkg.version}"

        @bower.init()
        .then (res) =>
            @initialized = true
            if @afterInit
                @afterInit.forEach (f) -> f()
            res

    start: ->
        @state.directory = @bower.state.directory

        func = (name) =>
            @fileAdd name
            .then => @fileChange name

        super @bower.filenames().reduce (p, i) ->
            p.then -> func i
        , RSVP.Promise.resolve()

    getFileContent: (name) ->
        readFile name
        .then (content) =>
            if name is "#{@state.directory}/requirejs/require.js"
                config = JSON.stringify {"packages":@bower.pkgConfig()}, 0, 4
                content =
                    new Buffer """#{content}\nrequirejs.config(#{config});"""
            content
        .catch (err) =>
            @log "error", "Cannot read file #{name} #{err}"

    broadcast: (req) ->
        if not @initialized
            @afterInit ?= []
            new RSVP.Promise (resolve) =>
                @afterInit.push => resolve @broadcast req
        else if req.type is "getVendorVanillaPackages"
            RSVP.all req.packages.map (name) =>
                RSVP.all @bower.jsForPkg(name).map (file) ->
                    readFile file
        else if req.type is "getBowerConfig"
            @bower.pkgConfig()
