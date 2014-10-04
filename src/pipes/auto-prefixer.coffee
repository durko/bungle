autoprefixer = require "autoprefixer"

{BasePipe} = require "../pipe"

module.exports = class ExtPipe extends BasePipe
    @schema: ->
        description: "Add vendor prefixes to css."
        properties:
            browsers:
                description: """
                    Browser versions to support (default: ["last 2 versions"])
                """
                type: "array"
                items:
                    type: "string"
                    minItems: 1
                    uniqueItems: true

    @configDefaults:
        pattern: "**/*.css"
        browsers: ["last 2 versions"]

    init: ->
        @ap = autoprefixer.apply @, browsers: @config.browsers

    change: (file) ->
        css = @ap.process(file.content).css
        super @modifyFile file, "content", css
