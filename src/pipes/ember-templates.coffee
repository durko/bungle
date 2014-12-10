vm = require "vm"

RSVP = require "rsvp"

{CompileInputDataPipe} = require "../pipe"

module.exports = class ExtPipe extends CompileInputDataPipe
    @schema: ->
        description: """
            Precompile Handlebars and Emblem templates for an Ember app.
        """
        properties:
            filename:
                description: "Filename of the compiled module"
                type: "string"
        required: ["filename"]

    @configDefaults:
        pattern: "**/*.emblem"

    @stateDefaults:
        vendor: {}

    init: ->
        if @state.vendor.emblem
            p = RSVP.Promise.resolve()
        else
            p = @pipeline.broadcast
                type: "getVendorVanillaPackages"
                packages: {
                    "handlebars": []
                    "ember": ["ember-template-compiler.js"]
                    "emblem": []
                }
            .then (res) =>
                @log "verbose", "Got vanilla vendor packages"

                res = (r for r in res when r)[0]

                @state.vendor.handlebars = res.handlebars[0].toString "utf8"
                @state.vendor.ember = res.ember[0].toString "utf8"
                @state.vendor.emblem = res.emblem[0].toString "utf8"

        p.then =>
            @context = vm.createContext {}
            @context.window = @context

            try
                v = @state.vendor
                @log "verbose", "loading handlebars"
                vm.runInContext v.handlebars, @context, "handlebars.js"
                @log "verbose", "loading emblem"
                vm.runInContext v.emblem, @context, "emblem.js"
                @log "verbose", "loading ember"
                ember_src = v.ember.replace /exports/g, "this"
                vm.runInContext ember_src, @context, "ember.js"
            catch e
                @log "error", "Could not initialize compile environemnt: #{e}"
                @log "error", e.stack
                @context = null
            super()

    unprefix: (f) ->
        f
        .replace(/\.emblem$/, "")
        .replace(/[\./]*/, "")

    valid: /^(templates|pods)$/

    getFileContent: ->
        @log "debug", "#C# #{@config.filename}" if @config.debug

        results = [ """
            import Em from "vendor/ember";
            var T=Em.TEMPLATES, t=Em.Handlebars.template;
            export default T;
        """ ]

        compile = "
            var options = {
                knownHelpers: {
                    action: true,
                    unbound: true,
                    'bind-attr': true,
                    template: true,
                    view: true,
                    _triageMustache: true
                },
                data: true,
                stringParams: true
            };
            Emblem.handlebarsVariant = EmberHandlebars;
            ast = Emblem.parse(template);
            environment = new EmberHandlebars.Compiler().compile(ast, options);
            compiler = new EmberHandlebars.JavaScriptCompiler();
            js = compiler.compile(environment, options, undefined, false);
        "

        for pathname, src of @state.files
            pathname = @unprefix pathname
            parts = pathname.split "/"
            continue if not @valid.test parts[0]

            if parts[0] is "pods"
                type = parts.pop()
                if type is "component"
                    parts[0] = "components"
                    key = parts.join "/"
                else if type is "template"
                    parts.shift()
                    key = parts.join "/"
                else
                    continue
            else
                key = parts[1..].join "/"

            try
                @context.template = Buffer(src).toString()
                vm.runInContext compile, @context

                results.push "T[\"#{key}\"] = t(#{@context.js});\n"
            catch e
                @log "error", "ParserError: #{e.toString()}"
                @log "error", e.stack

        RSVP.Promise.resolve results.join ""

    compile: ->
        @fileChange @config.filename
