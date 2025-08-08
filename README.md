# Steam Nano Patcher (SNP)

This was made to apply skins to Steam without installing anything else, while being small.

It can also load other binaries to extend its functionality and is compatible with Millennium skin configurations.

# Installation

Steam's CEF debugger must be enabled.

You can do so by either adding a file named `.cef-enable-remote-debugging` inside Steam's folder or starting it with the `-cef-enable-debugging` argument.

After that, get a [binary](https://github.com/x07x08/steam-nano-patcher/releases) or compile one and choose how you want to install it.

## Executable (`exe` folder)

1. Place `src/js/injector/injector.js` / `scripts/injector/injector.js` in `steam_nano_patcher/injector/`, relative to the executable.
2. Place `src/js/ThemeInjector.js` / `scripts/ThemeInjector.js` in `<steamfolder>/steamui/steam_nano_patcher`.
3. Run it alongside Steam.

## Injector / Library (`lib` folder)

> 1 and 2 are the same, but relative to Steam's folder.
3. Add the following code to any of Steam's scripts (`/usr/lib/steam/` or `<steamfolder>/steam.sh`, the former is recommended):

```sh
export SNP_LOADER_PATH="<absolute path to the loader binary>"
export SNP_CURRENT_PROC="$(basename "$0")"
export SNP_SEARCH_PROC="steam"
export LD_PRELOAD="${SNP_LOADER_PATH}${LD_PRELOAD:+:$LD_PRELOAD}"
```

4. Run Steam.

Since Steam is a 32-bit application, the injected code must also be the same architecture.

This is not the case for macOS, as it's 64-bit only.

# Configuration

## Loader

`steam_nano_patcher/settings.json`

```json
{
	"loadOtherModules": false,
	"modules": {
		"steam_nano_patcher": {
			"path": "steam_nano_patcher",
			"entryPoint": "SNPEntryPoint"
		}
	}
}
```

**THE DEFAULT ENTRY MUST BE FIRST OR OTHERS CAN BE LOADED BEFORE IT**.

On Windows and Linux the extension is appended automatically for every module.

## Patcher

`steam_nano_pathcer/patcher_settings.json`

```json
{
	"injectorPath": "steam_nano_patcher/injector/injector.js",
	"steamPort": 8080,
	"debug": false,
	"printRPCMessages": false,
	"autoreconnect": false,
	"exitOnLoopEnd": true,
	"connectionDelay": null
}
```

The `debug` option enables `printRPCMessages` and opens a console on Windows if the loader is a library.

`exitOnLoopEnd` is executable only.

On Linux you might need to change `connectionDelay`. The value is in seconds and should be 3 or more. Windows is delayed already (for some reason).

## Injector configuration

Read [`src/js/injector/injector.js`](https://github.com/x07x08/steam-nano-patcher/blob/main/src/js/injector/injector.js).

All assets loaded using `steamloopback.host` are inside `<steamfolder>/steamui`.

## Skin configuration
Read [`src/js/ThemeInjector.js`](https://github.com/x07x08/steam-nano-patcher/blob/main/src/js/ThemeInjector.js).

# Caveats

1. It cannot load dynamic libraries that have standard entry points (Millennium included).
2. There is no GUI for configuration, only JSON and JavaScript.

# Compilation

[Zig](https://ziglang.org) is needed to compile this.

Read [`build.zig`](https://github.com/x07x08/steam-nano-patcher/blob/main/build.zig) or type `zig build --help` inside the root folder to see the available options.

# Credits

* [Millennium](https://github.com/SteamClientHomebrew/Millennium)
* [SFP](https://github.com/PhantomGamers/SFP)
