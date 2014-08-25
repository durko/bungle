fs = require "fs"
path = require "path"

mkdirp = require "mkdirp"
RSVP = require "rsvp"

{BasePipe} = require "../pipe"

mkdirp = RSVP.denodeify mkdirp
writeFile = RSVP.denodeify fs.writeFile
unlink = RSVP.denodeify fs.unlink


module.exports = class ExtPipe extends BasePipe
    @schema: ->
        description: "Write files to disk."

    add: (file) ->
        file.add = true
        super file

    change: (file) ->
        mkdirp path.dirname(file.name)
        .then ->
            writeFile file.name, file.content
        .then =>
            super file

    unlink: (file) ->
        unlink file.name
        .catch (err) =>
            @log "error", "Could not delete #{file.name} #{err}"
        .then ->
            super file
