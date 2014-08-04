local file = computer.getBootAddress ()
local depo = 'http://istasi.dk/opencomputer/istasiOS/'

local gpu = component.list ( 'gpu',true ) ()
screen = component.list ( 'screen',true ) ()
component.invoke ( gpu, 'bind', screen )
component.invoke ( gpu, 'setBackground', 0x000000 )
component.invoke ( gpu, 'setForeground', 0xFFFFFF )
local size = ({component.invoke ( gpu, 'getResolution' )})

local function clear () component.invoke ( gpu, 'fill', 1,1, size [1],size[2], ' ' ) end
clear ()

local status = {
	['bar'] = {
		['size'] = {
			['width'] = math.floor(size[1]/4),
			['height'] = 1,
		},
		['position'] = {
			['x'] = math.floor ( (size[1] - math.floor(size[1]/4)) / 2 ),
			['y'] = math.floor ( (size[2]) / 2 ),
		},
		['bgColor'] = 0x000000,
		['fgColor'] = 0xFFFFFF,
		['abColor'] = 0x990000,
		['afColor'] = 0xFFFFFF,

		['char'] = {
			['fill']  = ' ',
			['start'] = '[',
			['end']   = ']',
		},

		['clear'] = function ( self )
			if component.invoke ( gpu, 'getForeground' ) ~= self.fgColor then component.invoke ( gpu, 'setForeground', self.fgColor ) end
			if component.invoke ( gpu, 'getBackground' ) ~= self.bgColor then component.invoke ( gpu, 'setBackground', self.bgColor ) end

			for h = 1,self.size.height do
				component.invoke ( gpu, 'set', self.position.x,self.position.y + h - 1, self.char ['start'] .. string.rep ( self.char ['fill'], (self.size.width - 2) ) .. self.char ['end'] )
			end
		end,
		['set'] = function ( self, procent )
			local str = self.char ['start'] .. string.rep ( self.char ['fill'], (self.size.width - 2) ) .. self.char ['end']

			if component.invoke ( gpu, 'getForeground' ) ~= self.afColor then component.invoke ( gpu, 'setForeground', self.afColor ) end
			if component.invoke ( gpu, 'getBackground' ) ~= self.abColor then component.invoke ( gpu, 'setBackground', self.abColor ) end

			for h = 1,self.size.height do
				component.invoke ( gpu, 'set', self.position.x,self.position.y + h - 1, str:sub (1,#str * procent) )
			end
		end,
	},
	['message'] = {
		['position'] = {
			['x'] = math.floor ( size[1] / 2 ) - 1,
			['y'] = math.floor ( size[2] / 2 ) - 1,
		},
		['fgColor'] = 0xFFFFFF,
		['bgColor'] = 0x000000,

		['lastMessage'] = 1,

		['write'] = function ( self, message )
			if component.invoke ( gpu, 'getForeground' ) ~= self.fgColor then component.invoke ( gpu, 'setForeground', self.fgColor ) end
			if component.invoke ( gpu, 'getBackground' ) ~= self.bgColor then component.invoke ( gpu, 'setBackground', self.bgColor ) end

			if message:match ( '^[Ee]rror' ) then component.invoke ( gpu, 'setForeground', 0xFF0000 ) end

			if self.lastMessage > #message then
				local pad = math.ceil ( (self.lastMessage - #message) / 2 )
				self.lastMessage = #message

				message = string.rep ( ' ', pad ) .. message .. string.rep ( ' ', pad )
			else
				self.lastMessage = #message
			end

			local x = self.position.x - math.floor(#message / 2)

			component.invoke ( gpu, 'set', x,self.position.y, message )
			
		end,
	},
}

status.message:write ( 'Creating various boot tools' )
local function stall () while true do computer.pullSignal () end end
local function download ( url, _file )
	local internet = component.list ( 'internet' ) ()
	if internet == nil then return false end

	local urlHandle = component.invoke ( internet, 'request', url )

	local content = ''
	local continue = true

	while continue == true do
		local line = component.invoke ( internet, 'read', urlHandle )
		if line == nil then
			continue = false
		else
			content = content .. line
		end
	end
	component.invoke ( internet, 'close', urlHandle )

	if _file == false then
		return content
	end

	local fileHandle = component.invoke ( file, 'open', _file, 'w' )
	if fileHandle == nil then
		clear ()
		status.message:write ( 'Error while download (' .. url ..', '.. _file ..')' )

		stall ()
	end
	component.invoke ( file, 'write', fileHandle, content )
	component.invoke ( file, 'close', fileHandle )

	return true
end

local function loadfile ( _file )
	if component.invoke ( file, 'exists', _file ) == false then
		clear ()
		status.message:write ( 'Error while loadfile ('.. _file .. ').' )

		stall ()
	end

	local fileHandle = component.invoke ( file, 'open', _file, 'r' )

	local content = ''
	local continue = true

	while continue == true do
		local line = component.invoke ( file, 'read', fileHandle, 1024 )
		if line == nil then
			continue = false
		else
			content = content .. line
		end
	end
	component.invoke ( file, 'close', fileHandle )

	local func, reason = load ( content, '=' .. _file, 't', _G )
	if type(func) ~= 'function' or reason ~= nil then
		clear ()
		status.message:write ( 'Error while loadfile ('.. _file .. '): ' .. tostring(reason) )

		stall ()
	end

	local state, reason = pcall ( func )
	if state == false or state == nil then
		clear ()
		status.message:write ( 'Error while loadfile ('.. _file .. '): ' .. tostring(reason) )

		stall ()
	end

	return reason
end

local function mkdir ( path )
	if component.invoke ( file, 'exists', path ) == false then
		if component.invoke ( file, 'makeDirectory', path ) == false then
			clear ()
			status.message:write ( 'Error while makeDirectory (' .. path .. ').' )

			stall ()
		end
	end
end

local content = download ( depo .. 'config/version/version.db?1', false )
if content ~= false then
	local files = {}


	status.message:write ( 'File checking' )
	status.bar:clear ()

	local list = {}
	for line in content:gmatch ( '([^%\n]*)\n?' ) do
		local _file, timestamp = line:match ( '(.-) ?%: ?(.*)' )
		if _file ~= nil then
			if _file:sub(1,2) == './' then _file = _file:sub(3) end

			if _file ~= 'init.lua' then
				table.insert ( list, _file )
			end
		end
	end

	for i, _file in ipairs ( list ) do
		local path = ''
		local bits = {}

		for bit in _file:gmatch ( '([^%/]*/?)' ) do
			path = path .. bit
			
			if path:match ('%/$') then
				if path:sub(1,1) == '/' then path = path:sub(2) end

				if component.invoke ( file, 'exists', path ) == false then
					mkdir ( path )
				end
			end
		end

		status.message:write ( _file )
		download ( depo .. _file, _file )
		status.bar:set ( i / #list )
	end
end

status.message:write ( 'loading system' )
if component.invoke ( file, 'exists', 'boot/load' ) == false then
	clear ()
	status.message:write ( 'Error while loading system: No files to load' )

	stall ()
end

status.bar.abColor = 0x009900
local list = component.invoke ( file, 'list', 'boot/load' )
if type(list) ~= 'table' then
	clear ()
	status.message:write ( 'Error while attempting to list: boot/load' )

	stall ()
end

for i, _file in ipairs (list) do
	_G [ _file:match( '(.-)%.lua') ] = loadfile ( 'boot/load/' .. _file )
	status.bar:set ( i / #list )
end

status.message:write ( 'Starting system' )
local reason = loadfile ( 'start.lua' )

gpu = component.list( 'gpu', true ) ()
if type(reason) ~= 'string' then
	reason = 'System stopped unexpectedly' 
end

component.invoke ( gpu, 'setBackground', 0x000000 )
clear ()

local lines = {}
table.insert ( lines, "EventHandler returned: " )
for line in reason:gmatch ( '(.-)\n' ) do
	table.insert ( lines, line )
end
if #lines < 2 then table.insert ( lines, reason ) end

local longest = 1
for _,line in ipairs ( lines ) do
	longest = math.max ( longest, line:len () )
end

component.invoke ( gpu, 'setForeground', 0xFF0000 )
local size = ({component.invoke ( gpu, 'getResolution' )})
if size == nil then
	component.invoke ( gpu, 'bind', component.list('screen',true)())
	size = ({component.invoke( gpu, 'getResolution')})
end
if size == nil then size = {80,25} end

local x = size[1] / 2
x = x - (longest / 2)

local y = size[2] / 2
y = y - (#lines / 2)

for i,line in ipairs ( lines ) do
	component.invoke ( gpu, 'set', x,y + i, tostring(line:gsub('%\t','  ')) )
end

stall ()