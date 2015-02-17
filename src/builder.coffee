{Runner} = require "./runner"

class Builder
    constructor: ->
        @bungle = {}
        @pipes = {}
        @runner = new Runner

    pipe: (type, meta) ->
        num = (Object.keys(@pipes).filter (n) => @pipes[n].type is type).length
        name = "#{type}-#{num}"
        meta.name = name
        meta.type = type
        meta.inputs = []
        @pipes[name] = meta

        meta: meta
        to: (next) ->
            next.meta.inputs.push @meta.name
            next

    run: ->
        delete meta.name for name, meta of @pipes
        @runner.run
            bungle: @bungle
            pipes: @pipes



module.exports.Builder = Builder

