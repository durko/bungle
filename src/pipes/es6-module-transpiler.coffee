esprima = require "esprima"
escodegen = require "escodegen"
recast = require "recast"
RSVP = require "rsvp"
{transpileAST} = require "esx-transpile"

{BasePipe} = require "../pipe"



module.exports = class ExtPipe extends BasePipe
    @schema: ->
        description: "Transpile modules written in ES6 syntax to AMD."
        properties:
            sourceMap:
                description: "Enable source maps (default: false)"
                type: "boolean"
            strict:
                description: """
                    Enable strict mode in transpiled modules (default: false)
                """
                type: "boolean"

    @configDefaults:
        pattern: "**/*.js"

    import: /^\s*import\s+./m
    export: /^\s*export\s+(\{|\*|var|class|function|default)/m
    module: /^\s*module\s+("[^"]+"|'[^']+')\s*\{/m

    change: (file) ->
        src = file.content

        if @export.test(src) or @import.test(src) or @module.test(src)
            RSVP.Promise.resolve file.content
            .then (source) ->
                # get ast for source
                #recast.parse source, esprima:esprima
                esprima.parse source
            .then (ast) ->
                # perform conversion on ast
                transpileAST ast
            .then (amdAst) ->
                # generate transpiled source
                #recast.print(amdAst).code
                escodegen.generate amdAst
            .catch (err) =>
                @log "error", "Error transpiling #{file.name}: #{err}"
            .then (content) =>
                super @modifyFile file, "content", content
        else
            super file
