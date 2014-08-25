esprima = require "esprima"
escodegen = require "escodegen"
recast = require "recast"
RSVP = require "rsvp"
{Bundler} = require "esx-bundle"

{CompileInputDataPipe} = require "../pipe"

module.exports = class ExtPipe extends CompileInputDataPipe
    @schema: ->
        description: "Bundle AMD compliant js modules."
        properties:
            main:
                description: "Entry point module of the bundle"
                type: "string"
            filename:
                description: "Filename of the bundle"
                type: "string"
        required: ["main", "filename"]

    @configDefaults:
        pattern: "**/*.js"
        sourceMap: false

    @stateDefaults:
        esxbundle: {}

    init: ->
        @bundler = new Bundler
            main: @config.main
            out: @config.filename
            state: @state.esxbundle

        if @state.esxbundle.packages.length
            p = RSVP.Promise.resolve()
        else
            @pipeline.broadcast
                type: "getBowerConfig"
            .then (res) =>
                res = (r for r in res when r)[0]
                @log "verbose", "Got bower config"
                @bundler.setPackages res
        p

    change: (file) ->
        if @config.sourceMap
            ast = recast.parse(file.content, {esprima:esprima}).program
        else
            ast = esprima.parse file.content
        @bundler.setSourceFile file.name, ast
        super file

    compile: ->
        @log "debug", "#C#" if @config.debug
        try
            if @config.sourceMap
                code = recast.print(@bundler.bundle()).code
            else
                code = escodegen.generate @bundler.bundle()
            @fileChange @config.filename, code
        catch e
            @log "error", "#{e.message}"
