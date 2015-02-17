RSVP = require "rsvp"

{BasePipe} = require "../pipe"

module.exports = class ExtPipe extends BasePipe
    @schema: ->
        description: "Compile HTMLBars to Javascript"

    @configDefaults:
        pattern: "**/*.hbs"

    @stateDefaults:
        compiler: null

    init: ->
        if @state.compiler
            p = RSVP.Promise.resolve()
        else
            p = @pipeline.broadcast
                type: "getVendorVanillaPackages"
                packages: {
                    "ember": ["ember-template-compiler.js"]
                }
            .then (res) =>
                @log "verbose", "Got ember template compiler"
                res = (r for r in res when r)[0]
                @state.compiler = res.ember[0].toString "utf8"

        p.then =>
            compiler = new module.constructor()
            compiler.paths = module.paths
            compiler._compile @state.compiler, "ember-template-compiler.js"

            @compiler = compiler.exports
            super()

    rename: (name) -> name.replace /hbs$/, "js"

    change: (file) ->
        try
            compiled = @compiler.precompile file.content.toString(), false
            js = "
                import Em from \"ember\";
                export default Em.HTMLBars.template(#{compiled});
            "
        catch e
            e.filename = file.name
            @log "error", "CompilerError: #{e.toString()}"
        super @modifyFile file, "content", js

