commander = require "commander"
RSVP = require "rsvp"
{Logger} = require "./logger"
{Config} = require "./config"
{Pipeline} = require "./pipeline"



# process command line
list = (val) -> val.split ","
commander
    .version "dev"
    .usage "[options] <profile>"
    .option "-c, --checkconfig", "validate config file"
    .option "-D, --debug", "enable debug output"
    .option "-e, --enable <pipe[,pipe]>", "enable pipes", list, []
    .option "-d, --disable <pipe[,pipe]>", "disable pipes", list, []
    .option "-r, --reset", "reset all bungle caches"
    .option "-L, --listpipes", "show list available pipes"
    .option "-H, --pipehelp <pipe|all>", "show help for pipe", list
    .parse process.argv



# load config and process command line arguments
cfg = new Config

cfg.load() || process.exit()
cfg.loadPipes()

if commander.listpipes
    cfg.showPipes()
    process.exit()

if commander.pipehelp
    cfg.showPipeHelp commander.pipehelp
    process.exit()

cfg.config.bungle ?= {}
cfg.config.bungle.reset = !!commander.reset

if commander.debug
    cfg.config.bungle.logger ?= {}
    cfg.config.bungle.logger.console = "debug"

cfg.setProfile commander.args[0] || "default"
cfg.setEnable commander.enable
cfg.setDisable commander.disable

if commander.checkconfig
    cfg.validate() || process.exit()



# create singleton logger instance
log = new Logger cfg



# install CTRL-C handler
setupSIGINT = ->
    shuttingDown = false
    process.on "SIGINT", ->
        if shuttingDown
            log.log "info", "process", "Force exiting ..."
            log.log "debug", "process", process._getActiveHandles()
            process.exit()
        else
            shuttingDown = true
            log.log "info", "process", "Shutting down gracefully ..."

            RSVP.all Pipeline.instances.map (pipeline) -> pipeline.cleanup()
            .then ->
                log.log "info", "process", "Bye"
                process.exit()

setupSIGINT()



# spawn pipeline with config
new Pipeline log, cfg
