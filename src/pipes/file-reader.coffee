fs = require "fs"
path = require "path"

minimatch = require "minimatch"
RSVP = require "rsvp"
sane = require "sane"

{BasePipe} = require "../pipe"

readFile = RSVP.denodeify fs.readFile

module.exports = class ExtPipe extends BasePipe
    @schema: ->
        description: "Read files from disk."
        properties:
            basedir:
                description: "Source directory (default: \".\")"
                type: "string"
            continuous:
                description: """
                    Keep observing directory for changes (default: false)
                """
                type: "boolean"

    @configDefaults:
        basedir: "."
        continuous: false

    @stateDefaults:
        hashes: {}
        adds: []
        changes: []
        unlinks: []

    matches: (p) ->
        minimatch p, @config.pattern

    getFileContent: (name) ->
        readFile path.join @config.basedir, name
        .catch (err) =>
            @log "error", "Could not read", name

    start: ->
        super new RSVP.Promise (resolve, reject) =>
            @watcher = sane @config.basedir, [@config.pattern],
                persistent: @config.continuous

            @watcher.on "ready", =>
                files = []
                for dir, filenames of @watcher.dirRegistery
                    files = files.concat Object.keys(filenames).map (n) =>
                        fullpath = path.join dir, n
                        path.relative @config.basedir, fullpath

                # filter out directories
                base = path.resolve @config.basedir
                files = files.filter (f) =>
                    not @watcher.watched[path.join base, f]

                func = (name) =>
                    if @matches name
                        @fileAdd name
                        .then =>
                            @fileChange name

                # emit files in order
                files.reduce (p, i) ->
                    p.then -> func i
                , RSVP.Promise.resolve()
                .then -> resolve()

                # emit out of order
                ###
                RSVP.all files.map (f) -> func f
                ###

            @watcher.on "add", (filepath, root, stat) =>
                return if stat.isDirectory()
                if @matches filepath
                    @fileAdd filepath
                    .then => @fileChange filepath

            @watcher.on "change", (filepath, root, stat) =>
                if @matches filepath
                    @fileChange filepath

            @watcher.on "delete", (filepath, root, stat) =>
                if @matches filepath
                    @fileUnlink filepath

    stop: ->
        @watcher.close() if @config.continuous
