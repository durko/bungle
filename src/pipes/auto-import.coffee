path = require "path"

{CompileInputListPipe} = require "../pipe"

module.exports = class ExtPipe extends CompileInputListPipe
    @schema: ->
        description: """
            Create module that automatically imports all other modules.
        """
        properties:
            filename:
                description: "Filename of the compiled module"
                type: "string"
        required: ["filename"]

    @configDefaults:
        pattern: "**/*.js"

    sanitize: (f) -> f.replace /\.js$/, ""

    compile: ->
        modules = []
        for pathname in @state.files.sort()
            pathname = @sanitize pathname

            id = pathname.replace /[\/-]/g, "_"
            src = "./#{path.relative (path.dirname @config.filename), pathname}"
            modules.push "import #{id} from \"#{src}\";"
        modules.push "export default 0;"
        @fileChange @config.filename, modules.join "\n"
