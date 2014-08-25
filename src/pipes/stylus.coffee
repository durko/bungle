stylus = require "stylus"
nib = require "nib"
RSVP = require "rsvp"

{BasePipe} = require "../pipe"

module.exports = class ExtPipe extends BasePipe
    @schema: ->
        description: "Compile Stylus resources to css."

    @configDefaults:
        pattern: "**/*.styl"

    rename: (name) -> name.replace /styl$/, "css"

    change: (file) ->
        func = RSVP.denodeify (cb) ->
            stylus(file.content).use(nib()).render cb
        func()
        .catch (err) ->
            @log "error", "BROKEN #{file.name}\nError: #{err}"
        .then (css) =>
            super @changeHelper file, css
