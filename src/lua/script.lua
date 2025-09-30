local lcpp = require("steam_nano_patcher/lua/lcpp")
local json = require("steam_nano_patcher/lua/JSON")
local url = require("steam_nano_patcher/lua/url")

lcpp.INCLUDE_PATHS = { "steam_nano_patcher/lua/include" }

ffi.cdef [[
void zigsleep(uint64_t ns);
void* allocLoop();
void freeLoop(void* loop);
void initLoop(void* loop);
void deinitLoop(void* loop);
void callLoop(void* loop);
void callLoopSameThread(void* loop);
void execLoop(void* loop);

// No args are passed?

void pushToLoop(void* loop, void* ptr, void* args, size_t len);
void asySpawn(void (*ptr)(), void* args, size_t len);

int bitAND(int a1, int a2);
int64_t bit64AND(int64_t a1, int64_t a2);
int bitOR(int a1, int a2);
int64_t bit64OR(int64_t a1, int64_t a2);
int bitXOR(int a1, int a2);
int64_t bit64XOR(int64_t a1, int64_t a2);
int bitNOT(int a1);
int64_t bit64NOT(int64_t a1);
int bitLSH(int a1, int a2);
int64_t bit64LSH(int64_t a1, int64_t a2);
int bitRSH(int a1, int a2);
int64_t bit64RSH(int64_t a1, int64_t a2);

const uint64_t ns_per_us;
const uint64_t ns_per_ms;
const uint64_t ns_per_s;
const uint64_t ns_per_min;
const uint64_t ns_per_hour;
const uint64_t ns_per_day;
const uint64_t ns_per_week;

// Divisions of a microsecond.
const uint64_t us_per_ms;
const uint64_t us_per_s;
const uint64_t us_per_min;
const uint64_t us_per_hour;
const uint64_t us_per_day;
const uint64_t us_per_week;

// Divisions of a millisecond.
const uint64_t ms_per_s;
const uint64_t ms_per_min;
const uint64_t ms_per_hour;
const uint64_t ms_per_day;
const uint64_t ms_per_week;

// Divisions of a second.
const uint64_t s_per_min;
const uint64_t s_per_hour;
const uint64_t s_per_day;
const uint64_t s_per_week;

void sleep_ms(uint64_t ms);

#include "steam_nano_patcher/lua/civetweb.h"
]]

print("Lua loaded")

local function fn(func)
	return func()
end

local cmg = fn(function()
	if (isCivetDynamic) then
		return ffi.load("civetweb")
	else
		return ffi.C
	end
end)

local CDPID = {
	AttachToTarget = 7800,
	ExposeDP = 7801,
	LogEnable = 7802,
	PageEnable = 7803,
	AddScript = 7804,
	BypassCSP = 7805,
}

local charPtr = ffi.typeof("char[?]")
local buf = charPtr(1)

local pathSep = stdfspath["sep_str"]
local cwd = currentDirectory
local settings = patcherSettings

local dtBindingName = "__snp_devtools_binding__"

local handleMessage
local handleClose

