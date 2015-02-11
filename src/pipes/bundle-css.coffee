path = require "path"

css = require "css"
mime = require "mime"

{CompileInputDataPipe} = require "../pipe"

module.exports = class ExtPipe extends CompileInputDataPipe
    @schema: ->
        description: "Bundle CSS, fonts and images into one css file."
        properties:
            main:
                description: "Entry point module of the bundle"
                type: "string"
            filename:
                description: "Filename of the bundle"
                type: "string"
        required: ["main", "filename"]

    @configDefaults:
        pattern: "**/*.{css,eot,svg,ttf,woff}"
        baseUrl: ""
        main: "style.css"
        filename: "main-built.css"

    rebaseUrl: (rules, from, to) ->
        regex = /(url\()([^)]+)(\))/g
        replaceUrl = (oldpath, p1, p2, p3) ->
            quote = ""
            if /^("|')/.test p2
                quote = p2[0]
                p2 = p2.substr 1, p2.length-2

            if not /data:/.test p2
                p2 = path.relative to, (path.normalize path.join from, p2)
            p1+quote+p2+quote+p3

        for rule in rules
            @rebaseUrl rule.rules, from, to if rule.rules
            continue if not rule.declarations

            for decl in rule.declarations
                continue if not /url/.test decl.value

                decl.value = decl.value.replace regex, replaceUrl

    loadRecursively: (pathname) ->
        dir = path.dirname pathname
        ast = css.parse @state.files[pathname]||""
        rules = ast.stylesheet.rules
        skiplist = []
        while 1
            impRule = null
            for rule in rules
                if rule.type is "import" and rule.import not in skiplist
                    impRule = rule

            break if not impRule

            if /^("|')/.test impRule.import
                impName = JSON.parse impRule.import
            else
                impName = impRule.import.replace /.*\("([^)]+)"\).*/, "$1"

            impRules = null
            for name of @state.files
                if path.relative(dir, name) is impName
                    impRules = @loadRecursively(name).stylesheet.rules
                    @rebaseUrl impRules, path.dirname(name), dir
                    break

            if impRules
                impRules.unshift 1
                impRules.unshift rules.indexOf impRule
                rules.splice.apply rules, impRules
            else
                skiplist.push impRule.import

        if skiplist.length
            @log "error", "Could not embed #{skiplist}"

        for rule in rules
            continue if not rule.declarations
            for decl in rule.declarations
                continue if decl.property isnt "src"
                value = decl.value.replace /\n/g, ""
                remUrl = new RegExp "^((?!url\\\().)*url\\\( *"
                while /url\(/.test value
                    value = value.replace remUrl, ""
                    d = value.match /^([""])/
                    continue if not d

                    d = d[1]
                    nameEx = new RegExp "^#{d}([^#{d}]*)#{d} *\\\)"
                    name = value.match nameEx
                    continue if not name

                    name = name[1]
                    filename = name.replace /(#|\?).*$/, ""
                    filename = path.normalize path.join dir, filename
                    if @state.files[filename]
                        data = @state.files[filename].toString("base64")
                        nameEx = "#{d}#{name}#{d}"
                        data = """
                            "data:#{mime.lookup(filename)};base64,#{data}"
                        """
                        decl.value = decl.value.replace nameEx, data
        ast

    compile: ->
        try
            ast = @loadRecursively @config.main
            olddir = path.dirname @config.main
            newdir = path.dirname @config.filename
            @rebaseUrl ast.stylesheet.rules, olddir, newdir

            @fileChange @config.filename, css.stringify ast
        catch e
            @log "error", "Error occured in bungle-css #{e} #{e.stack}"
