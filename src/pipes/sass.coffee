path = require "path"

sass = require "node-sass"
RSVP = require "rsvp"

{DependsPipe} = require "../pipe"

module.exports = class ExtPipe extends DependsPipe
    @schema: ->
        description: "Compile .scss resources to css."

    @configDefaults:
        pattern: "**/*.scss"

    rename: (name) -> name.replace /scss$/, "css"

    dependenciesFor: (name) ->
        content = @state.files[name].toString()
        dirname = path.dirname name

        imports = content.match /@import "(.*)";/g
        return [] if not imports
        imports.map (s) ->
            name = s.replace /@import "(.*)";/, "$1"
            path.join dirname, name+".css"

    compile: (name) ->
        new RSVP.Promise (resolve, reject) =>
            content = @state.files[name].toString()
            ret = sass.renderSync
                file: name
                data: if content then content else "//"
                importer: (url, prev) =>
                    dirname = path.dirname prev
                    impname = path.join dirname, url+".css"
                    if @state.files[impname]
                        contents = @state.files[impname].toString()
                    else
                        contents = ""
                    contents: contents
            if ret.status > 0
                reject ret
            else
                resolve ret
        .catch (err) =>
            @log "error", "BROKEN #{name}\nError: #{err}"
            ""
        .then (result) =>
            if result
                @fileChange name, new Buffer result.css.toString()
