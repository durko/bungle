handlebars = require "handlebars"

Pipe = require "../pipe"

module.exports = class ExtPipe extends Pipe.BasePipe
    @schema: ->
        description: "Compile templates (Handlebars) to html."
        properties:
            context:
                description: "Context to compile templates with (default: {})"
                type: "object"

    @configDefaults:
        pattern: "**/*.hbs"
        context: {}

    rename: (name) -> name.replace /\.hbs$/, ".html"

    change: (file) ->
        source = file.content.toString()
        template = handlebars.compile source
        content = new Buffer template @config.context
        super @changeHelper file, content
