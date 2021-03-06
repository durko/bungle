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

    nameReq: "requirejs/require.js"
    nameEML: "es6-module-loader/dist/es6-module-loader-sans-promises.js"

    getFileContent: (name) ->
        readFile name
        .then (content) =>
            if name is "#{@state.directory}/#{@nameReq}"
                config = JSON.stringify {"packages":@bower.pkgConfig()}, 0, 4
                content =
                    new Buffer """#{content}\nrequirejs.config(#{config});"""
            else if name is "#{@state.directory}/#{@nameEML}"
                mods = for p in @bower.pkgConfig()
                    "System.paths['#{p.name}']='#{p.location}/#{p.main}.js';"
                content = new Buffer content + "\n" + mods.join "\n"
            content
        .catch (err) =>
            @log "error", "Cannot read file #{name} #{err}"

    broadcast: (req) ->
        if not @initialized
            @afterInit ?= []
            new RSVP.Promise (resolve) =>
                @afterInit.push => resolve @broadcast req
        else if req.type is "getVendorVanillaPackages"
            res = {}
            for pkg, names of req.packages
                res[pkg] = RSVP.all @bower.jsForPkg(pkg, names).map (file) ->
                    readFile file
            RSVP.hash res
        else if req.type is "getBowerConfig"
            @bower.pkgConfig()
