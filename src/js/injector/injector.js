console.log("SNP : Injector loaded");

function inject() {
	const injector = document.createElement("script");
	injector.type = "module";
	injector.src = encodeURI("https://steamloopback.host/steam_nano_patcher/ThemeInjector.js");

	document.head.append(injector);
}

if (!document.location.href.match("steamcommunity|steampowered")) {
	inject();
} else {
	addEventListener("DOMContentLoaded", inject);
}
