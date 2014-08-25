http = require "http"
https = require "https"
fs = require "fs"
express = require "express"
mime = require "mime"
path = require "path"
sio = require "socket.io"
url = require "url"
minimatch = require "minimatch"

RSVP = require "rsvp"

{BasePipe} = require "../pipe"

reload = (pattern) ->
    script = """
        <script type="text/javascript" src="/socket.io/socket.io.js"></script>
        <script type="text/javascript">
        (function() {
            var d = document,
                h = d.getElementsByTagName("head")[0],
                origin = window.location.href.split("/").slice(0, 3),
                hostport = origin[2].split(":");

            hostport[1] = parseInt(hostport[1], 10) + 1;
            origin[2] = hostport.join(":");
            io.connect(origin.join("/"))
            .on("reconnect", function() { location.reload(); })
            .on("page", function() { location.reload(); })
            .on("css", function() {
                var links = d.getElementsByTagName("link"),
                    date = new Date().valueOf();
                for (var i=0; i<links.length; i++) {
                    var tag = links[i];
                    if (/stylesheet/i.test(tag.rel) && tag.href) {
                        var href = tag.href.replace(/(&|\\?)\\d+/, ""),
                            query = (~href.indexOf("?")?"&":"?") + date;
                        tag.href = href + query;
                    }
                }
            });
        })();
        </script>
    """

    return (req, res, next) ->
        return next() if not minimatch req.path.split("/").pop(), pattern

        write = res.write
        end = res.end
        res.write = (string, encoding) ->
            body = string.toString encoding
            body = body.replace /<head>/, "<head>"+script
            string = Buffer(body, encoding)
            write.call res, string, encoding

        res.end = (string, encoding) ->
            end.call res, string, encoding
            res.write = write
            res.end = end

        res.on "header", ->
            res.removeHeader "Content-Length"

        next()

memory = (files) ->
    dirlisting = """
        <!DOCTYPE html>
        <html>
            <head>
                <meta charset="utf-8">
                <title>listing directory {directory}</title>
                <style>
                    body {
                      margin: 0;
                      padding: 80px 100px;
                      font-family: "Helvetica Neue", "Lucida Grande", "Arial";
                      background-image: linear-gradient(#fff, #ece9e9);
                      background-repeat: no-repeat;
                      color: #555;
                      -webkit-font-smoothing: antialiased;
                    }
                    h1 {
                      margin: 0 0 18px 0;
                      font-size: 36px;
                      color: #343434;
                    }
                    a {
                      color: #555;
                      text-decoration: none;
                    }
                    a:hover {
                      *color: #303030;
                      color: #49607E;
                      background: #DCD9D9;
                    }
                    a.dir {
                      display: block;
                    }
                </style>
            </head>
            <body>
                <h1>{segments}</h1>
                {files}
            </body>
        </html>
    """

    return (req, res, next) ->
        return next() if req.method not in [ "GET", "HEAD" ]

        originalUrl = url.parse req.originalUrl
        pathname = originalUrl.pathname.replace /^\//, ""

        setHeader = (data) ->
            if not res.getHeader "ETag"
                res.setHeader "ETag", data.length
            if not res.getHeader "Date"
                res.setHeader "Date", new Date().toUTCString()
            if not res.getHeader "Cache-Control"
                res.setHeader "Cache-Control", "public, max-age=0"
            if not res.getHeader "Last-Modified"
                res.setHeader "Last-Modified", new Date().toUTCString()
            if not res.getHeader "Content-Type"
                type = mime.lookup pathname
                charset = mime.charsets.lookup type
                type += if charset then "; charset=" + charset else ""
                res.setHeader "Content-Type", type

        isFile = (pathname) ->
            return files[pathname]

        isDirectory = (pathname) ->
            if pathname is ""
                return true
            else if pathname[pathname.length-1] isnt "/"
                return false
            else
                r = new RegExp "^#{pathname}"
                for name of files
                    return true if r.test name
            false

        contents = (pathname) ->
            r = new RegExp "^#{pathname}"
            strip = new RegExp "^#{pathname}([^/]+).*"

            contents = []
            for name of files
                continue if not r.test name

                clean = name.replace strip, "$1"
                contents.push clean if clean not in contents
            contents.sort()
            contents

        redirect = () ->
            originalUrl.pathname += "/"
            target = url.format(originalUrl)
            res.statusCode = 303
            res.setHeader "Location", target
            res.end "Redirecting to #{target}"

        error = (err) ->
            if err.status is 404
                next()
            else
                next(err)

        if isFile pathname
            data = files[pathname]
            setHeader(data)
            res.write(Buffer(data))
            res.end()
        else if isDirectory pathname
            fs = contents pathname
            fs.unshift ".." if pathname

            up = (num) ->
                dir = []
                dir.push ".." for i in [0...num]
                dir.join("/")

            segments = pathname.split "/"
            segments.unshift ""
            segments.pop()
            segs = segments.map (f, i) ->
                "<a href=\"#{up segments.length-1-i}\">#{f}/</a>"

            links = ("<a class=\"dir\" href=\"#{f}\">#{f}</a>" for f in fs)
            str = dirlisting
                .replace("{directory}", pathname)
                .replace("{segments}", segs.join "")
                .replace("{files}", links.join "")
            res.write(str)
            res.end()
        else if isDirectory pathname+"/"
            redirect()
        else
            next()



readFile = RSVP.denodeify fs.readFile

module.exports = class ExtPipe extends BasePipe
    @schema: ->
        description: "Webserver with optional Testem and Reload integration."
        properties:
            key:
                description: "Private key to use for SSL (default: \"\")"
                type: "string"
            cert:
                description: "Public x509 certificate to use (default: \"\")"
                type: "string"
            port:
                description: "Server port (default: 8613)"
                type: "integer"
            reload:
                description: "Pages to inject reload code to (default: \"\")"
                type: "string"
            middleware:
                description: """
                    Middleware modules to add to the webserver (default: [])
                """
                type: "array"
                items:
                    type: "string"
                    minItems: 1
                    uniqueItems: true

    @configDefaults:
        port: 8613
        reload: null
        middleware: []
        key: ""
        cert: ""

    @stateDefaults:
        files: {}

    init: ->
        @app = express()

        if @config.key and @config.cert
            @server = https.createServer {
                key: fs.readFileSync @config.key
                cert: fs.readFileSync @config.cert
            }, @app
            @ioserver = https.createServer {
                key: fs.readFileSync @config.key
                cert: fs.readFileSync @config.cert
            }
        else
            @server = http.createServer @app
            @ioserver = http.createServer()
        @io = new sio @ioserver, { "log level": 0 }


        @app.use require("body-parser").json({limit: '50mb'})

        for mw in @config.middleware
            @app.use (require path.relative __dirname, mw)(@server)

        @app.use reload(@config.reload) if @config.reload
        @app.use memory(@state.files)


    start: ->
        @server.listen @config.port
        @ioserver.listen @config.port + 1
        protocol = "http#{(if @config.key then "s" else "")}"
        address = "#{protocol}://localhost:#{@config.port}"
        @log "info", "Listening on #{address}"
        super()

    stop: ->
        @server.close()
        @ioserver.close()

    add: (file) ->
        file.add = true
        @state.files[file.name] = ""
        super file

    change: (file) ->
        @state.files[file.name] = file.content
        if /\.css$/.test file.name
            @io.sockets.emit "css"
        else
            @io.sockets.emit "page"
        super file

    unlink: (file) ->
        delete @state.files[file.name]
        @io.sockets.emit "page"
        super file
