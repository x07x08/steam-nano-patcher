# Steam Nano Patcher (SNP)

This was made to apply skins to Steam without installing anything else, while being small.

It can also load other binaries to extend its functionality and is compatible with Millennium skin configurations.

# Installation

Steam's CEF debugger must be enabled.

You can do so by either adding a file named `.cef-enable-remote-debugging` inside Steam's folder or starting it with the `-cef-enable-debugging` argument.

After that, get a [binary](https://github.com/x07x08/steam-nano-patcher/releases) or compile one and choose how you want to install it.

Scripts will be updated independently of tagged releases.

## Executable (`exe` folder)

1. Place `src/js/injector/injector.js` / `scripts/js/injector/injector.js` in `steam_nano_patcher/js/injector`, relative to the executable.
2. Place `src/js/ThemeInjector.js` / `scripts/js/ThemeInjector.js` in `<steamfolder>/steamui/steam_nano_patcher`.
3. Place `src/lua`, the contents of each subfolder from `external/lua` and `external/c/civetweb/civetweb.h` in `steam_nano_patcher/lua`, relative to the executable.
   
   `scripts/lua` can be copied directly instead of manually making the folder.
4. Run it alongside Steam.

## Injector / Library (`lib` folder)

> Steps 1, 2 and 3 are the same, but relative to Steam's folder.

***Linux only***: Add the following code to any of Steam's scripts (`/usr/lib/steam/` or `<steamfolder>/steam.sh`, the former is recommended):

```sh
export SNP_LOADER_PATH="<absolute path to the loader binary>"
export SNP_CURRENT_PROC="$(basename "$0")"
export SNP_SEARCH_PROC="steam"
export LD_PRELOAD="${SNP_LOADER_PATH}${LD_PRELOAD:+:$LD_PRELOAD}"
```

> [!NOTE]
>
> Steam checks the size of `steam.sh` and will replace the script if it's incorrect. Try removing comments from it.
>
> Custom scripts can also be used.
> 
> See https://github.com/SteamClientHomebrew/Millennium/pull/503 and https://github.com/SteamClientHomebrew/Millennium/issues/475
> 

4. Place the dynamic libraries inside Steam's folder.
5. Run Steam.

> [!NOTE]
>
> You might need to restart Steam after it fully finishes loading.
> 
> The patcher will not be injected if Steam wants to update (it executes another binary before the main one) or if it has already updated (the script was reset).
> 
> Since Steam is a 32-bit application, the injected code must also be the same architecture.
> 
> > This is not the case for macOS, as it's 64-bit only.
> 

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

> [!IMPORTANT]
> **THE DEFAULT ENTRY MUST BE FIRST OR OTHERS CAN BE LOADED BEFORE IT**.
>
> No hash checking is done.
>
> On Windows and Linux the extension is appended automatically for every module.

## Patcher

`steam_nano_patcher/patcher_settings.json`

```json
{
	"injectorPath": "steam_nano_patcher/js/injector/injector.js",
	"luaScript": "steam_nano_patcher/lua/script.lua",
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
