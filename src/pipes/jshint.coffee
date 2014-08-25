path = require "path"

jslint = require("jshint").JSHINT

{BasePipe} = require "../pipe"

module.exports = class ExtPipe extends BasePipe
    @schema: ->
        description: "Hint JavaScript resources."

    @configDefaults:
        pattern: "**/*.js"

    @stateDefaults:
        broken: []
        jshintrcs: {}

    init: ->
        if not /\.jshintrc/.test @config.pattern
            @config.pattern = "{#{@config.pattern},**/.jshintrc}"

    findHints: (pathname) ->
        dirname = path.dirname pathname
        if @state.jshintrcs[dirname]
            @state.jshintrcs[dirname]
        else if dirname
            @findHints dirname
        else
            {}

    add: (file) ->
        file.add = true
        super file

    change: (file) ->
        if /\.jshintrc$/.test file.name
            # keep all jshintrcs
            try
                dir = path.dirname file.name
                @state.jshintrcs[dir] = JSON.parse file.content
            catch e
                @log "error", "Could not parse: #{file.name} #{e}"
        else
            # find correct jshintrc
            hints = @findHints file.name

            # perform linting
            lintok = jslint file.content, hints
            if not lintok
                e = jslint.errors[0]
                @state.broken.push file.name if file.name not in @state.broken
                @log "error", "BROKEN #{file.name}\nLine #{e.line}: #{e.reason}"
            else
                if file.name in @state.broken
                    @state.broken.pop file.name
                    @log "info", "FIXED #{file.name}"
        super file
