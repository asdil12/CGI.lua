--------------------------------------------------------------------------------
-- Title:               CGI.lua
-- Description:         Like a square peg in a round hole
-- Author:              Raphaël Szwarc http://alt.textdrive.com/lua/
-- Creation Date:       February 1, 2006
-- Legal:               Copyright (C) 2006 Raphaël Szwarc
--------------------------------------------------------------------------------

-- import dependencies
local debug = require( "debug" )
local io = require( "io" )
local os = require( "os" )
local string = require( "string" )
local table = require( "table" )

--------------------------------------------------------------------------------
-- Utility functions
--------------------------------------------------------------------------------

local function Copy( aValue )
        if type( aValue ) == "table" then
                local aCopy = {}
                
                for aKey, aValue in pairs( aValue ) do
                        aCopy[ Copy( aKey ) ] = Copy( aValue )
                end
        
                aValue = aCopy
        end

        return aValue
end

local function Log( ... )
        local aLength = select( "#", ... )
        local aBuffer = {}
        
        for anIndex = 1, aLength do
                aBuffer[ #aBuffer + 1 ] = tostring( select( anIndex, ... ) )
        end

        io.stderr:write( os.date( "%m/%d %H:%M:%S", os.time() ), " ", table.concat( aBuffer, "\t" ), "\n" )
end

local encodings = { [ "&" ] = "&amp;", [ "<" ] = "&lt;", [ ">" ] = "&gt;", [ "\"" ] = "&quot;", [ "'" ] = "&apos;" }

function string:encode()
        return ( self:gsub( "%W", encodings ) )
end

--------------------------------------------------------------------------------
-- Meta methods
--------------------------------------------------------------------------------

local Meta = {}

function Meta.__concat( anObject, anotherObject )
        return tostring( anObject ) .. tostring( anotherObject )
end

function Meta.__tostring( anObject )
        return anObject:toString()        
end

--------------------------------------------------------------------------------
-- URL methods
--------------------------------------------------------------------------------

local URL = {}

setmetatable( URL, Meta )

function URL:host()
        return ( os.getenv( "SERVER_NAME" ) or "localhost" ):lower()
end

function URL:path()
        local aPath = os.getenv( "SCRIPT_NAME" ) or ""
        
        aPath = aPath .. ( os.getenv( "PATH_INFO" ) or "/" )
        
        return self:decode( aPath )
end

function URL:port()
        return tonumber( os.getenv( "SERVER_PORT" ) ) or 80
end

function URL:query()
        return os.getenv( "QUERY_STRING" ) or ""
end

function URL:decode( aValue )
        local aFunction = function( aValue )
                return string.char( tonumber( aValue, 16 ) )
        end
        
        aValue = aValue:gsub( "%%(%x%x)", aFunction )
        
        return aValue
end

function URL:decodeParameters( aValue )
        local someParameters = {}
        
        for aKey, aValue in aValue:gmatch( "([^&=]+)=([^&=]+)" ) do
                aKey = aKey:gsub( "+", " " )
                aKey = self:decode( aKey ):lower()
                aValue = aValue:gsub( "+", " " )
                aValue = self:decode( aValue )
                
                someParameters[ aKey ] = aValue
        end
        
        return someParameters
end

function URL:encode( aValue )
        local aFunction = function( aValue )
                return ( "%%%02X" ):format( aValue:byte() )
        end
        
        return ( aValue:gsub( "([^A-Za-z0-9_%-%.])", aFunction ) )
end

function URL:encodeParameters( someValues )
        local aBuffer = {}
        
        for aKey, aValue in pairs( someValues ) do
                aKey = tostring( aKey ):gsub( " ", "+" )
                aBuffer[ #aBuffer + 1 ] = self:encode( aKey ):lower()
                aBuffer[ #aBuffer + 1 ] = "="
                aValue = tostring( aValue ):gsub( " ", "+" )
                aBuffer[ #aBuffer + 1 ] = self:encode( aValue  )
        end
        
        return table.concat( aBuffer, "" )
end

function URL:queries()
        return self:decodeParameters( self:query() )
end

function URL:scheme()
        return ( os.getenv( "SERVER_PROTOCOL" ) or "http" ):match( "(%a+)" ):lower()
end

function URL:toString()
        local aBuffer = {}
        
        aBuffer[ #aBuffer + 1 ] = self:scheme()
        aBuffer[ #aBuffer + 1 ] = "://"
        aBuffer[ #aBuffer + 1 ] = self:host()
        
        if self:port() ~= 80 then
                aBuffer[ #aBuffer + 1 ] = ":"
                aBuffer[ #aBuffer + 1 ] = tostring( self:port() )
        end        
        
        aBuffer[ #aBuffer + 1 ] = self:path()
        
        if self:query() and self:query():len() > 0 then
                aBuffer[ #aBuffer + 1 ] = "?"
                aBuffer[ #aBuffer + 1 ] = self:query()
        end
        
        return table.concat( aBuffer, "" )
end

--------------------------------------------------------------------------------
-- Request methods
--------------------------------------------------------------------------------

local Request = {}

setmetatable( Request, Meta )

function Request:address()
        return os.getenv( "REMOTE_ADDR" ) or ""
end

function Request:authentication()
        return os.getenv( "AUTH_TYPE" ) or ""
end

function Request:content()
        if not self._content then
                local aLength = self:contentLength()
                local aContent = ""
                
                if aLength > 0 then
                        aContent = self:reader():read( aLength )
                end
                
                self._content = aContent or ""
        end
        
        return self._content
end

function Request:contentLength()
        return tonumber( os.getenv( "CONTENT_LENGTH" ) ) or 0
end

function Request:contentType()
        return os.getenv( "CONTENT_TYPE" ) or ""
end

function Request:cookie( aKey )
        local aKey = tostring( aKey ):lower()
        local aCookie = self:cookies()[ aKey ]
        
        if aCookie then
                return aCookie.value, aCookie.options
        end
        
        return nil
end

function Request:cookies()
        local someCookies = {}
        local anHeader = self:header( "cookie" )
        
        if anHeader then
                local aName = nil
        
                -- as per Xavante's Cookies module 
                -- http://www.keplerproject.org/xavante/
                for aKey, aValue in anHeader:gmatch( '([^%s;=]+)%s*=%s*"([^"]*)"' ) do
                        aKey = aKey:lower()

                        if aKey:byte() == 36 then       -- $option
                                if aName then
                                        local anOption = aKey:sub( 2 )
                                        
                                        someCookies[ aName ].options[ anOption ] = aValue
                                end
                        else
                                someCookies[ aKey ] = { value = aValue, options = {} }
                                aName = aKey
                        end
                end
        end
        
        return someCookies
end

function Request:header( aKey )
        local aKey = tostring( aKey ):upper():gsub( "%-", "_" )
        local aValue = os.getenv( aKey )
        
        if not aValue then
                aKey = self:url():scheme():upper() .. "_" .. aKey
                
                aValue = os.getenv( aKey )
        end
        
        return aValue
end

function Request:method()
        return os.getenv( "REQUEST_METHOD" ) or "GET"
end

function Request:parameter( aKey )
        local aKey = tostring( aKey ):lower()
        local someParameters = self:parameters()
        
        return someParameters[ aKey ]
end

function Request:parameters()
        local someParameters = self:url():queries()
        local aType = ( self:header( "content-type" ) or "" ):lower()

        if aType:find( "application/x-www-form-urlencoded", 1, true ) then
                someParameters = self:url():decodeParameters( self:content() )
        end
        
        return someParameters
end

function Request:reader()
        return io.stdin
end

function Request:url()
        return URL
end

function Request:user()
        return os.getenv( "REMOTE_USER" ) or ""
end

function Request:version()
        return os.getenv( "SERVER_PROTOCOL" ) or "HTTP/1.1"
end

function Request:toString()
        local aBuffer = {}
        
        aBuffer[ #aBuffer + 1 ] = self:method()
        aBuffer[ #aBuffer + 1 ] = self:url():toString()
        aBuffer[ #aBuffer + 1 ] = self:version()
        
        return table.concat( aBuffer, " " )
end

--------------------------------------------------------------------------------
-- Response methods
--------------------------------------------------------------------------------

local Response = {}

setmetatable( Response, Meta )

function Response:contentType()
        return self:header( "content-type" )
end

function Response:setContentType( aValue )
        self:setHeader( "content-type", aValue )
        
        return self
end

function Response:cookie( aKey )
        local aKey = tostring( aKey ):lower()
        local aCookie = self:cookies()[ aKey ]
        
        if aCookie then
                return aCookie.value, aCookie.options
        end
        
        return nil
end

function Response:setCookie( aKey, aValue, someOptions )
        local aKey = tostring( aKey ):lower()
        local someCookies = self:cookies()
        
        if not aValue then
                aValue = tostring( nil )
                someOptions = { [ "max-age" ] = 0 }
        end
        
        someCookies[ aKey ] = { value = aValue, options = someOptions }
        
        return self
end

function Response:cookies()
        if not self._cookies then
                self._cookies = Copy( Request:cookies() )
        end
        
        return self._cookies
end

function Response:cookiesHeader()
        local aBuffer = {}
        
        for aName, aCookie in pairs( self:cookies() ) do
                local aFormat = ( '%s="%s";version="1"' ):format( aName, aCookie.value )
                local someOptions = aCookie.options
                
                if someOptions then
                        for aKey, aValue in pairs( someOptions ) do
                                aFormat = aFormat .. ( ';%s="%s"' ):format( aKey:lower(), tostring( aValue ) )
                        end
                end
                                
                aBuffer[ #aBuffer + 1 ] = aFormat
        end
        
        if #aBuffer > 0 then
                return table.concat( aBuffer, "" )
        end
        
        return nil
end

function Response:encoding()
        return "utf-8"
end

function Response:header( aKey )
        local aKey = tostring( aKey ):lower()
        local someHeaders = self:headers()

        return someHeaders[ aKey ]
end

function Response:setHeader( aKey, aValue )
        local aKey = tostring( aKey ):lower()
        local someHeaders = self:headers()
        
        someHeaders[ aKey ] = aValue

        return self
end

function Response:headers()
        if not self._headers then
                local someHeaders = {}
                
                someHeaders[ "content-type" ] = "text/html; charset=" .. self:encoding()
                someHeaders[ "date" ] =  os.date( "!%a, %d %b %Y %H:%M:%S GMT", os.time() )
                someHeaders[ "server" ] =  self:server()

                self._headers = someHeaders
        end
        
        return self._headers
end

function Response:status()
        if not self._status then
                self._status = 200
                self._statusDescription = "OK"
        end
        
        return self._status, self._statusDescription
end

function Response:setStatus( aValue, aDescription )
        self._status = tonumber( aValue )
        self._statusDescription = tostring( aDescription or aValue )
        
        return self
end

function Response:server()
        return os.getenv( "SERVER_SOFTWARE" ) or "CGI.lua"
end

function Response:writeHeaders()
        if not self._writeHeaders then
                local aWriter = self:writer()
                local aSeparator = "\r\n"
                local aStatus, aDescription = self:status()
                local someHeaders = self:headers()
                local aCookieHeader = self:cookiesHeader()
                
                aWriter:write( "status: ", aStatus, " ", aDescription, aSeparator )
                
                for aKey, aValue in pairs( someHeaders ) do
                        aWriter:write( aKey, ": ", tostring( aValue ), aSeparator )
                end
                
                if aCookieHeader then
                        aWriter:write( "set-cookie", ": ", aCookieHeader, aSeparator )
                end
        
                aWriter:write( aSeparator )

                self._writeHeaders = true
        end
        
        return self
end

function Response:write( ... )
        local aWriter = self:writer()
        local aLength = select( "#", ... )
        
        self:writeHeaders()

        for anIndex = 1, aLength do
                local aValue = select( anIndex, ... )
                
                aWriter:write( tostring( aValue ) )
        end
        
        aWriter:flush()
        
        return self
end

function Response:writer()
        return io.stdout
end

function Response:toString()
        local aBuffer = {}
        local aStatus, aDescription = self:status()
        
        aBuffer[ #aBuffer + 1 ] = aStatus
        aBuffer[ #aBuffer + 1 ] = aDescription
        
        return table.concat( aBuffer, " " )
end

--------------------------------------------------------------------------------
-- CGI methods
--------------------------------------------------------------------------------

local CGI = { _DESCRIPTION = "CGI.lua", _VERSION = "1.1" }

setmetatable( CGI, Meta )

function CGI:name()
        return os.getenv( "SCRIPT_NAME" ) or "CGI.lua"
end

function CGI:path()
        return os.getenv( "PATH_TRANSLATED" ) or "."
end

function CGI:request()
        return Request
end

function CGI:response()
        return Response
end

function CGI:log()
        return Log
end

function CGI:print()
        if not self._print then
                self._print = function( ... )
                        self:response():write( ... )
                end
        end
        
        return self._print
end

function CGI:handlerWithMethod( anHandler, aMethod, someMatches )
        if type( anHandler ) == "string" then
                anHandler = require( anHandler )
        end
        
        if type( anHandler ) == "table" then
                table.insert( someMatches, 1, anHandler )

                anHandler = anHandler[ aMethod:lower() ]
        end
        
        if type( anHandler ) == "function" then
                local anEnviromnent = { log = self:log(), print = self:print() }
        
                setmetatable( anEnviromnent, { __index = _G } )

                setfenv( anHandler, anEnviromnent )
        else
                error( "cannot resolve handler '" .. tostring( anHandler ) .. "' of type '" .. type( anHandler ) .. "'" )
        end

        return anHandler, someMatches
end

function CGI:dispatch( someMappings )
        local aName = ( self:name() .. "/" ):gsub( "(%W)", "%%%1" )
        local aMethod = self:request():method()
        local aPath = self:request():url():path()
        
        for anIndex, aMapping in ipairs( assert( someMappings, "missing mappings" ) ) do
                local aPattern = assert( aMapping[ 1 ], "mappings: missing pattern at " .. anIndex )
                local aPattern = "^" .. aName .. aPattern .. "$" 

                if aPath:find( aPattern ) then
                        local someMatches = { aPath:match( aPattern ) }        
                        local anHandler = assert( aMapping[ 2 ], "mappings: missing handler at " .. anIndex )
                        local anHandler, someMatches = self:handlerWithMethod( anHandler, aMethod, someMatches )
                        
                        anHandler( unpack( someMatches ) )
                        
                        return self
                end
        end
        
        self:response():setContentType( "text/plain" )
        self:response():setStatus( 404, "Not Found" )
        self:response():write( "404 Not Found" )

        return self
end

function CGI:run( someMappings )
        local aFunction = function() return self:dispatch( someMappings ) end
        local aStatus, anException = xpcall( aFunction, debug.traceback )
        
        if not aStatus then
                local aContent = "500 Internal Server Error\r\n"
                
                aContent = aContent .. "\r\n" .. tostring( anException ) .. "\r\n"
        
                self:response():setContentType( "text/plain" )
                self:response():setStatus( 500, "Internal Server Error" )
                self:response():write( aContent  )
                
                return nil, anException
        end
        
        return self
end

function CGI:version()
        return os.getenv( "GATEWAY_INTERFACE" ) or "CGI/1.1"
end

function CGI:toString()
        return self:name() 
end

return CGI