{BasePipe} = require "../pipe"

module.exports = class ExtPipe extends BasePipe
    @schema: ->
        description: "Move files to other directory."
        properties:
            dir:
                description: "Target directory"
                type: "string"
        required: ["dir"]

    @configDefaults:
        pattern: "**/*"

    rename: (name) ->
        pathname = name.split "/"
        for segment in @config.dir.split("/")
            continue if segment is "."
            if segment is ".."
                pathname.shift()
            else
                pathname.unshift segment
        pathname.join "/"
