compiler = require "coffee-script"

{BasePipe} = require "../pipe"

module.exports = class ExtPipe extends BasePipe
    @schema: ->
        description: "Compile CoffeeScript to Javascript"

    @configDefaults:
        pattern: "**/*.coffee"

    rename: (name) -> name.replace /coffee$/, "js"

    change: (file) ->
        try
            js = new Buffer compiler.compile file.content.toString(), bare:true
        catch e
            e.filename = file.name
            @log "error", "CompilerError: #{e.toString()}"
        super @modifyFile file, "content", js
