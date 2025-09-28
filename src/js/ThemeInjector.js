console.log("SNP : Theme Injector loaded");

// Configuration chunk

/**
 * @type {defaultPatches}
*/

const customPatches = [];

/**
 * @type {defaultPatches}
*/

let patchesList = [].concat(customPatches);

// Millennium skin configs can be added here
// Add the path that contains the "skins.json" file with a trailing slash
//
// <Skin Name>: <Path>
// string: string
//

const millenniumSkins = {};

// Millennium skin conditionals
// If there is a match in the config, it will be added to the list of patches
//
// <Skin Name>: { <Condition>: <Value> }
// string: { string: string }
//

const millenniumConditionals = {};

// Code chunk

const steamHostURL = "https://steamloopback.host/";
const jsContextTitle = "SharedJSContext";

/**
 * @typedef Patch
 * 
 * @prop {RegExp[]} MatchRegexString
 * @prop {string} TargetCss
 * @prop {string} TargetJs
*/

/**
 * @param {RegExp[]} MatchRegexString
 * @param {string} TargetCss
 * @param {string} TargetJs
 * 
 * @returns {Patch}
*/

function Patch(MatchRegexString, TargetCss = null, TargetJs = null) {
	return {
		MatchRegexString: MatchRegexString,
		TargetCss: TargetCss,
		TargetJs: TargetJs,
	};
}

// Millennium defaults

const defaultPatches = [
	Patch(
		[
			'https://.*.steampowered.com',
			'https://steamcommunity.com',
		],
		'webkit.css', 'webkit.js'
	),
	Patch(
		[
			'^Steam$',
			'^OverlayBrowser_Browser$',
			'^SP Overlay:',
			'Menu$',
			'Supernav$',
			'^notificationtoasts_',
			'^SteamBrowser_Find$',
			'^OverlayTab\\d+_Find$',
			'.ModalDialogPopup',
			'.FullModalOverlay',
		],
		'libraryroot.custom.css', 'libraryroot.custom.js'
	),
	Patch(
		[
			'^Steam Big Picture Mode$',
			'^QuickAccess_',
			'^MainMenu_',
		],
		'bigpicture.custom.css', 'bigpicture.custom.js'),
	Patch(['.friendsui-container'], 'friends.custom.css', 'friends.custom.js'),
];

for (const skin in millenniumSkins) {
	loadMillenniumSkin(skin, millenniumSkins[skin]);
}

if (Object.keys(millenniumSkins).length == 0) {
	for (const patch of patchesList) {
		matchPatch(patch);
	}
}

function safeQuery(elem, selector) {
	try {
		return elem.querySelector(selector);
	} catch {
		return null;
	}
}

/**
 * @param {Patch} patch
*/

function matchPatch(patch) {
	for (const pattern of patch.MatchRegexString) {
		// Injecting in SharedJSContext also injects in the main Steam frame

		if (((document.title == jsContextTitle) && (pattern != jsContextTitle)) ||
			!(
				(document.title.match(pattern)) ||
				((pattern.search("://") != -1) && document.location.href.match(pattern)) ||
				safeQuery(document, pattern) ||
				safeQuery(document, "." + pattern)
			)
		) {
			continue;
		}

		loadPatch(patch);

		return;
	}
}

/**
 * @param {Patch} patch
*/

function loadPatch(patch) {
	if (patch.TargetJs) {
		const url = encodeURI(steamHostURL + patch.TargetJs);

		fetch(url).then((response) => {
			if (!response.ok) return;

			const js = document.createElement("script");
			js.src = url;
			js.type = "module";

			document.head.append(js);
		});
	}

	if (patch.TargetCss) {
		const url = encodeURI(steamHostURL + patch.TargetCss);

		fetch(url).then((response) => {
			if (!response.ok) return;

			const css = document.createElement("link");
			css.rel = "stylesheet";
			css.href = url;
			css.type = "text/css";

			document.head.append(css);
		});
	}
}

/**
 * @param {string} skin
 * @param {string} path
*/

function loadMillenniumSkin(skin, path) {
	const configURL = steamHostURL + path + "skin.json";

	fetch(configURL).then((response) => {
		if (!response.ok) return;

		response.json().then((json) => {
			parseMillenniumSkin(json, skin, path);

			for (const patch of patchesList) {
				matchPatch(patch);
			}
		});
	});
}

function parseMillenniumSkin(json, skin, path) {
	if (json.UseDefaultPatches) {
		for (const patch of defaultPatches) {
			patchesList.push(
				Patch(patch.MatchRegexString,
					makeSkinPath(path, patch.TargetCss),
					makeSkinPath(path, patch.TargetJs)
				)
			);
		}
	}

	if (json.Patches) {
		for (const patch of json.Patches) {
			patchesList.push(
				Patch([patch.MatchRegexString],
					makeSkinPath(path, patch.TargetCss),
					makeSkinPath(path, patch.TargetJs)
				)
			);
		}
	}

	if (json.Conditions) {
		const jcref = json.Conditions;

		for (const condition in jcref) {
			const cref = jcref[condition];

			const savedSkin = millenniumConditionals[skin];

			let toPush = cref.default;

			if (savedSkin) {
				const savedValue = savedSkin[condition];

				if (savedValue &&
					cref.values[savedValue]) {
					toPush = savedSkin[condition];
				}
			}

			const pref = cref.values[toPush];

			// Some skins can have broken default values
			// Haven't checked if Millennium ignores them

			if (!pref) continue;

			let tref = null;

			if (pref.TargetCss) {
				tref = pref.TargetCss;

				patchesList.push(Patch(tref.affects, makeSkinPath(path, tref.src)));
			}

			if (pref.TargetJs) {
				tref = pref.TargetJs;

				patchesList.push(Patch(tref.affects, null, makeSkinPath(path, tref.src)));
			}
		}
	}

	// Might load it twice

	const webkitFile = json["Steam-WebKit"];

	if (webkitFile) {
		patchesList.push(Patch(defaultPatches[0].MatchRegexString, makeSkinPath(path, webkitFile), null));
	}

	const colorsFile = json["RootColors"];

	if (colorsFile) {
		patchesList.push(Patch([".*"], makeSkinPath(path, colorsFile), null));
	}
}

function makeSkinPath(path, value) {
	if (value) return path + value;

	return null;
}
