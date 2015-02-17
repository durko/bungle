chalk = require "chalk"
growl = require "growl"

levels =
    debug: 0
    verbose: 1000
    info: 2000
    warn: 3000
    error: 4000

formatedLevel =
    debug: chalk.green "debug"
    verbose: chalk.green "verbose"
    info: chalk.green "info"
    warn: chalk.red "warn"
    error: chalk.bgRed.white "error"



class Logger
    constructor: (config) ->
        @level =
            console: levels[config.console || "debug"]
            notify: levels[config.notify || "info"]

    log: (level, prefix, message)->
        if @level.console <= levels[level]
            console.log chalk.blue("bungle"),
                formatedLevel[level],
                chalk.yellow(prefix),
                message
        if @level.notify <= levels[level]
            growl message, { title: "Bungle #{level} #{prefix}" }



module.exports.Logger = Logger

