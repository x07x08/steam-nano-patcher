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

local function fn(func)
	func()
end

local cmg = ffi.C

if (isCivetDynamic) then
	cmg = ffi.load("civetweb")
end

local pathSep = stdfspath["sep_str"]
local cwd = currentDirectory
local settings = patcherSettings

local dtBindingName = "__snp_devtools_binding__"

local CDPID = {
	AttachToTarget = 7800,
	ExposeDP = 7801,
	LogEnable = 7802,
	PageEnable = 7803,
	AddScript = 7804,
	BypassCSP = 7805,
}

local charPtr = ffi.typeof("char[?]")

print("Lua loaded")

local loop = ffi.C.allocLoop()
local buf = charPtr(1)

local handleMessage
local handleClose
local currentConnection

---@type string
local execScript

fn(function()
	local scriptFile = io.open(cwd .. pathSep .. settings["injectorPath"], "r")

	if (scriptFile == nil) then
		return
	end

	execScript = scriptFile:read("a")
	scriptFile:close()
end)

local function writeHandler(data)
	cmg.mg_websocket_client_write(
		currentConnection,
		ffi.C.MG_WEBSOCKET_OPCODE_TEXT,
		data,
		#data
	)
end

local function attachToPage(targetID)
	writeHandler(json:encode(
		{
			id = CDPID.AttachToTarget,
			method = "Target.attachToTarget",
			params = {
				targetId = targetID,
				flatten = true,
			},
		}
	))

	writeHandler(json:encode(
		{
			id = CDPID.ExposeDP,
			method = "Target.exposeDevToolsProtocol",
			params = {
				targetId = targetID,
				bindingName = dtBindingName,
			}
		}
	))
end

local function textMsg(data)
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

			writeHandler(json:encode(
				{
					id = CDPID.LogEnable,
					method = "Log.enable",
					sessionId = jsContextSessionID,
				}
			))

			writeHandler(json:encode(
				{
					id = CDPID.PageEnable,
					method = "Page.enable",
					sessionId = jsContextSessionID,
				}
			))

			if (execScript ~= nil) then
				writeHandler(json:encode(
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

				writeHandler(json:encode(
					{
						id = CDPID.AddScript,
						method = "Page.addScriptToEvaluateOnNewDocument",
						params = {
							source = execScript,
							runImmediately = true,
						},
						sessionId = jsContextSessionID,
					}
				))
			end
		elseif (method == "Target.targetCreated") then
			local targetInfo = msg["params"]["targetInfo"]

			attachToPage(targetInfo["targetId"])
		end
	end
end

local function connectToDevTools()
	writeHandler(json:encode(
		{
			id = CDPID.AttachToTarget,
			method = "Target.setDiscoverTargets",
			params = {
				discover = true
			},
		}
	))
end

local function initDevTools(wsURL)
	local parsed = url.parse(wsURL)

	currentConnection = cmg.mg_connect_websocket_client(
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

	return (currentConnection ~= nil)
end

local function getDevToolsEntry()
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
end

local function reconnectToDevTools()
	local delay = settings["connectionDelay"]

	if (delay == nil) then
		delay = 0.0
	end

	print(string.format("Connecting to Steam with a delay of %d seconds", delay))

	ffi.C.sleep_ms(delay * ffi.C.ms_per_s)

	local ret = false

	local wsURL = getDevToolsEntry()

	if (wsURL == nil) then
		return ret
	end

	ret = initDevTools(wsURL)

	if (ret == false) then
		return ret
	end

	print("Connected to Steam")

	connectToDevTools()

	return ret
end

handleMessage = ffi.cast("mg_websocket_data_handler",
	function(connection, flags, data, dataLen, userData)
		local isText = ((ffi.C.bitAND(flags, 0xF) == ffi.C.MG_WEBSOCKET_OPCODE_TEXT))

		if (isText) then
			textMsg(ffi.string(data, dataLen))
		end

		return 1
	end
)

local function close()
	print("Disconnected")

	if (settings["autoreconnect"]) then
		print("Trying to reconnect")

		if (reconnectToDevTools()) then
			return
		else
			print("Failed to reconnect")

			currentConnection = nil
		end
	end

	ffi.C.deinitLoop(loop)
	ffi.C.execLoop(loop)
end

handleClose = ffi.cast("mg_websocket_close_handler",
	function(connection, userData)
		close()
	end
)

local function main()
	cmg.mg_init_library(0)

	if (not reconnectToDevTools()) then
		ffi.C.freeLoop(loop)

		error("Steam connection is denied or invalid")
	end

	ffi.C.initLoop(loop)
	ffi.C.callLoopSameThread(loop)

	handleMessage:free()
	handleClose:free()

	ffi.C.freeLoop(loop)
end

main()
