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
                packages: ["handlebars","ember","emblem"]
            .then (res) =>
                @log "verbose", "Got vanilla vendor packages"

                res = (r for r in res when r)[0]

                @state.vendor.handlebars = res[0][0].toString "utf8"
                @state.vendor.ember = res[1][0].toString "utf8"
                @state.vendor.emblem = res[2][0].toString "utf8"

        p.then =>
            jQuery = -> jQuery
            jQuery.jquery = "2.1.1"
            jQuery.event = { fixHooks: {} }

            element =
                appendChild: ->
                childNodes: [
                    { nodeValue: "Test:" },
                    null,
                    { nodeValue: 'Value' }
                ]
                firstChild: -> element
                innerHTML: -> element
                setAttribute: ->

            @context = vm.createContext
                document:
                    createElement: -> element
                jQuery: jQuery
            @context.window = @context

            try
                v = @state.vendor
                vm.runInContext v.handlebars, @context, "handlebars.js"
                vm.runInContext v.emblem, @context, "emblem.js"
                vm.runInContext v.ember, @context, "ember.js"
            catch
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

        compile = "js = Emblem.precompile(Em.Handlebars, template)"

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
                results.push "T[\"#{key}\"] = t(#{@context.js.toString()});\n"
            catch e
                @log "error", "ParserError: #{e.toString()}"

        RSVP.Promise.resolve results.join ""

    compile: ->
        @fileChange @config.filename
