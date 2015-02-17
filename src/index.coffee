{Cli} = require "./cli"
{Builder} = require "./builder"

module.exports.Builder = Builder

if require.main is module
    new Cli().run()

