RSVP = require "rsvp"

{CompileInputListPipe} = require "../pipe"

module.exports = class ExtPipe extends CompileInputListPipe
    @schema: ->
        description: "Detect Ember resources and create application module."
        properties:
            filename:
                description: "Filename of the compiled module"
                type: "string"
        required: ["filename"]

    @configDefaults:
        pattern: "**/*.js"

    sanitize: (f) -> f.replace /\.js$/, ""

    entities: [
        "adapters"
        "components"
        "controllers"
        "helpers"
        "initializers"
        "mixins"
        "models"
        "routers"
        "routes"
        "serializers"
        "templates"
        "transforms"
        "views"
        "pods"
    ]

    init: ->
        @valid = new RegExp "^#{@entities.join "|"}$"

    getFileContent: ->
        @log "debug", "#C# #{@config.filename}" if @config.debug

        results = []
        objects = []

        for pathname in @state.files.sort()
            pathname = @sanitize pathname
            parts = pathname.split("/")
            continue if not @valid.test parts[0]

            if parts[0] is "pods"
                type = parts.pop().replace /([a-z])(.*)/,
                    ($0,$1,$2) -> $1.toUpperCase()+$2
                dashedname = parts[1..].join "-"
                camelcasename = dashedname.replace /(^|\-)([a-z])/g,
                    ($1) -> $1.toUpperCase().replace("-", "")
            else
                type = parts[0].replace /([a-z])(.*)s/,
                    ($0,$1,$2) -> $1.toUpperCase()+$2

                dashedname = parts[1..].join "-"
                camelcasename = dashedname.replace /(^|\-)([a-z])/g,
                    ($1) -> $1.toUpperCase().replace("-", "")

            modname = "#{camelcasename}#{type}"

            results.push "import #{modname} from \"./#{pathname}\";"
            objects.push "#{modname}"
        results.push "var App = {"
        results.push ("  #{i}: #{i}" for i in objects).join ",\n"
        results.push "};"
        results.push "export default App;"

        RSVP.Promise.resolve results.join "\n"

    compile: ->
        @fileChange @config.filename
