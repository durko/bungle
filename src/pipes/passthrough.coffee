{BasePipe} = require "../pipe"

module.exports = class ExtPipe extends BasePipe
    @schema: ->
        description: """
            A noop pipe.
            Can be used to split input stream based on file patterns.
        """