local clientHandler = {
	---@type string
	execScript = nil,
	loop = nil,
	currentConnection = nil,

	writeHandler = function(self, data)
		cmg.mg_websocket_client_write(
			self.currentConnection,
			ffi.C.MG_WEBSOCKET_OPCODE_TEXT,
			data,
			#data
		)
	end,

	attachToPage = function(self, targetID)
		self:writeHandler(json:encode(
			{
				id = CDPID.AttachToTarget,
				method = "Target.attachToTarget",
				params = {
					targetId = targetID,
					flatten = true,
				},
			}
		))

		self:writeHandler(json:encode(
			{
				id = CDPID.ExposeDP,
				method = "Target.exposeDevToolsProtocol",
				params = {
					targetId = targetID,
					bindingName = dtBindingName,
				}
			}
		))
	end,

	textMsg = function(self, data)
		if (settings["debug"] and settings["printRPCMessages"]) then
			print(data)
		end

		local msg = json:decode(data)

		if (msg["id"]) then
			if (msg["error"]) then
				return
			end
		else
			local method = msg["method"]

			if (method == "Target.attachedToTarget") then
				local params = msg["params"]
				local jsContextSessionID = params["sessionId"]

				self:writeHandler(json:encode(
					{
						id = CDPID.LogEnable,
						method = "Log.enable",
						sessionId = jsContextSessionID,
					}
				))

				self:writeHandler(json:encode(
					{
						id = CDPID.PageEnable,
						method = "Page.enable",
						sessionId = jsContextSessionID,
					}
				))

				if (self.execScript ~= nil) then
					self:writeHandler(json:encode(
						{
							id = CDPID.BypassCSP,
							method = "Page.setBypassCSP",
							params = {
								enabled = true,
							},
							sessionId = jsContextSessionID,
						}
					))

					-- Without "runImmediately" it does not run
					--
					-- The "Runtime" domain does not bypass CORS and it cannot
					-- run inside fetched documents

					self:writeHandler(json:encode(
						{
							id = CDPID.AddScript,
							method = "Page.addScriptToEvaluateOnNewDocument",
							params = {
								source = self.execScript,
								runImmediately = true,
							},
							sessionId = jsContextSessionID,
						}
					))
				end
			elseif (method == "Target.targetCreated") then
				local targetInfo = msg["params"]["targetInfo"]

				self:attachToPage(targetInfo["targetId"])
			end
		end
	end,

	connectToDevTools = function(self)
		self:writeHandler(json:encode(
			{
				id = CDPID.AttachToTarget,
				method = "Target.setDiscoverTargets",
				params = {
					discover = true
				},
			}
		))
	end,

	initDevTools = function(self, wsURL)
		local parsed = url.parse(wsURL)

		self.currentConnection = cmg.mg_connect_websocket_client(
			parsed.host,
			settings["steamPort"],
			0,
			nil,
			0,
			parsed.path,
			nil,
			handleMessage,
			handleClose,
			nil
		)

		return (self.currentConnection ~= nil)
	end,

	getDevToolsEntry = function(self)
		local port = settings["steamPort"]

		-- If you don't provide the Host header, the webSocketDebuggerUrl field will have 3 slashes

		local connection = cmg.mg_download(
			"localhost",
			port,
			0,
			buf,
			1,
			"GET /json/version HTTP/1.1\r\nHost: localhost:%d\r\nConnection: close\r\n\r\n",
			port
		)

		if (connection == nil) then
			return nil
		end

		local ret = charPtr(1024)
		local readSize = 0
		local read = 0

		while (true) do
			read = cmg.mg_read(connection, ret, 1024)

			if (read <= 0) then
				break
			end

			readSize = readSize + read
		end

		local parsed = json:decode(ffi.string(ret, readSize))

		if (parsed == nil) then
			cmg.mg_close_connection(connection)

			return nil
		end

		return parsed["webSocketDebuggerUrl"]
	end,

	reconnectToDevTools = function(self)
		local delay = settings["connectionDelay"]

		if (delay == nil) then
			delay = 0.0
		end

		print(string.format("Connecting to Steam with a delay of %d seconds", delay))

		ffi.C.sleep_ms(delay * ffi.C.ms_per_s)

		local ret = false

		local wsURL = self:getDevToolsEntry()

		if (wsURL == nil) then
			return ret
		end

		ret = self:initDevTools(wsURL)

		if (ret == false) then
			return ret
		end

		print("Connected to Steam")

		self:connectToDevTools()

		return ret
	end,

	close = function(self)
		print("Disconnected")

		if (settings["autoreconnect"]) then
			print("Trying to reconnect")

			if (self:reconnectToDevTools()) then
				return
			else
				print("Failed to reconnect")

				self.currentConnection = nil
			end
		end

		ffi.C.deinitLoop(self.loop)
		ffi.C.execLoop(self.loop)
	end,
}

handleMessage = ffi.cast("mg_websocket_data_handler",
	function(connection, flags, data, dataLen, userData)
		local isText = ((ffi.C.bitAND(flags, 0xF) == ffi.C.MG_WEBSOCKET_OPCODE_TEXT))

		if (isText) then
			clientHandler:textMsg(ffi.string(data, dataLen))
		end

		return 1
	end
)

handleClose = ffi.cast("mg_websocket_close_handler",
	function(connection, userData)
		clientHandler:close()
	end
)

local function main()
	cmg.mg_init_library(0)

	clientHandler.loop = ffi.C.allocLoop()
	clientHandler.execScript = fn(function()
		local scriptFile = io.open(cwd .. pathSep .. settings["injectorPath"], "r")

		if (scriptFile == nil) then
			return nil
		end

		local ret = scriptFile:read("a")
		scriptFile:close()

		return ret
	end)

	if (not clientHandler:reconnectToDevTools()) then
		ffi.C.freeLoop(clientHandler.loop)

		error("Steam connection is denied or invalid")
	end

	ffi.C.initLoop(clientHandler.loop)
	ffi.C.callLoopSameThread(clientHandler.loop)

	handleMessage:free()
	handleClose:free()

	ffi.C.freeLoop(clientHandler.loop)
end

main()
