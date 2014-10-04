compiler = require "uglify-js"

{BasePipe} = require "../pipe"

module.exports = class ExtPipe extends BasePipe
    @schema: ->
        description: "Compile CoffeeScript to Javascript"

    @configDefaults:
        pattern: "**/*.js"

    change: (file) ->
        code = compiler.minify(file.content, fromString:true).code
        super @modifyFile file, "content", code
